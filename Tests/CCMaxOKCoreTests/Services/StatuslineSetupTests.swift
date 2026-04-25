import Foundation
import Testing
@testable import CCMaxOKCore

@Test func deploysStatuslineScript() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let fam = FileAccessManager(homeDirectory: tempDir)
    try fam.ensureCCMaxOKDirectory()

    try StatuslineSetup.deployScript(fileAccess: fam)

    let scriptPath = fam.statuslineScriptPath
    #expect(FileManager.default.fileExists(atPath: scriptPath.path()))

    let content = try String(contentsOf: scriptPath, encoding: .utf8)
    #expect(content.contains("live-status.json"))

    // Verify executable permission
    let attrs = try FileManager.default.attributesOfItem(atPath: scriptPath.path())
    let perms = (attrs[.posixPermissions] as? Int) ?? 0
    #expect(perms & 0o111 != 0) // has execute bit
}

@Test func scriptNeedsUpdateDetectsTilde() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let fam = FileAccessManager(homeDirectory: tempDir)
    try fam.ensureCCMaxOKDirectory()

    // Write a script with tilde path (old format)
    let oldScript = """
    #!/bin/bash
    cat /dev/stdin > ~/.claude/ccmaxok/live-status.json
    """
    try oldScript.write(to: fam.statuslineScriptPath, atomically: true, encoding: .utf8)

    #expect(StatuslineSetup.scriptNeedsUpdate(fileAccess: fam) == true)
}

@Test func scriptNeedsUpdateReturnsFalseWhenCurrent() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let fam = FileAccessManager(homeDirectory: tempDir)
    try fam.ensureCCMaxOKDirectory()

    // Deploy the correct script
    try StatuslineSetup.deployScript(fileAccess: fam)

    #expect(StatuslineSetup.scriptNeedsUpdate(fileAccess: fam) == false)
}

@Test func deployScriptUsesAbsolutePath() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let fam = FileAccessManager(homeDirectory: tempDir)
    try fam.ensureCCMaxOKDirectory()

    try StatuslineSetup.deployScript(fileAccess: fam)

    let content = try String(contentsOf: fam.statuslineScriptPath, encoding: .utf8)
    // Must contain absolute path, not tilde
    #expect(content.contains(fam.liveStatusPath.path()))
    #expect(!content.contains("~/"))
}

@Test func patchesSettingsJson() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    let claudeDir = tempDir.appendingPathComponent(".claude")
    try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let fam = FileAccessManager(homeDirectory: tempDir)

    // Create existing settings.json
    let existingSettings = """
    {
      "enabledPlugins": {
        "superpowers@claude-plugins-official": true
      }
    }
    """
    try existingSettings.write(to: fam.settingsPath, atomically: true, encoding: .utf8)

    try StatuslineSetup.patchSettings(fileAccess: fam)

    let data = try Data(contentsOf: fam.settingsPath)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

    // Existing settings preserved
    #expect(json["enabledPlugins"] != nil)

    // Statusline added
    let statusLine = json["statusLine"] as? [String: Any]
    #expect(statusLine?["type"] as? String == "command")
    let command = statusLine?["command"] as? String
    #expect(command?.contains("statusline.sh") == true)
}

@Test func wrapsExistingStatusLine() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    let claudeDir = tempDir.appendingPathComponent(".claude")
    try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let fam = FileAccessManager(homeDirectory: tempDir)
    try fam.ensureCCMaxOKDirectory()

    // Create existing settings.json with a non-ccmaxok statusLine (e.g., ccusage)
    let existingSettings = """
    {
      "statusLine": {
        "type": "command",
        "command": "/usr/local/bin/ccusage statusline"
      }
    }
    """
    try existingSettings.write(to: fam.settingsPath, atomically: true, encoding: .utf8)

    let result = try StatuslineSetup.setup(fileAccess: fam)

    // Outcome = wrappedExisting
    #expect(result.outcome == .wrappedExisting(command: "/usr/local/bin/ccusage statusline"))

    // wrapped-command.txt contains the original command
    let wrapped = try String(contentsOf: fam.wrappedCommandPath, encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    #expect(wrapped == "/usr/local/bin/ccusage statusline")

    // settings.json now points to haru script
    let data = try Data(contentsOf: fam.settingsPath)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    let cmd = (json["statusLine"] as? [String: Any])?["command"] as? String
    #expect(cmd == fam.statuslineScriptPath.path())
}

