import Foundation
import Observation

enum TodoListCommand: Equatable {
    case copy
    case cut
    case paste
    case moveUp
    case moveDown
    case undo
    case redo
}

struct TodoListCommandRegistration: Hashable {
    fileprivate let id: UUID
}

private final class WeakTodoListActionModule {
    weak var value: TodoListActionModule?

    init(_ value: TodoListActionModule) {
        self.value = value
    }
}

@MainActor
@Observable
final class ActiveListCommandCoordinator {
    static let shared = ActiveListCommandCoordinator()

    private var registrations: [UUID: WeakTodoListActionModule] = [:]
    private var currentRegistrationId: UUID?

    private init() {}

    var hasCurrentList: Bool {
        currentModule != nil
    }

    func register(_ module: TodoListActionModule) -> TodoListCommandRegistration {
        removeExpiredRegistrations()
        let registration = TodoListCommandRegistration(id: UUID())
        registrations[registration.id] = WeakTodoListActionModule(module)
        return registration
    }

    func unregister(_ registration: TodoListCommandRegistration) {
        registrations[registration.id] = nil
        if currentRegistrationId == registration.id {
            currentRegistrationId = nil
        }
    }

    func replaceAndClaim(
        _ registration: TodoListCommandRegistration,
        with module: TodoListActionModule
    ) -> TodoListCommandRegistration {
        unregister(registration)
        let replacement = register(module)
        claim(replacement)
        return replacement
    }

    @discardableResult
    func claim(_ registration: TodoListCommandRegistration) -> Bool {
        removeExpiredRegistrations()
        guard let module = registrations[registration.id]?.value else { return false }
        currentRegistrationId = registration.id
        module.activateHistoryContext()
        return true
    }

    func isCurrent(_ module: TodoListActionModule) -> Bool {
        currentModule === module
    }

    func availability(of command: TodoListCommand) -> TodoListCommandAvailability {
        currentModule?.commandAvailability(command) ?? .unavailable(nil)
    }

    @discardableResult
    func perform(_ command: TodoListCommand) -> TodoListActionResult {
        currentModule?.perform(command) ?? .noChange
    }

    func resetForTesting() {
        registrations.removeAll()
        currentRegistrationId = nil
    }

    private var currentModule: TodoListActionModule? {
        guard let currentRegistrationId else { return nil }
        guard let module = registrations[currentRegistrationId]?.value else {
            self.currentRegistrationId = nil
            registrations[currentRegistrationId] = nil
            return nil
        }
        return module
    }

    private func removeExpiredRegistrations() {
        registrations = registrations.filter { $0.value.value != nil }
        if let currentRegistrationId,
           registrations[currentRegistrationId] == nil {
            self.currentRegistrationId = nil
        }
    }
}
