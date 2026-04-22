import Foundation
import os

/// File-based diagnostic logger. Writes structured lines to `~/Library/Logs/haru/haru.log`
/// with size-based rotation (single .1 backup) so users can share a log bundle with the
/// developer when usage data fails to render.
///
/// Also mirrors each entry to `CCMaxOKCore.logger` (os.Logger) so it remains visible in
/// Console.app.
public final class DiagnosticsLogger: @unchecked Sendable {
    public enum Level: String, Sendable {
        case debug = "DEBUG"
        case info  = "INFO"
        case warn  = "WARN"
        case error = "ERROR"
    }

    public static let shared = DiagnosticsLogger()

    private let queue = DispatchQueue(label: "com.ccmaxok.diagnostics-logger", qos: .utility)
    private let fileURL: URL
    private let rotatedURL: URL
    private let maxBytes: Int = 5 * 1024 * 1024

    private let isoFormatter: ISO8601DateFormatter = {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fmt
    }()

    private var errorCounter: Int = 0

    public init(directory: URL? = nil) {
        let dir = directory ?? Self.defaultDirectory()
        self.fileURL = dir.appendingPathComponent("haru.log")
        self.rotatedURL = dir.appendingPathComponent("haru.log.1")

        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
    }

    private static func defaultDirectory() -> URL {
        let logs = FileManager.default
            .urls(for: .libraryDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("haru", isDirectory: true)
        return logs
    }

    public var logFileURL: URL { fileURL }
    public var rotatedFileURL: URL { rotatedURL }

    public var errorCount: Int {
        queue.sync { errorCounter }
    }

    public func log(
        _ level: Level,
        category: String,
        _ message: String,
        error: Error? = nil,
        file: String = #fileID,
        line: Int = #line
    ) {
        let timestamp = isoFormatter.string(from: Date())
        var suffix = ""
        if let error {
            suffix = " | error=\(String(describing: type(of: error))): \(error.localizedDescription)"
        }
        let origin = "\(file):\(line)"
        let line = "\(timestamp)\t\(level.rawValue)\t\(category)\t\(origin)\t\(message)\(suffix)\n"

        queue.async { [weak self] in
            guard let self else { return }
            if level == .error || level == .warn {
                self.errorCounter += 1
            }
            self.appendAndRotate(line)
        }

        switch level {
        case .debug: CCMaxOKCore.logger.debug("[\(category, privacy: .public)] \(message, privacy: .public)")
        case .info:  CCMaxOKCore.logger.info("[\(category, privacy: .public)] \(message, privacy: .public)")
        case .warn:  CCMaxOKCore.logger.warning("[\(category, privacy: .public)] \(message, privacy: .public)")
        case .error: CCMaxOKCore.logger.error("[\(category, privacy: .public)] \(message, privacy: .public)")
        }
    }

    public func debug(_ category: String, _ message: String, file: String = #fileID, line: Int = #line) {
        log(.debug, category: category, message, file: file, line: line)
    }
    public func info(_ category: String, _ message: String, file: String = #fileID, line: Int = #line) {
        log(.info, category: category, message, file: file, line: line)
    }
    public func warn(_ category: String, _ message: String, error: Error? = nil, file: String = #fileID, line: Int = #line) {
        log(.warn, category: category, message, error: error, file: file, line: line)
    }
    public func error(_ category: String, _ message: String, error: Error? = nil, file: String = #fileID, line: Int = #line) {
        log(.error, category: category, message, error: error, file: file, line: line)
    }

    /// Read the most recent N lines from the active log for UI display.
    public func recentEntries(limit: Int = 200) -> [String] {
        queue.sync {
            guard let data = try? Data(contentsOf: fileURL),
                  let text = String(data: data, encoding: .utf8) else { return [] }
            let lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            return Array(lines.suffix(limit))
        }
    }

    public func clear() {
        queue.sync {
            try? "".write(to: fileURL, atomically: true, encoding: .utf8)
            try? FileManager.default.removeItem(at: rotatedURL)
            errorCounter = 0
        }
    }

    // MARK: - Private

    private func appendAndRotate(_ line: String) {
        guard let data = line.data(using: .utf8) else { return }

        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: fileURL)
        }

        // Size check after write
        if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
           let size = attrs[.size] as? NSNumber,
           size.intValue > maxBytes {
            try? FileManager.default.removeItem(at: rotatedURL)
            try? FileManager.default.moveItem(at: fileURL, to: rotatedURL)
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
    }
}