@Test func alreadyInstalledReturnsAlreadyInstalled() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    let claudeDir = tempDir.appendingPathComponent(".claude")
    try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let fam = FileAccessManager(homeDirectory: tempDir)

    // First install
    _ = try StatuslineSetup.setup(fileAccess: fam)

    // Second call should report alreadyInstalled
    let result = try StatuslineSetup.setup(fileAccess: fam)
    #expect(result.outcome == .alreadyInstalled)

    // No wrapped-command.txt written
    #expect(FileManager.default.fileExists(atPath: fam.wrappedCommandPath.path()) == false)
}

@Test func clearsStaleWrappedCommandWhenNoExisting() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    let claudeDir = tempDir.appendingPathComponent(".claude")
    try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let fam = FileAccessManager(homeDirectory: tempDir)
    try fam.ensureCCMaxOKDirectory()

    // Pre-existing stale wrapped-command.txt from a previous session
    try "/some/old/command".write(to: fam.wrappedCommandPath, atomically: true, encoding: .utf8)

    // No existing statusLine in settings
    let result = try StatuslineSetup.setup(fileAccess: fam)
    #expect(result.outcome == .installed)

    // Stale wrapped-command.txt should be cleaned up
    #expect(FileManager.default.fileExists(atPath: fam.wrappedCommandPath.path()) == false)
}

@Test func scriptContainsWrapperLogic() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let fam = FileAccessManager(homeDirectory: tempDir)
    let content = StatuslineSetup.expectedScriptContent(fileAccess: fam)

    #expect(content.contains("WRAPPED_FILE"))
    #expect(content.contains("eval"))
    #expect(content.contains(fam.wrappedCommandPath.path()))
    #expect(content.contains(fam.liveStatusPath.path()))
}

@Test func preservesOtherStatusLineKeys() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    let claudeDir = tempDir.appendingPathComponent(".claude")
    try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let fam = FileAccessManager(homeDirectory: tempDir)
    try fam.ensureCCMaxOKDirectory()

    // settings.json with extra statusLine keys (e.g., padding)
    let existingSettings = """
    {
      "statusLine": {
        "type": "command",
        "command": "/bin/echo old",
        "padding": 2
      }
    }
    """
    try existingSettings.write(to: fam.settingsPath, atomically: true, encoding: .utf8)

    _ = try StatuslineSetup.setup(fileAccess: fam)

    let data = try Data(contentsOf: fam.settingsPath)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    let statusLine = json["statusLine"] as? [String: Any]
    #expect(statusLine?["padding"] as? Int == 2)
    #expect((statusLine?["command"] as? String) == fam.statuslineScriptPath.path())
}

@Test func deployedScriptExecutesWrappedCommand() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    let claudeDir = tempDir.appendingPathComponent(".claude")
    try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let fam = FileAccessManager(homeDirectory: tempDir)
    try fam.ensureCCMaxOKDirectory()

    // Pre-existing non-haru statusline — setup should wrap it
    let existingSettings = """
    { "statusLine": { "type": "command", "command": "/bin/echo wrapped-hi" } }
    """
    try existingSettings.write(to: fam.settingsPath, atomically: true, encoding: .utf8)

    _ = try StatuslineSetup.setup(fileAccess: fam)

    // Actually run the deployed script, feeding JSON via stdin
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = [fam.statuslineScriptPath.path()]

    let stdinPipe = Pipe()
    let stdoutPipe = Pipe()
    process.standardInput = stdinPipe
    process.standardOutput = stdoutPipe

    try process.run()
    let input = "{\"hello\":\"world\"}"
    stdinPipe.fileHandleForWriting.write(input.data(using: .utf8)!)
    try stdinPipe.fileHandleForWriting.close()
    process.waitUntilExit()

    let output = String(
        data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(),
        encoding: .utf8
    ) ?? ""

    // live-status.json contains the piped input
    let live = try String(contentsOf: fam.liveStatusPath, encoding: .utf8)
    #expect(live == input)

    // Wrapped command's stdout was forwarded
    #expect(output.contains("wrapped-hi"))
}

@Test func patchesSettingsWhenNoFileExists() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    let claudeDir = tempDir.appendingPathComponent(".claude")
    try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let fam = FileAccessManager(homeDirectory: tempDir)

    try StatuslineSetup.patchSettings(fileAccess: fam)

    let data = try Data(contentsOf: fam.settingsPath)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    let statusLine = json["statusLine"] as? [String: Any]
    #expect(statusLine?["type"] as? String == "command")
}
