import Foundation
import os

public enum StatuslineSetup {

    public static func deployScript(fileAccess: FileAccessManager) throws {
        let scriptContent = expectedScriptContent(fileAccess: fileAccess)

        try fileAccess.ensureCCMaxOKDirectory()
        let scriptPath = fileAccess.statuslineScriptPath
        try scriptContent.write(to: scriptPath, atomically: true, encoding: .utf8)

        // Make executable
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: scriptPath.path()
        )
    }

    public struct SettingsPatchFailure: Sendable, Equatable {
        public let path: URL
        public let reason: String
    }

    public struct PatchResult: Sendable, Equatable {
        public let succeeded: [URL]
        public let failures: [SettingsPatchFailure]
        public var hasFailures: Bool { !failures.isEmpty }
    }

    /// Primary settings.json 패치는 실패 시 throw(기존 동작 유지).
    /// 보조 config 디렉토리(CLAUDE_CONFIG_DIR의 추가 경로 등) 패치 실패는 결과로 반환.
    @discardableResult
    public static func patchSettings(fileAccess: FileAccessManager) throws -> PatchResult {
        var succeeded: [URL] = []
        var failures: [SettingsPatchFailure] = []

        try patchSingleSettings(at: fileAccess.settingsPath, fileAccess: fileAccess)
        succeeded.append(fileAccess.settingsPath)

        for path in fileAccess.allSettingsPaths where path != fileAccess.settingsPath {
            do {
                try patchSingleSettings(at: path, fileAccess: fileAccess)
                succeeded.append(path)
            } catch {
                failures.append(SettingsPatchFailure(path: path, reason: error.localizedDescription))
                CCMaxOKCore.logger.warning("Failed to patch settings at \(path.path()): \(error.localizedDescription)")
            }
        }
        return PatchResult(succeeded: succeeded, failures: failures)
    }

    private static func patchSingleSettings(at settingsPath: URL, fileAccess: FileAccessManager) throws {
        var settings: [String: Any] = [:]

        if FileManager.default.fileExists(atPath: settingsPath.path()) {
            let data = try Data(contentsOf: settingsPath)

            // 패치 전 백업
            let backupPath = settingsPath.deletingPathExtension().appendingPathExtension("json.backup")
            do {
                try data.write(to: backupPath, options: .atomic)
            } catch {
                CCMaxOKCore.logger.warning("Settings backup failed at \(backupPath.path()): \(error.localizedDescription)")
            }

            if let existing = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                settings = existing
            }
        }

        // Only patch if no statusLine exists or it already points to our script
        if let existingStatusLine = settings["statusLine"] as? [String: Any],
           let existingCommand = existingStatusLine["command"] as? String,
           !existingCommand.contains("ccmaxok") {
            // Don't overwrite user's existing statusline config
            return
        }

        settings["statusLine"] = [
            "type": "command",
            "command": fileAccess.statuslineScriptPath.path()
        ] as [String: String]

        let data = try JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: settingsPath, options: .atomic)
    }

    public static func expectedScriptContent(fileAccess: FileAccessManager) -> String {
        // tmp 파일에 쓰고 mv로 교체 → haru가 쓰는 중인 파일을 읽어 JSON이 깨지는 경합을 제거.
        // 비정상 종료 시에도 tmp 누적 방지 위해 EXIT trap 사용.
        let finalPath = fileAccess.liveStatusPath.path()
        return """
        #!/bin/bash
        set -e
        tmp="\(finalPath).tmp.$$"
        trap 'rm -f "$tmp"' EXIT
        cat /dev/stdin > "$tmp"
        mv -f "$tmp" "\(finalPath)"
        """
    }

    public static func scriptNeedsUpdate(fileAccess: FileAccessManager) -> Bool {
        let fm = FileManager.default
        let scriptPath = fileAccess.statuslineScriptPath
        guard fm.fileExists(atPath: scriptPath.path()) else { return true }

        guard let current = try? String(contentsOf: scriptPath, encoding: .utf8) else { return true }
        let expected = expectedScriptContent(fileAccess: fileAccess)
        return current != expected
    }

    public static func isSetupComplete(fileAccess: FileAccessManager) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileAccess.statuslineScriptPath.path()) else { return false }

        // Check if any settings.json has the statusline hook configured
        let pathsToCheck = [fileAccess.settingsPath] + fileAccess.allSettingsPaths
        for settingsPath in Set(pathsToCheck.map { $0.path }) {
            let url = URL(fileURLWithPath: settingsPath)
            guard let data = try? Data(contentsOf: url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let statusLine = json["statusLine"] as? [String: Any],
                  let command = statusLine["command"] as? String else {
                continue
            }
            if command.contains("statusline.sh") {
                return true
            }
        }
        return false
    }

    @discardableResult
    public static func setup(fileAccess: FileAccessManager) throws -> PatchResult {
        try deployScript(fileAccess: fileAccess)
        return try patchSettings(fileAccess: fileAccess)
    }

    public struct StatuslineConflict: Sendable, Equatable {
        public let settingsPath: URL
        public let projectPath: URL
        public let overridingCommand: String
    }

    /// Scan recent project dirs (e.g. cmux worktrees) for local `.claude/settings*.json`
    /// whose `statusLine.command` is set to something other than our ccmaxok script.
    /// Such overrides silently prevent haru from receiving data for that project.
    public static func projectLocalStatuslineConflicts(
        fileAccess: FileAccessManager,
        projectLimit: Int = 20
    ) -> [StatuslineConflict] {
        let ourScript = fileAccess.statuslineScriptPath.path
        let fm = FileManager.default
        var conflicts: [StatuslineConflict] = []

        for project in fileAccess.recentProjectPaths(limit: projectLimit) {
            let candidates = [
                project.appendingPathComponent(".claude/settings.json"),
                project.appendingPathComponent(".claude/settings.local.json")
            ]
            for settingsURL in candidates {
                guard fm.fileExists(atPath: settingsURL.path),
                      let data = try? Data(contentsOf: settingsURL),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let statusLine = json["statusLine"] as? [String: Any],
                      let command = statusLine["command"] as? String
                else { continue }

                if command != ourScript && !command.contains("ccmaxok") {
                    conflicts.append(StatuslineConflict(
                        settingsPath: settingsURL,
                        projectPath: project,
                        overridingCommand: command
                    ))
                }
            }
        }
        return conflicts
    }
}
