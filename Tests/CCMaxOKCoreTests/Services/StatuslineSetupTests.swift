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

@Test func doesNotOverwriteExistingNonCCMaxOKStatusLine() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    let claudeDir = tempDir.appendingPathComponent(".claude")
    try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let fam = FileAccessManager(homeDirectory: tempDir)

    // Create existing settings.json with a non-ccmaxok statusLine
    let existingSettings = """
    {
      "statusLine": {
        "type": "command",
        "command": "/usr/local/bin/my-custom-statusline.sh"
      }
    }
    """
    try existingSettings.write(to: fam.settingsPath, atomically: true, encoding: .utf8)

    try StatuslineSetup.patchSettings(fileAccess: fam)

    let data = try Data(contentsOf: fam.settingsPath)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

    // Existing non-ccmaxok statusLine must NOT be overwritten
    let statusLine = json["statusLine"] as? [String: Any]
    let command = statusLine?["command"] as? String
    #expect(command == "/usr/local/bin/my-custom-statusline.sh")
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
