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

    private(set) var activeScope: TodoClipboardScope?
    private(set) var revealRequest: TodoHistoryRevealRequest?
    private var openMainWindow: (() -> Void)?

    private init() {}

    func install(openMainWindow: @escaping () -> Void) {
        self.openMainWindow = openMainWindow
    }

    func activate(scope: TodoClipboardScope) {
        activeScope = scope
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
        if canActiveScopeDisplay(destination) == false {
            openMainWindow?()
        }
    }

    func resetForTesting() {
        activeScope = nil
        revealRequest = nil
        openMainWindow = nil
    }

    private func canActiveScopeDisplay(_ destination: TodoDropDestination) -> Bool {
        switch (activeScope, destination.normalized) {
        case (.today, .scheduled(let date)):
            return Calendar.current.isDateInToday(date)
        case (.scheduledMonth(let year, let month), .scheduled(let date)):
            let components = Calendar.current.dateComponents([.year, .month], from: date)
            return components.year == year && components.month == month
        case (.longTerm, .longTerm):
            return true
        default:
            return false
        }
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
