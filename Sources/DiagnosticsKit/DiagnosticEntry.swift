//
//  DiagnosticEntry.swift
//  DiagnosticsKit
//
//  One logged event. Codable so entries survive relaunch and can be merged
//  across apps from a shared App Group container — `app` is what lets a
//  merged timeline show which process wrote each line.
//

import Foundation

public struct DiagnosticEntry: Identifiable, Codable, Hashable, Sendable {

    public enum Level: String, Codable, Sendable, CaseIterable {
        case info, warning, error

        public var label: String { rawValue.capitalized }

        public var symbolName: String {
            switch self {
            case .info:    return "info.circle"
            case .warning: return "exclamationmark.triangle"
            case .error:   return "xmark.octagon.fill"
            }
        }
    }

    public let id: UUID
    public let date: Date
    /// Which app produced this entry. Set automatically from the bundle name;
    /// the only field that matters when reading a merged cross-app log.
    public let app: String
    public let level: Level
    /// Coarse subsystem tag ("AudioSession", "CoreData"). Empty when the
    /// caller relied on `#fileID` capture instead.
    public let source: String
    public let message: String
    /// Expanded `NSError` dump, when an `Error` was passed in.
    public let detail: String?
    public let file: String
    public let line: Int
    public let function: String

    public init(id: UUID = UUID(),
                date: Date = Date(),
                app: String,
                level: Level,
                source: String,
                message: String,
                detail: String? = nil,
                file: String,
                line: Int,
                function: String) {
        self.id = id
        self.date = date
        self.app = app
        self.level = level
        self.source = source
        self.message = message
        self.detail = detail
        self.file = file
        self.line = line
        self.function = function
    }

    /// Single-line rendering for the timeline and for export.
    public var timelineLine: String {
        let stamp = DiagnosticEntry.timeFormatter.string(from: date)
        let tag = source.isEmpty ? "" : "[\(source)] "
        return "\(stamp) [\(app)] \(tag)\(message)"
    }

    /// Everything known about this entry, for pasting into a bug report.
    /// Unlike `timelineLine` this keeps the full date, the call site, and the
    /// expanded `NSError` detail — the parts you actually need when the log is
    /// read somewhere other than the device that produced it.
    public var fullText: String {
        var lines = [
            "\(level.rawValue.uppercased()) — \(app)",
            DiagnosticEntry.fullDateFormatter.string(from: date),
        ]
        if !source.isEmpty { lines.append("Source: \(source)") }
        lines.append("")
        lines.append(message)
        if let detail, !detail.isEmpty {
            lines.append("")
            lines.append(detail)
        }
        lines.append("")
        lines.append("\(file):\(line)  \(function)")
        return lines.joined(separator: "\n")
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    private static let fullDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()
}
