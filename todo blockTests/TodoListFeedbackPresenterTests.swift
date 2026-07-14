import XCTest
@testable import todo_block

@MainActor
final class TodoListFeedbackPresenterTests: XCTestCase {
    func testHiddenRejectionsMapToShortListMessagesAndAreAnnounced() {
        var announcements: [String] = []
        let presenter = TodoListFeedbackPresenter(
            displayDuration: .seconds(5),
            announce: { announcements.append($0) }
        )

        presenter.consume(.rejected(.finishCurrentInput))
        XCTAssertEqual(presenter.feedback?.message, "请先结束当前输入")

        presenter.consume(.rejected(.openMainWindowForHistory))
        XCTAssertEqual(presenter.feedback?.message, "请在主窗口撤销或恢复上一次操作")

        presenter.consume(.rejected(.itemNoLongerAvailable))
        XCTAssertEqual(presenter.feedback?.message, "这项待办已不存在")
        XCTAssertEqual(
            announcements,
            [
                "请先结束当前输入",
                "请在主窗口撤销或恢复上一次操作",
                "这项待办已不存在"
            ]
        )
    }

    func testVisibleBoundaryAndSuccessfulActionsStaySilent() {
        var announcements: [String] = []
        let presenter = TodoListFeedbackPresenter(
            displayDuration: .seconds(5),
            announce: { announcements.append($0) }
        )

        presenter.consume(.noChange)
        presenter.consume(.performed)

        XCTAssertNil(presenter.feedback)
        XCTAssertTrue(announcements.isEmpty)
    }

    func testEachListKeepsItsOwnFeedbackAndClearDoesNotAffectAnotherList() {
        let dateList = TodoListFeedbackPresenter(displayDuration: .seconds(5))
        let menuBarList = TodoListFeedbackPresenter(displayDuration: .seconds(5))

        dateList.consume(.rejected(.itemNoLongerAvailable))
        menuBarList.consume(.rejected(.openMainWindowForHistory))
        dateList.clear()

        XCTAssertNil(dateList.feedback)
        XCTAssertEqual(
            menuBarList.feedback?.message,
            "请在主窗口撤销或恢复上一次操作"
        )
    }

    func testNewRejectionReplacesOldFeedbackAndRestartsDismissal() async throws {
        let presenter = TodoListFeedbackPresenter(displayDuration: .seconds(1))

        presenter.consume(.rejected(.finishCurrentInput))
        try await Task.sleep(for: .milliseconds(550))
        presenter.consume(.rejected(.itemNoLongerAvailable))
        try await Task.sleep(for: .milliseconds(550))

        XCTAssertEqual(presenter.feedback?.message, "这项待办已不存在")
    }

    func testFeedbackDismissesAfterItsDisplayDuration() async throws {
        let presenter = TodoListFeedbackPresenter(displayDuration: .milliseconds(50))

        presenter.consume(.rejected(.itemNoLongerAvailable))
        try await Task.sleep(for: .seconds(1))

        XCTAssertNil(presenter.feedback)
    }
}
