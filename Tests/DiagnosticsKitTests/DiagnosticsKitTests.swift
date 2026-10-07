import XCTest
@testable import DiagnosticsKit

final class DiagnosticsKitTests: XCTestCase {

    // MARK: - Helpers

    /// Isolated UserDefaults suite so tests never touch the real log.
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "DiagnosticsKitTests_\(UUID().uuidString)")!
    }

    private func makeLog(cap: Int = 500) -> ErrorLog {
        ErrorLog(defaults: makeDefaults(), key: "test_log",
                 app: "TestApp", maxEntries: cap)
    }

    /// `record` publishes asynchronously when off the main thread; on the main
    /// thread it is synchronous, so tests can assert immediately.
    private func entriesOnMain(_ log: ErrorLog) -> [DiagnosticEntry] {
        XCTAssertTrue(Thread.isMainThread)
        return log.entries
    }

    // MARK: - Recording

    @MainActor
    func testTerseRecordDefaultsToErrorAndCapturesCallSite() {
        let log = makeLog()
        log.record("something broke")

        let entries = entriesOnMain(log)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].level, .error, "terse form defaults to .error")
        XCTAssertEqual(entries[0].message, "something broke")
        XCTAssertEqual(entries[0].source, "")
        XCTAssertTrue(entries[0].file.contains("DiagnosticsKitTests"),
                      "#fileID should identify the call site, got \(entries[0].file)")
        XCTAssertEqual(entries[0].app, "TestApp")
    }

    @MainActor
    func testLeveledRecordExpandsNSErrorDetail() throws {
        let log = makeLog()
        let err = NSError(domain: "TestDomain", code: 42,
                          userInfo: [NSLocalizedDescriptionKey: "boom"])
        log.record(.warning, source: "CoreData", message: "save failed", error: err)

        let entry = entriesOnMain(log)[0]
        XCTAssertEqual(entry.level, .warning)
        XCTAssertEqual(entry.source, "CoreData")
        let detail = try XCTUnwrap(entry.detail)
        XCTAssertTrue(detail.contains("TestDomain"))
        XCTAssertTrue(detail.contains("42"))
    }

    @MainActor
    func testConvenienceHelpersSetLevels() {
        let log = makeLog()
        log.info("Audio", "started")
        log.warning("Audio", "odd")
        log.error("Audio", "dead")

        // entries are newest-first
        XCTAssertEqual(entriesOnMain(log).map(\.level), [.error, .warning, .info])
    }

    @MainActor
    func testMostRecentErrorSkipsLowerLevels() {
        let log = makeLog()
        log.error("Audio", "real failure")
        log.info("Audio", "noise")
        XCTAssertEqual(log.mostRecentError?.message, "real failure")
    }

    // MARK: - Unread count

    @MainActor
    func testUnreadCountAccumulatesAndClears() {
        let log = makeLog()
        log.info("A", "1")
        log.info("A", "2")
        XCTAssertEqual(log.unreadCount, 2)
        log.markRead()
        XCTAssertEqual(log.unreadCount, 0)
    }

    // MARK: - Capping

    @MainActor
    func testEntriesAreCapped() {
        let log = makeLog(cap: 5)
        for i in 0..<20 { log.info("A", "entry \(i)") }
        XCTAssertEqual(entriesOnMain(log).count, 5)
        XCTAssertEqual(entriesOnMain(log).first?.message, "entry 19",
                       "newest entries are the ones kept")
    }

    // MARK: - Persistence

    @MainActor
    func testEntriesSurviveANewLogOverTheSameDefaults() {
        let defaults = makeDefaults()
        let first = ErrorLog(defaults: defaults, key: "test_log", app: "TestApp")
        first.record("persisted")

        let second = ErrorLog(defaults: defaults, key: "test_log", app: "TestApp")
        XCTAssertEqual(second.entries.count, 1)
        XCTAssertEqual(second.entries[0].message, "persisted")
    }

    @MainActor
    func testClearAlsoClearsPersistedEntries() {
        let defaults = makeDefaults()
        let log = ErrorLog(defaults: defaults, key: "test_log", app: "TestApp")
        log.record("gone soon")
        log.clear()
        XCTAssertTrue(log.entries.isEmpty)

        let reloaded = ErrorLog(defaults: defaults, key: "test_log", app: "TestApp")
        XCTAssertTrue(reloaded.entries.isEmpty, "clear must not leave entries behind on disk")
    }

    @MainActor
    func testInMemoryLogDoesNotPersist() {
        let log = ErrorLog(defaults: nil, app: "TestApp")
        log.record("ephemeral")
        XCTAssertEqual(log.entries.count, 1)

        // A nil-defaults log has nowhere to read from on the next launch.
        let next = ErrorLog(defaults: nil, app: "TestApp")
        XCTAssertTrue(next.entries.isEmpty)
    }

    @MainActor
    func testRemoveDropsOnlyTheTargetedEntry() throws {
        let log = makeLog()
        log.info("A", "keep me")
        log.info("A", "delete me")
        let target = try XCTUnwrap(entriesOnMain(log).first { $0.message == "delete me" })
        log.remove(target)
        XCTAssertEqual(entriesOnMain(log).map(\.message), ["keep me"])
    }

    // MARK: - Off-main-thread logging

    func testRecordFromBackgroundThreadIsDelivered() {
        // XCTest runs this on the main thread, so the log is built there and
        // only the `record` call is moved off-main — the case MindHeist's
        // AudioPlayer completion callbacks hit.
        let log = makeLog()
        let exp = expectation(description: "published")

        DispatchQueue.global().async {
            log.record("from a background queue")
            // Enqueued after the publish hop, so by the time this runs the
            // entry has already landed.
            DispatchQueue.main.async { exp.fulfill() }
        }
        wait(for: [exp], timeout: 2)

        XCTAssertEqual(log.entries.count, 1)
        XCTAssertEqual(log.entries[0].message, "from a background queue")
    }

    // MARK: - Export

    @MainActor
    func testExportTextIsOldestFirstAndTagsTheApp() {
        let log = makeLog()
        log.info("A", "first")
        log.info("A", "second")

        let lines = log.exportText().split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[0].contains("first"), "export reads oldest → newest")
        XCTAssertTrue(lines[1].contains("second"))
        XCTAssertTrue(lines[0].contains("[TestApp]"))
    }

    // MARK: - Per-entry copy

    @MainActor
    func testFullTextCarriesEverythingNeededOffDevice() throws {
        let log = makeLog()
        let err = NSError(domain: "AudioDomain", code: 7,
                          userInfo: [NSLocalizedDescriptionKey: "session grabbed"])
        log.record(.warning, source: "AudioSession", message: "deactivate failed", error: err)

        let text = entriesOnMain(log)[0].fullText
        XCTAssertTrue(text.contains("WARNING"))
        XCTAssertTrue(text.contains("TestApp"))
        XCTAssertTrue(text.contains("AudioSession"), "source tag")
        XCTAssertTrue(text.contains("deactivate failed"), "message")
        XCTAssertTrue(text.contains("AudioDomain"), "expanded NSError detail")
        XCTAssertTrue(text.contains("DiagnosticsKitTests"), "call site")
        // Full date, not just wall-clock time — the log gets read elsewhere.
        XCTAssertTrue(text.contains("-"), "should carry a yyyy-MM-dd date")
    }

    @MainActor
    func testFullTextOmitsEmptyOptionalSections() {
        let log = makeLog()
        log.record("bare message")

        let text = entriesOnMain(log)[0].fullText
        XCTAssertTrue(text.contains("bare message"))
        XCTAssertFalse(text.contains("Source:"),
                       "an empty source must not render a dangling label")
    }

    // MARK: - Copy Log

    private func entry(_ message: String, level: DiagnosticEntry.Level = .info,
                       source: String = "", detail: String? = nil,
                       at seconds: TimeInterval) -> DiagnosticEntry {
        DiagnosticEntry(date: Date(timeIntervalSince1970: seconds), app: "TestApp",
                        level: level, source: source, message: message, detail: detail,
                        file: "Mod/File.swift", line: 12, function: "f()")
    }

    func testCopyTextIsNewestFirstWithFullDetail() {
        let old = entry("older", at: 1_000)
        let new = entry("newer", level: .error, source: "CoreData",
                        detail: "Domain: X  Code: 1", at: 2_000)

        let text = ErrorLog.copyText(for: [old, new])
        XCTAssertEqual(text, new.fullText + "\n\n---\n\n" + old.fullText,
                       "newest first, each in fullText form")
        XCTAssertTrue(text.contains("ERROR"))
        XCTAssertTrue(text.contains("Source: CoreData"))
        XCTAssertTrue(text.contains("Domain: X  Code: 1"))
        XCTAssertTrue(text.contains("Mod/File.swift:12"))
        XCTAssertFalse(text.contains("Showing newest"), "no cap note under the limit")
    }

    func testCopyTextCapsAndNotesTheCap() {
        let entries = (0..<10).map { entry("entry \($0)", at: TimeInterval($0)) }

        let text = ErrorLog.copyText(for: entries, limit: 3)
        XCTAssertTrue(text.contains("entry 9"))
        XCTAssertTrue(text.contains("entry 7"))
        XCTAssertFalse(text.contains("entry 6"), "older entries beyond the cap are dropped")
        XCTAssertTrue(text.hasSuffix("[Showing newest 3 of 10 entries]"))
    }

    func testCopyTextOfNothingIsEmpty() {
        XCTAssertEqual(ErrorLog.copyText(for: []), "")
    }

    // MARK: - Snapshot

    func testSnapshotSummaryMentionsCategoryAndOptions() {
        let summary = AudioSessionSnapshot.capture().summary
        XCTAssertTrue(summary.contains("cat="))
        XCTAssertTrue(summary.contains("opts="))
        XCTAssertTrue(summary.contains("otherAudioPlaying="))
    }

    #if os(iOS)
    func testOptionNamesDecodeTheBitmask() {
        let names = AudioSessionSnapshot.optionNames([.mixWithOthers, .duckOthers])
        XCTAssertEqual(Set(names), ["mixWithOthers", "duckOthers"])
        XCTAssertTrue(AudioSessionSnapshot.optionNames([]).isEmpty,
                      "no options must render as empty, not as a stray name")
    }
    #endif
}
