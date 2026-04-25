import Foundation
import os

public enum SetupOutcome: Equatable, Sendable {
    /// 기존 훅이 없어 haru를 신규 설치
    case installed
    /// haru 훅이 이미 존재하여 변경 없음
    case alreadyInstalled
    /// 다른 도구의 statusLine 명령어를 감쌌음
    case wrappedExisting(command: String)
}

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

    /// origin v1.1.6의 `SetupOutcome`(설치 종류)과 우리 다중 settings.json 패치 결과(succeeded/failures)를
    /// 모두 담는 통합 결과. UI는 `outcome`으로 wrap/installed 분기를 표시하고, `failures`로 일부 보조
    /// config 디렉토리 패치가 실패한 케이스를 노출한다.
    public struct PatchResult: Sendable, Equatable {
        public let outcome: SetupOutcome
        public let succeeded: [URL]
        public let failures: [SettingsPatchFailure]
        public var hasFailures: Bool { !failures.isEmpty }
    }

    /// Primary settings.json 패치는 실패 시 throw(기존 동작 유지).
    /// 보조 config 디렉토리(CLAUDE_CONFIG_DIR의 추가 경로 등) 패치 실패는 `failures`로 수집.
    @discardableResult
    public static func patchSettings(fileAccess: FileAccessManager) throws -> PatchResult {
        var succeeded: [URL] = []
        var failures: [SettingsPatchFailure] = []
        var aggregateOutcome: SetupOutcome = .alreadyInstalled

        let primaryOutcome = try patchSingleSettings(at: fileAccess.settingsPath, fileAccess: fileAccess)
        succeeded.append(fileAccess.settingsPath)
        aggregateOutcome = mergeOutcome(aggregateOutcome, primaryOutcome)

        for path in fileAccess.allSettingsPaths where path != fileAccess.settingsPath {
            do {
                let outcome = try patchSingleSettings(at: path, fileAccess: fileAccess)
                succeeded.append(path)
                aggregateOutcome = mergeOutcome(aggregateOutcome, outcome)
            } catch {
                failures.append(SettingsPatchFailure(path: path, reason: error.localizedDescription))
                DiagnosticsLogger.shared.warn("setup", "Failed to patch settings at \(path.path())", error: error)
            }
        }
        return PatchResult(outcome: aggregateOutcome, succeeded: succeeded, failures: failures)
    }

    /// Priority: wrappedExisting > installed > alreadyInstalled
    private static func mergeOutcome(_ a: SetupOutcome, _ b: SetupOutcome) -> SetupOutcome {
        func rank(_ o: SetupOutcome) -> Int {
            switch o {
            case .wrappedExisting: return 2
            case .installed: return 1
            case .alreadyInstalled: return 0
            }
        }
        return rank(b) >= rank(a) ? b : a
    }

    private static func patchSingleSettings(
        at settingsPath: URL,
        fileAccess: FileAccessManager
    ) throws -> SetupOutcome {
        var settings: [String: Any] = [:]

        if FileManager.default.fileExists(atPath: settingsPath.path()) {
            let data = try Data(contentsOf: settingsPath)

            // 패치 전 백업
            let backupPath = settingsPath.deletingPathExtension().appendingPathExtension("json.backup")
            do {
                try data.write(to: backupPath, options: .atomic)
            } catch {
                DiagnosticsLogger.shared.warn("setup", "Settings backup failed at \(backupPath.path())", error: error)
            }

            if let existing = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                settings = existing
            }
        }

        let ourScriptPath = fileAccess.statuslineScriptPath.path()
        var outcome: SetupOutcome = .installed

        if let existingStatusLine = settings["statusLine"] as? [String: Any],
           let existingCommand = existingStatusLine["command"] as? String {
            if existingCommand == ourScriptPath {
                // 이미 우리 스크립트를 가리키는 경우 — 파일 변경 없이 반환
                DiagnosticsLogger.shared.info("setup", "haru statusline already installed at \(settingsPath.path()); no changes")
                return .alreadyInstalled
            } else if existingCommand.contains("ccmaxok") && existingCommand.contains("statusline.sh") {
                // 레거시 haru 경로(다른 위치) — 경로만 정규화
                outcome = .installed
            } else {
                // 타 도구를 감쌈 — wrapped-command.txt에 원본 저장
                try existingCommand.write(
                    to: fileAccess.wrappedCommandPath,
                    atomically: true,
                    encoding: .utf8
                )
                DiagnosticsLogger.shared.info("setup", "Wrapped existing statusline at \(settingsPath.path()): \(existingCommand)")
                outcome = .wrappedExisting(command: existingCommand)
            }
        } else {
            // statusLine 없음 — stale wrapped-command.txt 정리
            let wrappedPath = fileAccess.wrappedCommandPath
            if FileManager.default.fileExists(atPath: wrappedPath.path()) {
                try? FileManager.default.removeItem(at: wrappedPath)
            }
            DiagnosticsLogger.shared.info("setup", "Installed haru statusline at \(settingsPath.path()) (no existing command)")
        }

        // 기존 statusLine dict의 다른 키(예: padding)는 보존하고 type/command만 갱신
        var statusLine = (settings["statusLine"] as? [String: Any]) ?? [:]
        statusLine["type"] = "command"
        statusLine["command"] = ourScriptPath
        settings["statusLine"] = statusLine

        let data = try JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: settingsPath, options: .atomic)

        return outcome
    }

    public static func expectedScriptContent(fileAccess: FileAccessManager) -> String {
        // 1) live-status.json은 tmp + mv로 atomic 교체 → 읽는 쪽이 깨진 JSON을 보지 않도록 경합 제거.
        // 2) wrapped-command.txt가 있으면 그 명령어로 동일 stdin을 위임 → 경쟁 statusline 도구와 공존.
        let liveStatusPath = fileAccess.liveStatusPath.path()
        let wrappedPath = fileAccess.wrappedCommandPath.path()
        return """
        #!/bin/bash
        # haru statusline wrapper — atomic live-status write + delegate to any pre-existing statusline.
        INPUT=$(cat)
        tmp='\(liveStatusPath).tmp.'$$
        trap 'rm -f "$tmp"' EXIT
        printf '%s' "$INPUT" > "$tmp" 2>/dev/null && mv -f "$tmp" '\(liveStatusPath)' 2>/dev/null || true
        WRAPPED_FILE='\(wrappedPath)'
        if [ -s "$WRAPPED_FILE" ]; then
          WRAPPED_CMD=$(cat "$WRAPPED_FILE")
          if [ -n "$WRAPPED_CMD" ]; then
            printf '%s' "$INPUT" | eval "$WRAPPED_CMD" || true
          fi
        fi
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

    /// 현재 감싸고 있는 기존 statusline 명령어를 반환 (없으면 nil)
    public static func wrappedCommand(fileAccess: FileAccessManager) -> String? {
        let path = fileAccess.wrappedCommandPath
        guard let raw = try? String(contentsOf: path, encoding: .utf8) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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
