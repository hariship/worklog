import XCTest
@testable import WorklogCore

final class PagesTests: XCTestCase {
    var root: URL!
    var store: Store!

    override func setUp() {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = Store(root: root)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    func testLinkParsing() {
        let m = Links.matches(in: "see [[Quilt Ops]] and [[ 2026-09-29 ]], not [[]] or [[a\nb]]")
        XCTAssertEqual(m.map(\.target), ["Quilt Ops", "2026-09-29"])
        XCTAssertEqual(Links.doc(for: "Quilt Ops"), .page("Quilt Ops"))
        let day = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 29))!
        XCTAssertEqual(Links.doc(for: "2026-09-29"), .day(day))
    }

    func testLineMentionsByLinkOrTag() {
        XCTAssertTrue(Links.line("- 10:00 call about [[quilt ops]]", mentions: "Quilt Ops"))
        XCTAssertTrue(Links.line("- 10:00-11:00 (1h00) deploy #quilt-ops", mentions: "Quilt Ops"))
        XCTAssertFalse(Links.line("- 10:00 deploy #quilt", mentions: "Quilt Ops"))
    }

    func testPagesAndBacklinks() throws {
        let day = Date()
        try store.write("# d\n\n## Log\n- 09:00 planned [[Pugmarks]] auth\n- 10:00-11:00 (1h00) M1 login #pugmarks\n- 12:00 lunch\n", for: day)
        try store.writePage("# Pugmarks\n\nDog community site.\n", name: "Pugmarks")
        try store.writePage("# Ideas\n\n- badges for [[Pugmarks]] members\n", name: "Ideas")

        XCTAssertEqual(store.pages(), ["Ideas", "Pugmarks"])
        let links = store.backlinks(to: "Pugmarks")
        XCTAssertEqual(links.map(\.line), [
            "- 09:00 planned [[Pugmarks]] auth",
            "- 10:00-11:00 (1h00) M1 login #pugmarks",
            "- badges for [[Pugmarks]] members",
        ])
        XCTAssertEqual(links.last?.doc, .page("Ideas"))
        // The page itself is not its own backlink, but search finds it.
        XCTAssertEqual(store.search("dog community").first?.doc, .page("Pugmarks"))
        XCTAssertTrue(store.pageURL("a/b: c").lastPathComponent == "a-b- c.md")
    }
}
