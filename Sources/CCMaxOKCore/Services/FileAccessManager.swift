import Foundation

public final class FileAccessManager: Sendable {
    private let homeDirectory: URL

    public init(homeDirectory: URL? = nil) {
        self.homeDirectory = homeDirectory ?? FileManager.default.homeDirectoryForCurrentUser
    }

    // MARK: - Claude Config Directory Resolution

    /// Primary claude config directory (resolved by priority)
    public var claudeDirectory: URL {
        Self.resolveClaudeConfigDir(home: homeDirectory)
    }

    /// All existing claude config directories (for scanning session files, etc.)
    public var allClaudeDirectories: [URL] {
        let fm = FileManager.default
        var dirs: [URL] = []

        // Check CLAUDE_CONFIG_DIR env var
        if let envPath = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"] {
            for path in envPath.split(separator: ",") {
                let url = URL(fileURLWithPath: String(path).trimmingCharacters(in: .whitespaces), isDirectory: true)
                if fm.fileExists(atPath: url.path) {
                    dirs.append(url)
                }
            }
        }

        // New path: ~/.config/claude/
        let configClaude = homeDirectory
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("claude", isDirectory: true)
        if fm.fileExists(atPath: configClaude.path) && !dirs.contains(configClaude) {
            dirs.append(configClaude)
        }

        // Legacy path: ~/.claude/
        let dotClaude = homeDirectory.appendingPathComponent(".claude", isDirectory: true)
        if fm.fileExists(atPath: dotClaude.path) && !dirs.contains(dotClaude) {
            dirs.append(dotClaude)
        }

        return dirs
    }

    /// All existing settings.json paths across all config directories
    public var allSettingsPaths: [URL] {
        let fm = FileManager.default
        return allClaudeDirectories.compactMap { dir in
            let path = dir.appendingPathComponent("settings.json")
            return fm.fileExists(atPath: path.path) ? path : nil
        }
    }

    /// Resolve the primary claude config directory
    private static func resolveClaudeConfigDir(home: URL) -> URL {
        let fm = FileManager.default

        // 1. CLAUDE_CONFIG_DIR env var (first path)
        if let envPath = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"] {
            let first = envPath.split(separator: ",").first.map { String($0).trimmingCharacters(in: .whitespaces) }
            if let path = first {
                let url = URL(fileURLWithPath: path, isDirectory: true)
                if fm.fileExists(atPath: url.path) {
                    return url
                }
            }
        }

        // 2. ~/.config/claude/ (new convention)
        let configClaude = home
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("claude", isDirectory: true)
        if fm.fileExists(atPath: configClaude.path) {
            return configClaude
        }

        // 3. ~/.claude/ (legacy, always fallback)
        return home.appendingPathComponent(".claude", isDirectory: true)
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

    /// Recent project working directories reconstructed from `~/.claude/projects/` subdirectory names.
    /// Claude Code encodes each project's cwd by replacing `/` with `-` (e.g. `/Users/a/haru` → `-Users-a-haru`).
    /// Returns URLs in descending modification-date order (most recently active first), deduplicated, existing dirs only.
    public func recentProjectPaths(limit: Int) -> [URL] {
        let fm = FileManager.default
        var entries: [(url: URL, mod: Date)] = []

        for dir in allClaudeDirectories {
            let projectsDir = dir.appendingPathComponent("projects", isDirectory: true)
            guard fm.fileExists(atPath: projectsDir.path),
                  let children = try? fm.contentsOfDirectory(
                      at: projectsDir,
                      includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                      options: [.skipsHiddenFiles]
                  )
            else { continue }

            for child in children {
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: child.path, isDirectory: &isDir), isDir.boolValue else { continue }

                guard let projectURL = Self.resolveEncodedProjectPath(child.lastPathComponent) else {
                    DiagnosticsLogger.shared.info(
                        "projects",
                        "encoded=\(child.lastPathComponent) could not be resolved to an existing path"
                    )
                    continue
                }

                let attrs = try? fm.attributesOfItem(atPath: child.path)
                let mod = (attrs?[.modificationDate] as? Date) ?? .distantPast
                entries.append((projectURL, mod))
            }
        }

        var seen = Set<String>()
        return entries
            .sorted { $0.mod > $1.mod }
            .compactMap { entry in
                let key = entry.url.path
                guard !seen.contains(key) else { return nil }
                seen.insert(key)
                return entry.url
            }
            .prefix(limit)
            .map { $0 }
    }

    /// Claude Code는 프로젝트 cwd의 모든 `/`를 `-`로 치환해 디렉토리명으로 쓴다(`/Users/a/haru` → `-Users-a-haru`).
    /// 실제 경로에 `-`가 포함된 경우(예: `/Users/me/my-proj/haru`) 나이브 역변환이 깨지므로,
    /// 1차 나이브 시도가 실패하면 토큰을 greedy하게 합쳐 실제 존재하는 최장 경로를 찾는다.
    /// 토큰 수 상한(20)을 두어 악성 입력을 방어한다.
    static func resolveEncodedProjectPath(_ encoded: String) -> URL? {
        let fm = FileManager.default
        let trimmed = encoded.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let tokens = trimmed.components(separatedBy: "-").filter { !$0.isEmpty }
        // 실제 사용자 cwd 깊이는 보통 5~10 토큰. 상한 30은 UUID가 섞인 tmp 경로까지 커버.
        guard !tokens.isEmpty, tokens.count <= 30 else { return nil }

        // 1차: 모든 `-`를 `/`로 치환 (기존 동작)
        let naive = URL(fileURLWithPath: "/" + tokens.joined(separator: "/"), isDirectory: true)
        if fm.fileExists(atPath: naive.path) {
            return naive
        }

        // 2차: greedy longest-existing-segment
        var current = URL(fileURLWithPath: "/", isDirectory: true)
        var i = 0
        while i < tokens.count {
            var chosen: (endIndex: Int, segment: String)?
            var j = tokens.count
            while j > i {
                let segment = tokens[i..<j].joined(separator: "-")
                let candidate = current.appendingPathComponent(segment, isDirectory: true)
                if fm.fileExists(atPath: candidate.path) {
                    chosen = (j, segment)
                    break
                }
                j -= 1
            }
            guard let pick = chosen else { return nil }
            current = current.appendingPathComponent(pick.segment, isDirectory: true)
            i = pick.endIndex
        }
        return current
    }

    /// Find all .jsonl session files under all claude config directories' projects/
    public func sessionFiles() throws -> [URL] {
        let fm = FileManager.default
        var jsonlFiles: [URL] = []
        var seen = Set<String>() // deduplicate by filename

        for dir in allClaudeDirectories {
            let projectsDir = dir.appendingPathComponent("projects", isDirectory: true)
            guard fm.fileExists(atPath: projectsDir.path) else { continue }

            if let enumerator = fm.enumerator(
                at: projectsDir,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) {
                for case let fileURL as URL in enumerator {
                    if fileURL.pathExtension == "jsonl" {
                        let name = fileURL.lastPathComponent
                        if !seen.contains(name) {
                            seen.insert(name)
                            jsonlFiles.append(fileURL)
                        }
                    }
                }
            }
        }
        return jsonlFiles
    }
}
