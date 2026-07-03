//
//  DeletionLogger.swift
//  Account Manager
//
//  Writes one .log file per run to ~/Library/Logs/AccountManager/.
//  Keeps the 100 most recent files, deleting older ones automatically.
//

import Foundation

struct DeletionLogger {

    // MARK: - Constants

    static let maxRuns = 100

    static var logDirectory: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("AccountManager", isDirectory: true)
    }

    // MARK: - Write

    /// Write a run log for `results`. Returns the URL of the written file, or nil on failure.
    @discardableResult
    static func write(
        results: [DeletionResult],
        isDryRun: Bool,
        host: String           // "local" or the SSH host name
    ) -> URL? {
        let fm  = FileManager.default
        let dir = logDirectory

        // Ensure directory exists
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

        let now       = Date()
        let fileName  = fileTimestamp(now) + ".log"
        let fileURL   = dir.appendingPathComponent(fileName)
        let content   = buildLog(results: results, isDryRun: isDryRun, host: host, date: now)

        guard let data = content.data(using: .utf8) else { return nil }
        try? data.write(to: fileURL, options: .atomic)

        rotate(in: dir, keeping: maxRuns)
        return fileURL
    }

    // MARK: - Log content

    private static func buildLog(
        results: [DeletionResult],
        isDryRun: Bool,
        host: String,
        date: Date
    ) -> String {
        let dateFmt     = DateFormatter(); dateFmt.dateFormat = "yyyy-MM-dd"
        let timeFmt     = DateFormatter(); timeFmt.dateFormat = "HH:mm:ss"
        let dateStr     = dateFmt.string(from: date)
        let timeStr     = timeFmt.string(from: date)
        let modeLabel   = isDryRun ? "Preview (no changes made)" : "Live Run"
        let successes   = results.filter(\.success).count

        let bar     = String(repeating: "═", count: 64)
        let divider = String(repeating: "─", count: 64)

        var lines: [String] = []

        // Header
        lines += [
            bar,
            "Account Manager  |  \(dateStr) \(timeStr)  |  \(host)",
            bar,
            "Mode    : \(modeLabel)",
            "Actions : \(results.count)",
            "",
        ]

        // Entries
        for result in results {
            let ts      = timeFmt.string(from: date)   // same second is fine; order implies sequence
            let action  = result.mode.label.uppercased()
            let name    = result.displayName.map { "\(result.username)  (\($0))" } ?? result.username

            if isDryRun {
                lines.append("[PREVIEW]    \(ts)  \(pad(action, 22))  \(name)")
            } else if result.success {
                lines.append("[COMPLETED]  \(ts)  \(pad(action, 22))  \(name)")
            } else if let err = result.error {
                lines.append("[ERROR]      \(ts)  \(pad(action, 22))  \(name)")
                lines.append("             \(String(repeating: " ", count: 9))Error: \(err)")
            } else {
                lines.append("[WARNING]    \(ts)  \(pad(action, 22))  \(name)")
            }
        }

        // Footer
        let summaryIcon = (successes == results.count) ? "✓" : "✗"
        lines += [
            "",
            divider,
            "Result  : \(summaryIcon) \(successes) / \(results.count) \(isDryRun ? "previewed" : "completed") successfully",
            bar,
            "",
        ]

        return lines.joined(separator: "\n")
    }

    // MARK: - Rotation

    private static func rotate(in directory: URL, keeping max: Int) {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        ) else { return }

        let logs = items
            .filter { $0.pathExtension == "log" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }  // lex sort on timestamp name = chronological

        guard logs.count > max else { return }
        let toDelete = logs.prefix(logs.count - max)
        for url in toDelete {
            try? fm.removeItem(at: url)
        }
    }

    // MARK: - Helpers

    private static func fileTimestamp(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd_HHmmss"
        return fmt.string(from: date)
    }

    private static func pad(_ string: String, _ width: Int) -> String {
        string.count >= width ? string : string + String(repeating: " ", count: width - string.count)
    }
}
