import AppKit
import Foundation
import Observation

enum TodoListCommand: Equatable {
    case copy
    case cut
    case paste
    case selectAll
    case moveUp
    case moveDown
    case undo
    case redo
}

enum TodoListCommandInvocation: Equatable {
    case keyboardShortcut
    case menu
}

struct TodoListCommandRegistration: Hashable {
    fileprivate let id: UUID
}

struct TodoListTemporaryCommandClaim: Hashable {
    fileprivate let id: UUID
    fileprivate let temporaryRegistrationId: UUID
    fileprivate let previousRegistrationId: UUID?
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
    private var activeTemporaryClaim: TodoListTemporaryCommandClaim?

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
        removeExpiredRegistrations()
        guard registrations[registration.id] != nil else {
            let replacement = register(module)
            claim(replacement)
            return replacement
        }

        registrations[registration.id] = WeakTodoListActionModule(module)
        if activeTemporaryClaim?.previousRegistrationId != registration.id {
            claim(registration)
        }
        return registration
    }

    @discardableResult
    func claim(_ registration: TodoListCommandRegistration) -> Bool {
        removeExpiredRegistrations()
        if let activeTemporaryClaim,
           activeTemporaryClaim.temporaryRegistrationId != registration.id {
            return false
        }
        guard let module = registrations[registration.id]?.value else { return false }
        currentRegistrationId = registration.id
        module.activateHistoryContext()
        return true
    }

    func isCurrent(_ module: TodoListActionModule) -> Bool {
        currentModule === module
    }

    func beginTemporaryClaim(
        _ registration: TodoListCommandRegistration
    ) -> TodoListTemporaryCommandClaim? {
        removeExpiredRegistrations()
        guard activeTemporaryClaim == nil,
              let module = registrations[registration.id]?.value
        else { return nil }

        let claim = TodoListTemporaryCommandClaim(
            id: UUID(),
            temporaryRegistrationId: registration.id,
            previousRegistrationId: currentRegistrationId
        )
        activeTemporaryClaim = claim
        currentRegistrationId = registration.id
        module.activateHistoryContext()
        return claim
    }

    @discardableResult
    func endTemporaryClaim(_ claim: TodoListTemporaryCommandClaim) -> Bool {
        guard activeTemporaryClaim?.id == claim.id else { return false }
        activeTemporaryClaim = nil

        guard currentRegistrationId == claim.temporaryRegistrationId else {
            return true
        }

        removeExpiredRegistrations()
        guard let previousRegistrationId = claim.previousRegistrationId,
              let previousModule = registrations[previousRegistrationId]?.value
        else {
            currentRegistrationId = nil
            return true
        }

        currentRegistrationId = previousRegistrationId
        previousModule.activateHistoryContext()
        return true
    }

    func availability(of command: TodoListCommand) -> TodoListCommandAvailability {
        currentModule?.commandAvailability(command) ?? .unavailable(nil)
    }

    func canCurrentListDisplayHistoryResult(at destination: TodoDropDestination) -> Bool {
        currentModule?.canDisplayHistoryResult(at: destination) == true
    }

    @discardableResult
    func perform(_ command: TodoListCommand) -> TodoListActionResult {
        perform(command, event: NSApp.currentEvent)
    }

    @discardableResult
    func perform(_ command: TodoListCommand, event: NSEvent?) -> TodoListActionResult {
        guard let currentModule else { return .noChange }
        let resolvedInvocation: TodoListCommandInvocation = if event?.type == .keyDown {
            .keyboardShortcut
        } else {
            .menu
        }
        return currentModule.perform(
            command,
            invocation: resolvedInvocation,
            event: event
        )
    }

    func resetForTesting() {
        registrations.removeAll()
        currentRegistrationId = nil
        activeTemporaryClaim = nil
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
