import XCTest
@testable import WorklogCore

final class DayFileTests: XCTestCase {
    let sample = """
    # Tue 29 Sep 2026

    ## Log
    - 09:12 standup, planned M1 auth #pugmarks
    - 10:05-11:20 (1h15) fixed FD edge bundle #quilt
    - 11:30- reviewing PR 823 #quilt #review
    - not a log line
    - 9:00am meeting

    ## Notes
    - 13:00 this is in notes, not the log
    """

    func testParsesAllThreeLineShapes() {
        let e = DayFile.entries(in: sample)
        XCTAssertEqual(e.count, 3)

        XCTAssertEqual(e[0].start, 9 * 60 + 12)
        XCTAssertNil(e[0].end)
        XCTAssertFalse(e[0].isRunning)
        XCTAssertEqual(e[0].text, "standup, planned M1 auth #pugmarks")
        XCTAssertEqual(e[0].tags, ["pugmarks"])

        XCTAssertEqual(e[1].minutes, 75)
        XCTAssertEqual(e[1].text, "fixed FD edge bundle #quilt")

        XCTAssertTrue(e[2].isRunning)
        XCTAssertEqual(e[2].tags, ["quilt", "review"])
    }

    func testAppendGoesAfterLastLogLineAndKeepsNotes() {
        let out = DayFile.appending(DayFile.pointLine(at: 12 * 60, "lunch"), to: sample)
        let lines = out.components(separatedBy: "\n")
        XCTAssertEqual(lines[8], "- 12:00 lunch")
        XCTAssertEqual(lines[9], "")
        XCTAssertEqual(lines[10], "## Notes")
        XCTAssertTrue(out.hasSuffix("- 13:00 this is in notes, not the log"))
    }

    func testAppendIntoEmptyTemplate() {
        let t = DayFile.template(for: Date(timeIntervalSince1970: 0))
        let out = DayFile.appending("- 08:00 first", to: t)
        XCTAssertEqual(DayFile.entries(in: out).map(\.text), ["first"])
        XCTAssertTrue(out.contains("- 08:00 first\n\n## Notes"))
    }

    func testAppendCreatesLogSectionWhenMissing() {
        let out = DayFile.appending("- 08:00 first", to: "# Hand written\n\nsome notes\n")
        XCTAssertEqual(DayFile.entries(in: out).map(\.text), ["first"])
        XCTAssertTrue(out.hasPrefix("# Hand written\n\n## Log\n- 08:00 first"))
    }

    func testStopRunningRewritesLineInPlace() {
        let out = DayFile.stopping(start: 11 * 60 + 30, text: "reviewing PR 823 #quilt #review", in: sample, at: 12 * 60 + 12)!
        XCTAssertTrue(out.contains("- 11:30-12:12 (0h42) reviewing PR 823 #quilt #review"))
        XCTAssertFalse(DayFile.entries(in: out).contains(where: \.isRunning))
        XCTAssertNil(DayFile.stopping(start: 11 * 60 + 30, text: "reviewing PR 823 #quilt #review", in: out, at: 13 * 60))
    }

    func testTimerPastMidnightWraps() {
        XCTAssertEqual(DayFile.span(from: 23 * 60 + 30, to: 30), 60)
        XCTAssertEqual(DayFile.finishedLine(start: 23 * 60 + 30, end: 30, "late"), "- 23:30-00:30 (1h00) late")
    }

    func testTagsIgnoreHeadingsAndMidWord() {
        XCTAssertEqual(DayFile.tags(in: "issue#12 ##x #Quilt-ops"), ["quilt-ops"])
    }

    func testStoreRoundTripAndSearch() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = Store(root: root)
        let day = Date()

        XCTAssertNil(store.read(day))
        try store.update(day) { DayFile.appending("- 08:00 hello #x", to: $0) }
        XCTAssertEqual(DayFile.entries(in: store.read(day)!).map(\.text), ["hello #x"])
        XCTAssertEqual(store.days().count, 1)
        XCTAssertEqual(store.search("HELLO").map(\.line), ["- 08:00 hello #x"])
        XCTAssertTrue(store.url(for: day).path.contains("/\(Calendar.current.component(.year, from: day))/"))
    }
}

final class MultiTimerTests: XCTestCase {
    func testStopsOnlyTheMatchingTimerEvenAfterLinesShift() {
        var text = DayFile.template(for: Date())
        text = DayFile.appending(DayFile.runningLine(at: 600, "a #x"), to: text)
        text = DayFile.appending(DayFile.runningLine(at: 610, "b #y"), to: text)
        // Someone inserts a line above both timers in another editor.
        text = text.replacingOccurrences(of: "## Log\n", with: "## Log\n- 08:00 earlier\n")

        let out = DayFile.stopping(start: 600, text: "a #x", in: text, at: 660)!
        let e = DayFile.entries(in: out)
        XCTAssertEqual(e.first { $0.text == "a #x" }?.minutes, 60)
        XCTAssertTrue(e.first { $0.text == "b #y" }!.isRunning)
        XCTAssertNil(DayFile.stopping(start: 600, text: "a #x", in: out, at: 700))
    }
}
