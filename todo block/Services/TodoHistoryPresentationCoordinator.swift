import Foundation

/// 用于区分同一逻辑列表的稳定参与身份。
///
/// 内建入口使用固定身份，因此视图重建后仍能识别已经处理过的定位；
/// 临时入口则使用独立身份，避免彼此覆盖。
enum TodoListParticipationIdentity: Hashable {
    case mainWindow
    case longTerm
    case menuBar
    case ephemeral(UUID)
}

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
    private var handledParticipationIdentities: [UUID: Set<TodoListParticipationIdentity>] = [:]

    private init() {}

    /// 接收已经执行完成的历史结果。这里只发布可观察的数据，绝不决定窗口、导航或滚动。
    func present(
        _ result: TodoHistoryApplicationResult
    ) {
        let sidebarDestination = Self.sidebarDestination(for: result.destination)
        let request = TodoHistoryRevealRequest(
            id: UUID(),
            destination: sidebarDestination,
            resultDestination: result.destination.normalized,
            itemId: result.itemId,
            selectionState: result.sourceSelectionState,
            sourceHistoryContext: result.sourceHistoryContext
        )
        revealRequest = request
        handledParticipationIdentities = [request.id: []]
    }

    /// 标记一个可见逻辑列表已处理当前定位请求。
    ///
    /// 已被新请求取代的旧请求不能再处理；同一逻辑列表重建后也不会重复定位。
    func consume(
        _ request: TodoHistoryRevealRequest,
        by participationIdentity: TodoListParticipationIdentity
    ) -> Bool {
        guard let revealRequest, revealRequest.id == request.id else {
            return false
        }
        var handledIdentities = handledParticipationIdentities[request.id] ?? []
        let wasInserted = handledIdentities.insert(participationIdentity).inserted
        handledParticipationIdentities[request.id] = handledIdentities
        return wasInserted
    }

    func isCurrent(_ request: TodoHistoryRevealRequest) -> Bool {
        revealRequest?.id == request.id
    }

    func resetForTesting() {
        revealRequest = nil
        handledParticipationIdentities.removeAll()
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
