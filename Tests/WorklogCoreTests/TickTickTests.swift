import XCTest
@testable import WorklogCore

final class TickTickTests: XCTestCase {
    // Shape of GET /project/{id}/data from the TickTick Open API.
    let projectData = """
    {"project":{"id":"p1","name":"📥 Quilt Ops"},
     "tasks":[
      {"id":"t1","projectId":"p1","title":"QW-1015 infra decision","dueDate":"2026-09-28T18:30:00.000+0000","status":0,"priority":5},
      {"id":"t2","projectId":"p1","title":"no due date","status":0},
      {"id":"t3","projectId":"p1","title":"next week","dueDate":"2026-10-06T18:30:00.000+0000","status":0}
     ]}
    """

    func testDecodesProjectDataAndFiltersToday() throws {
        let data = try JSONDecoder().decode(TickTick.ProjectData.self, from: Data(projectData.utf8))
        let tasks = (data.tasks ?? []).map { var t = $0; t.projectName = "📥 Quilt Ops"; return t }
        XCTAssertEqual(tasks.count, 3)
        XCTAssertNotNil(tasks[0].due)

        let now = TickTick.parseDate("2026-09-29T09:00:00.000+0000")!
        XCTAssertEqual(TickTick.dueToday(tasks, now: now).map(\.id), ["t1"])
        XCTAssertEqual(tasks[0].logText, "QW-1015 infra decision #quilt-ops")
    }

    func testTagSlug() {
        XCTAssertEqual(TickTick.tag(for: "📥 Quilt Ops"), "quilt-ops")
        XCTAssertEqual(TickTick.tag(for: "Inbox"), "inbox")
        XCTAssertEqual(TickTick.tag(for: "🎯"), "")
    }

    func testAuthRequestHasPKCE() {
        let r = TickTick.authRequest(clientId: "abc")
        let items = URLComponents(url: r.url, resolvingAgainstBaseURL: false)!.queryItems!
        let value = { (n: String) in items.first { $0.name == n }?.value }
        XCTAssertEqual(value("client_id"), "abc")
        XCTAssertEqual(value("redirect_uri"), TickTick.redirectURI)
        XCTAssertEqual(value("state"), r.state)
        XCTAssertEqual(value("code_challenge_method"), "S256")
        XCTAssertEqual(value("code_challenge")?.count, 43)
    }
}
