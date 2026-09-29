import XCTest
@testable import WorklogCore

final class NotesHTMLTests: XCTestCase {
    // Same shape as the real Weekly Notes body.
    let body = """
    <div><h1>Weekly Notes</h1></div>
    <div><br></div>
    <ol>
    <li>Inktober is incoming</li>
    <li>Alphonso Dunn - Workbook</li>
    </ol>
    """

    func testAppendsToExistingNumberedList() {
        let out = NotesHTML.appendingListItem("boring life <is> peaceful & calm", to: body)
        XCTAssertTrue(out.hasPrefix("<div><h1>Weekly Notes</h1></div>"))
        XCTAssertTrue(out.contains("<li>Alphonso Dunn - Workbook</li>\n<li>boring life &lt;is&gt; peaceful &amp; calm</li>\n</ol>"))
    }

    func testStartsListWhenNoneExists() {
        let out = NotesHTML.appendingListItem("first", to: "<div><h1>New</h1></div>")
        XCTAssertTrue(out.hasSuffix("<ol>\n<li>first</li>\n</ol>"))
    }

    func testNoteTextDropsOnlyWeeklyTag() {
        XCTAssertEqual(NotesHTML.noteText(from: "homelab budget #weekly #ideas"), "homelab budget #ideas")
        XCTAssertEqual(NotesHTML.noteText(from: "#weekly boring life"), "boring life")
    }

    func testWeekSummary() {
        let monday = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 28))!
        let text = """
        # d

        ## Log
        - 09:00 standup #quilt
        - 10:00-11:15 (1h15) fixed FD edge bundle #quilt
        - 11:30-12:00 (0h30) PR 823 <review> #quilt
        - 13:00-14:00 (1h00) pugmarks auth #pugmarks
        - 15:00-15:30 (0h30) thinking about homelab #weekly
        """
        let days = [NotesHTML.Day(date: monday, entries: DayFile.entries(in: text))]
        let html = NotesHTML.weekSummary(monday: monday, days: days)!
        XCTAssertTrue(html.contains("<b>Week of 28 Sep 2026</b> - 2h45 tracked"))
        XCTAssertTrue(html.contains("quilt 1h45 · pugmarks 1h00"))
        XCTAssertTrue(html.contains("<b>Mon</b>: fixed FD edge bundle; PR 823 &lt;review&gt;; pugmarks auth"))
        XCTAssertFalse(html.contains("homelab"))
        XCTAssertFalse(html.contains("standup"))
        XCTAssertTrue(NotesHTML.hasWeek(monday, in: body + html))
        XCTAssertNil(NotesHTML.weekSummary(monday: monday, days: []))
    }
}
