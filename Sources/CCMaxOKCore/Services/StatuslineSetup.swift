import Foundation

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
        var settings: [String: Any] = [:]

        let settingsPath = fileAccess.settingsPath
        if FileManager.default.fileExists(atPath: settingsPath.path()) {
            let data = try Data(contentsOf: settingsPath)
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
        guard fm.fileExists(atPath: fileAccess.settingsPath.path()) else { return false }

        guard let data = try? Data(contentsOf: fileAccess.settingsPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let statusLine = json["statusLine"] as? [String: Any],
              let command = statusLine["command"] as? String else {
            return false
        }
        return command.contains("statusline.sh")
    }

    public static func setup(fileAccess: FileAccessManager) throws {
        try deployScript(fileAccess: fileAccess)
        try patchSettings(fileAccess: fileAccess)
    }
}
