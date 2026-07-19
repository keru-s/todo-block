import Foundation

struct TodoHistoryRevealRequest: Equatable {
    let id: UUID
    let destination: SidebarDestination
    let resultDestination: TodoDropDestination
    let itemId: UUID?
    let selectionState: TodoSelectionState?
    let sourceHistoryContext: TodoSelectionHistoryContext?
}

@MainActor
@Observable
final class TodoHistoryPresentationCoordinator {
    static let shared = TodoHistoryPresentationCoordinator()

    private(set) var revealRequest: TodoHistoryRevealRequest?

    private init() {}

    /// 接收已经执行完成的历史结果。这里只发布可观察的数据，绝不决定窗口、导航或滚动。
    func present(
        _ result: TodoHistoryApplicationResult
    ) {
        let sidebarDestination = Self.sidebarDestination(for: result.destination)
        revealRequest = TodoHistoryRevealRequest(
            id: UUID(),
            destination: sidebarDestination,
            resultDestination: result.destination.normalized,
            itemId: result.itemId,
            selectionState: result.sourceSelectionState,
            sourceHistoryContext: result.sourceHistoryContext
        )
    }

    func resetForTesting() {
        revealRequest = nil
    }

    private static func sidebarDestination(
        for destination: TodoDropDestination
    ) -> SidebarDestination {
        switch destination.normalized {
        case .scheduled(let date):
            let components = Calendar.current.dateComponents([.year, .month], from: date)
            return .month(
                year: components.year ?? Calendar.current.component(.year, from: date),
                month: components.month ?? Calendar.current.component(.month, from: date)
            )
        case .longTerm:
            return .longTerm
        }
    }
}
