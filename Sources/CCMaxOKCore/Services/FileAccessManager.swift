import Foundation

public final class FileAccessManager: Sendable {
    private let homeDirectory: URL

    public init(homeDirectory: URL? = nil) {
        self.homeDirectory = homeDirectory ?? FileManager.default.homeDirectoryForCurrentUser
    }

    public var claudeDirectory: URL {
        homeDirectory.appendingPathComponent(".claude", isDirectory: true)
    }

    public var ccmaxokDirectory: URL {
        claudeDirectory.appendingPathComponent("ccmaxok", isDirectory: true)
    }

    public var liveStatusPath: URL {
        ccmaxokDirectory.appendingPathComponent("live-status.json")
    }

    public var statsCachePath: URL {
        claudeDirectory.appendingPathComponent("stats-cache.json")
    }

    public var settingsPath: URL {
        claudeDirectory.appendingPathComponent("settings.json")
    }

    public var statuslineScriptPath: URL {
        ccmaxokDirectory.appendingPathComponent("statusline.sh")
    }

    public var databasePath: URL {
        ccmaxokDirectory.appendingPathComponent("history.sqlite")
    }

    public var projectsDirectory: URL {
        claudeDirectory.appendingPathComponent("projects", isDirectory: true)
    }

    public func ensureCCMaxOKDirectory() throws {
        try FileManager.default.createDirectory(
            at: ccmaxokDirectory,
            withIntermediateDirectories: true
        )
    }

    /// Find all .jsonl session files under ~/.claude/projects/
    public func sessionFiles() throws -> [URL] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: projectsDirectory.path()) else { return [] }

        var jsonlFiles: [URL] = []
        if let enumerator = fm.enumerator(
            at: projectsDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let fileURL as URL in enumerator {
                if fileURL.pathExtension == "jsonl" {
                    jsonlFiles.append(fileURL)
                }
            }
        }
        return jsonlFiles
    }
}
