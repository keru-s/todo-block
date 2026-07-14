import Foundation

struct TodoHistoryRevealRequest: Equatable {
    let id: UUID
    let destination: SidebarDestination
    let resultDestination: TodoDropDestination
    let itemId: UUID?
    let selectionState: TodoSelectionState?
}

@MainActor
@Observable
final class TodoHistoryPresentationCoordinator {
    static let shared = TodoHistoryPresentationCoordinator()

    private(set) var revealRequest: TodoHistoryRevealRequest?
    private var openMainWindow: (() -> Void)?

    private init() {}

    func install(openMainWindow: @escaping () -> Void) {
        self.openMainWindow = openMainWindow
    }

    func reveal(
        destination: TodoDropDestination,
        itemId: UUID?,
        selectionState: TodoSelectionState? = nil
    ) {
        let sidebarDestination = Self.sidebarDestination(for: destination)
        revealRequest = TodoHistoryRevealRequest(
            id: UUID(),
            destination: sidebarDestination,
            resultDestination: destination.normalized,
            itemId: itemId,
            selectionState: selectionState
        )
        if ActiveListCommandCoordinator.shared
            .canCurrentListDisplayHistoryResult(at: destination) == false {
            openMainWindow?()
        }
    }

    func resetForTesting() {
        revealRequest = nil
        openMainWindow = nil
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
