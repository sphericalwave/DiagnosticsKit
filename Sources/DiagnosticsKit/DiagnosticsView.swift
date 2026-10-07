//
//  DiagnosticsView.swift
//  DiagnosticsKit
//
//  Shared log screen, generalized from MindHeist's `ErrorLogView`. Filter by
//  level, snapshot the audio session on demand, export the timeline, clear.
//
//  Host coupling is gone: MindHeist's version needed a `MainTableVm` just to
//  reach the snapshot button, which is now a framework call.
//

import SwiftUI

public struct DiagnosticsView: View {

    @ObservedObject private var log: ErrorLog
    @State private var levelFilter: DiagnosticEntry.Level?
    /// Entry showing its "copied" confirmation, if any.
    @State private var copiedID: UUID?
    /// "Copied N entries" toast after Copy Log; `nil` when hidden.
    @State private var logCopiedToast: Toast?
    private let onSnapshot: (() -> Void)?

    /// - Parameter onSnapshot: replaces what the Snapshot button records. Hosts
    ///   with their own state worth dumping alongside the session (a player's
    ///   engine/node state, say) pass a closure that logs both. Defaults to a
    ///   plain audio-session snapshot.
    public init(log: ErrorLog = .shared, onSnapshot: (() -> Void)? = nil) {
        self.log = log
        self.onSnapshot = onSnapshot
    }

    private var visible: [DiagnosticEntry] {
        guard let levelFilter else { return log.entries }
        return log.entries.filter { $0.level == levelFilter }
    }

    public var body: some View {
        List {
            filterSection

            if visible.isEmpty {
                Section {
                    Text(log.entries.isEmpty ? "No entries logged."
                                             : "No entries match this filter.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("\(visible.count) entries") {
                    ForEach(visible) { entry in
                        row(entry)
                    }
                    .onDelete { idx in
                        idx.map { visible[$0] }.forEach(log.remove)
                    }
                }
            }
        }
        .navigationTitle("Diagnostics")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar { toolbarContent }
        .overlay(alignment: .bottom) {
            if let logCopiedToast {
                Label(logCopiedToast.text, systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: logCopiedToast)
        .sensoryFeedback(.success, trigger: logCopiedToast) { _, new in new != nil }
        .onAppear { log.markRead() }
    }

    private func copyLog() {
        let entries = visible
        Pasteboard.copy(ErrorLog.copyText(for: entries))
        let count = min(entries.count, ErrorLog.copyLimit)
        // A fresh id per copy, so a repeat copy re-fires the haptic and
        // isn't hidden early by the previous copy's timer.
        let toast = Toast(text: "Copied \(count) \(count == 1 ? "entry" : "entries")")
        logCopiedToast = toast
        Task {
            try? await Task.sleep(for: .seconds(2))
            if logCopiedToast == toast { logCopiedToast = nil }
        }
    }

    private struct Toast: Equatable {
        let id = UUID()
        let text: String
    }

    @ViewBuilder
    private var filterSection: some View {
        Section {
            Picker("Level", selection: $levelFilter) {
                Text("All").tag(DiagnosticEntry.Level?.none)
                ForEach(DiagnosticEntry.Level.allCases, id: \.self) { level in
                    Text(level.label).tag(DiagnosticEntry.Level?.some(level))
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private func row(_ entry: DiagnosticEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: entry.level.symbolName)
                    .foregroundStyle(color(for: entry.level))
                if !entry.source.isEmpty {
                    Text(entry.source)
                        .font(.caption.bold())
                        .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 8)

                Button {
                    Pasteboard.copy(entry.fullText)
                    copiedID = entry.id
                    // Revert the confirmation after a beat; a permanently
                    // ticked row reads as state rather than feedback.
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        if copiedID == entry.id { copiedID = nil }
                    }
                } label: {
                    Image(systemName: copiedID == entry.id
                          ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                        .foregroundStyle(copiedID == entry.id ? .green : .accentColor)
                }
                // Borderless keeps the tap on the icon — a plain Button in a
                // List row swallows taps across the whole row.
                .buttonStyle(.borderless)
                .accessibilityLabel(copiedID == entry.id ? "Copied" : "Copy entry")
            }

            Text(entry.message)
                .font(.body)
                .textSelection(.enabled)

            if let detail = entry.detail {
                Text(detail)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Text(entry.date.formatted(date: .abbreviated, time: .standard))
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("\(entry.file):\(entry.line)  \(entry.function)")
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    private func color(for level: DiagnosticEntry.Level) -> Color {
        switch level {
        case .info:    return .secondary
        case .warning: return .orange
        case .error:   return .red
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button("Snapshot Audio Session") {
                    if let onSnapshot {
                        onSnapshot()
                    } else {
                        log.recordAudioSnapshot("manual")
                    }
                }
                ShareLink(item: log.exportText()) {
                    Label("Export Timeline", systemImage: "square.and.arrow.up")
                }
                Button(action: copyLog) {
                    Label("Copy Log", systemImage: "doc.on.doc")
                }
                .disabled(visible.isEmpty)
                Divider()
                Button("Clear This App's Log", role: .destructive) {
                    log.clear()
                }
                .disabled(log.entries.isEmpty)
            } label: {
                Label("Actions", systemImage: "ellipsis.circle")
            }
        }
    }
}

#if DEBUG
#Preview("DiagnosticsView") {
    NavigationStack {
        DiagnosticsView(log: DiagnosticsKitSamples.sampleLog())
    }
}
#endif
