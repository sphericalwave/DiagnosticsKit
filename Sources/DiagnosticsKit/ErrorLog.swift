//
//  ErrorLog.swift
//  DiagnosticsKit
//
//  In-app log for non-fatal failures and notable events, so trouble in
//  production leaves clues instead of vanishing.
//
//  Merged from the two designs that grew up in parallel across the apps:
//  MindHeist's (singleton, `#fileID`/`#line` capture, persisted, callable off
//  the main thread) and progYog/kettlebell's (levels, `source` tag, `NSError`
//  detail expansion, unread count). Both call styles still compile, so apps
//  adopt without rewriting their call sites.
//
//  Each app keeps its own log — there is no cross-app storage. Comparing two
//  apps means exporting from each; `DiagnosticEntry.app` tags every line so
//  those exports stay distinguishable when read side by side.
//

import Foundation
import Combine

public final class ErrorLog: ObservableObject, @unchecked Sendable {

    /// Shared instance, for apps that log from anywhere (MindHeist style).
    /// Apps that prefer injection can construct their own — both work.
    public static let shared = ErrorLog()

    public typealias Entry = DiagnosticEntry
    public typealias Level = DiagnosticEntry.Level

    @Published public private(set) var entries: [DiagnosticEntry] = []
    @Published public var unreadCount: Int = 0

    private let app: String
    private let maxEntries: Int
    /// Persistence target. `nil` keeps the log in memory only — which is what
    /// progYog and kettlebell do today.
    private let defaults: UserDefaults?
    private let key: String
    /// Guards persistence — `record` is callable from any thread (audio render
    /// callbacks, background queues), while `@Published` mutation stays on main.
    private let lock = NSLock()

    /// - Parameters:
    ///   - defaults: where entries persist. Pass `nil` for an in-memory log.
    ///   - app: tag written onto every entry, so an exported timeline says
    ///     which app produced it.
    public init(defaults: UserDefaults? = .standard,
                key: String = "DiagnosticsKit_ErrorLog_v1",
                app: String = Bundle.main.appDisplayName,
                maxEntries: Int = 500) {
        self.defaults = defaults
        self.key = key
        self.app = app
        self.maxEntries = maxEntries
        // `init` runs before anyone can observe, so a direct set is safe here.
        self.entries = Self.load(from: defaults, key: key)
    }

    // MARK: - Recording

    /// Full form. Matches the progYog/kettlebell signature exactly.
    public func record(_ level: Level,
                       source: String,
                       message: String,
                       error: Error? = nil,
                       file: String = #fileID,
                       line: Int = #line,
                       function: String = #function) {
        commit(DiagnosticEntry(
            app: app,
            level: level,
            source: source,
            message: message,
            detail: error.map(Self.describe),
            file: file,
            line: line,
            function: function
        ))
    }

    /// Terse form. Matches the MindHeist signature exactly — level defaults to
    /// `.error`, and the call site is identified by `#fileID`/`#line` instead
    /// of an explicit `source`.
    public func record(_ message: String,
                       file: String = #fileID,
                       line: Int = #line,
                       function: String = #function) {
        record(.error, source: "", message: message,
               file: file, line: line, function: function)
    }

    public func info(_ source: String, _ message: String,
                     file: String = #fileID, line: Int = #line, function: String = #function) {
        record(.info, source: source, message: message,
               file: file, line: line, function: function)
    }

    public func warning(_ source: String, _ message: String, error: Error? = nil,
                        file: String = #fileID, line: Int = #line, function: String = #function) {
        record(.warning, source: source, message: message, error: error,
               file: file, line: line, function: function)
    }

    public func error(_ source: String, _ message: String, error: Error? = nil,
                      file: String = #fileID, line: Int = #line, function: String = #function) {
        record(.error, source: source, message: message, error: error,
               file: file, line: line, function: function)
    }

    private func commit(_ entry: DiagnosticEntry) {
        print("[\(entry.level.rawValue)][\(entry.app)] \(entry.file):\(entry.line) \(entry.function) — \(entry.message)")
        if let detail = entry.detail { print("  \(detail)") }

        publish {
            $0.entries.insert(entry, at: 0)
            if $0.entries.count > $0.maxEntries {
                $0.entries = Array($0.entries.prefix($0.maxEntries))
            }
            $0.unreadCount += 1
            $0.persist()
        }
    }

    // MARK: - Reading / clearing

    public var mostRecentError: DiagnosticEntry? {
        entries.first { $0.level == .error }
    }

    public func markRead() {
        publish { $0.unreadCount = 0 }
    }

    public func clear() {
        publish {
            $0.entries = []
            $0.unreadCount = 0
            $0.persist()
        }
    }

    public func remove(_ entry: DiagnosticEntry) {
        publish {
            $0.entries.removeAll { $0.id == entry.id }
            $0.persist()
        }
    }

    /// Plain-text dump of the current timeline, oldest first, for a share sheet
    /// or a paste into a bug report.
    public func exportText() -> String {
        entries.reversed().map(\.timelineLine).joined(separator: "\n")
    }

    // MARK: - Persistence

    private func persist() {
        guard let defaults else { return }
        lock.lock()
        defer { lock.unlock() }
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: key)
    }

    private static func load(from defaults: UserDefaults?, key: String) -> [DiagnosticEntry] {
        guard let defaults,
              let data = defaults.data(forKey: key),
              let arr = try? JSONDecoder().decode([DiagnosticEntry].self, from: data)
        else { return [] }
        return arr
    }

    // MARK: - Helpers

    /// All state mutation funnels through here so `record` stays callable from
    /// any thread while `@Published` only ever changes on main.
    private func publish(_ mutate: @escaping (ErrorLog) -> Void) {
        if Thread.isMainThread {
            mutate(self)
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                mutate(self)
            }
        }
    }

    private static func describe(_ error: Error) -> String {
        let nserror = error as NSError
        var lines: [String] = []
        lines.append("Domain: \(nserror.domain)  Code: \(nserror.code)")
        lines.append("Description: \(nserror.localizedDescription)")
        if let reason = nserror.localizedFailureReason {
            lines.append("Reason: \(reason)")
        }
        if let suggestion = nserror.localizedRecoverySuggestion {
            lines.append("Suggestion: \(suggestion)")
        }
        if !nserror.userInfo.isEmpty {
            lines.append("UserInfo:")
            for (k, v) in nserror.userInfo {
                lines.append("  \(k) = \(v)")
            }
        }
        return lines.joined(separator: "\n")
    }
}

extension Bundle {
    /// Short app name used to tag entries, so an exported log says where it
    /// came from.
    public var appDisplayName: String {
        object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? bundleIdentifier
            ?? "app"
    }
}
