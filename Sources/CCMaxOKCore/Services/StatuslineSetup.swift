import Foundation
import os

public enum StatuslineSetup {

    public static func deployScript(fileAccess: FileAccessManager) throws {
        let scriptContent = """
        #!/bin/bash
        cat /dev/stdin > \(fileAccess.liveStatusPath.path())
        """

        try fileAccess.ensureCCMaxOKDirectory()
        let scriptPath = fileAccess.statuslineScriptPath
        try scriptContent.write(to: scriptPath, atomically: true, encoding: .utf8)

        // Make executable
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: scriptPath.path()
        )
    }

    public static func patchSettings(fileAccess: FileAccessManager) throws {
        // Patch primary settings.json
        try patchSingleSettings(at: fileAccess.settingsPath, fileAccess: fileAccess)

        // Also patch settings.json in other existing config directories
        for path in fileAccess.allSettingsPaths where path != fileAccess.settingsPath {
            do {
                try patchSingleSettings(at: path, fileAccess: fileAccess)
            } catch {
                CCMaxOKCore.logger.warning("Failed to patch settings at \(path.path()): \(error.localizedDescription)")
            }
        }
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

    public static func setup(fileAccess: FileAccessManager) throws {
        try deployScript(fileAccess: fileAccess)
        try patchSettings(fileAccess: fileAccess)
    }
}
