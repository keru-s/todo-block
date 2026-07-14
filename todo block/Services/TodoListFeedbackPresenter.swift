import AppKit
import Foundation
import Observation

struct TodoListFeedback: Equatable, Identifiable {
    let id: UUID
    let message: String
}

@MainActor
@Observable
final class TodoListFeedbackPresenter {
    private(set) var feedback: TodoListFeedback?

    private let displayDuration: Duration
    private let announce: @MainActor (String) -> Void
    private var dismissalTask: Task<Void, Never>?

    init(
        displayDuration: Duration = .seconds(3),
        announce: @escaping @MainActor (String) -> Void =
            TodoListFeedbackPresenter.announceForAccessibility
    ) {
        self.displayDuration = displayDuration
        self.announce = announce
    }

    func consume(_ result: TodoListActionResult) {
        guard case .rejected(let rejection) = result else { return }

        let feedback = TodoListFeedback(
            id: UUID(),
            message: message(for: rejection)
        )
        dismissalTask?.cancel()
        self.feedback = feedback
        announce(feedback.message)

        let displayDuration = displayDuration
        dismissalTask = Task { [weak self] in
            do {
                try await Task.sleep(for: displayDuration)
            } catch {
                return
            }
            guard let self else { return }
            guard self.feedback?.id == feedback.id else { return }
            self.feedback = nil
            self.dismissalTask = nil
        }
    }

    func clear() {
        dismissalTask?.cancel()
        dismissalTask = nil
        feedback = nil
    }

    private func message(for rejection: TodoListActionRejection) -> String {
        switch rejection {
        case .finishCurrentInput:
            "请先结束当前输入"
        case .openMainWindowForHistory:
            "请在主窗口撤销或恢复上一次操作"
        case .itemNoLongerAvailable:
            "这项待办已不存在"
        }
    }

    private static func announceForAccessibility(_ message: String) {
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: NSAccessibilityPriorityLevel.medium.rawValue
            ]
        )
    }
}
