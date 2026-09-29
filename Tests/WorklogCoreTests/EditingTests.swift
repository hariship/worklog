import XCTest
@testable import WorklogCore

final class EditingTests: XCTestCase {
    let text = "# d\n\n## Log\n- 09:00 standup #quilt\n- 10:00- deploy #ops\n\n## Notes\n"

    func testReplaceAndDelete() {
        let edited = DayFile.replacing(start: 540, text: "standup #quilt", in: text, with: "- 09:05 standup, short #quilt")!
        XCTAssertEqual(DayFile.entries(in: edited).map(\.text), ["standup, short #quilt", "deploy #ops"])
        let deleted = DayFile.replacing(start: 600, text: "deploy #ops", in: text, with: nil)!
        XCTAssertEqual(DayFile.entries(in: deleted).map(\.text), ["standup #quilt"])
        XCTAssertTrue(deleted.hasSuffix("## Notes\n"))
        XCTAssertNil(DayFile.replacing(start: 1, text: "gone", in: text, with: nil))
    }

    func testNormalisedLine() {
        XCTAssertEqual(DayFile.normalisedLine("10:05-11:20 fixed it #quilt"), "- 10:05-11:20 (1h15) fixed it #quilt")
        XCTAssertEqual(DayFile.normalisedLine("- 9:30- running"), "- 09:30- running")
        XCTAssertEqual(DayFile.normalisedLine("10:05-11:20 (9h99) stale duration"), "- 10:05-11:20 (1h15) stale duration")
        XCTAssertNil(DayFile.normalisedLine("no time here"))
        XCTAssertNil(DayFile.normalisedLine("10:00"))
    }

    func testLinkPrefixAndCompletions() {
        XCTAssertEqual(Links.openLinkPrefix(before: "see [[Pug"), "Pug")
        XCTAssertEqual(Links.openLinkPrefix(before: "see [["), "")
        XCTAssertNil(Links.openLinkPrefix(before: "see [[Pugmarks]] and"))
        XCTAssertNil(Links.openLinkPrefix(before: "[[a\nb"))

        let pages = ["Ideas", "Pugmarks"], notes = ["Weekly Notes", "Groceries"]
        XCTAssertEqual(Links.completions(for: "pug", pages: pages, notes: notes), ["Pugmarks"])
        XCTAssertEqual(Links.completions(for: "notes:week", pages: pages, notes: notes), ["notes:Weekly Notes"])
        XCTAssertEqual(Links.completions(for: "", pages: pages, notes: notes).count, 4)
        XCTAssertEqual(Links.noteName("notes: Weekly Notes"), "Weekly Notes")
        XCTAssertNil(Links.noteName("Pugmarks"))
    }
}
