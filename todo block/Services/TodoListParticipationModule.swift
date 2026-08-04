import Foundation
import Observation

/// 管理单个列表参与当前列表的生命周期。
///
/// 列表只声明自己是否处于活动状态；注册、接管和编辑器直接操作的先后顺序
/// 都收敛在这里。待办动作规则仍由 `TodoListActionModule` 负责。
@MainActor
@Observable
final class TodoListParticipationModule {
    typealias HistoryRevealMatcher = @MainActor (TodoHistoryRevealRequest) -> Bool

    private let actionModule: TodoListActionModule
    private let commandCoordinator: ActiveListCommandCoordinator
    private let participationIdentity: TodoListParticipationIdentity
    private let historyPresentation: TodoHistoryPresentationCoordinator
    private let claimsCurrentListWhenFirstActivated: Bool
    private let retainsHistoryRevealsWhileInactive: Bool
    private var historyRevealMatches: HistoryRevealMatcher
    private var commandRegistration: TodoListCommandRegistration?
    private var temporaryCommandClaim: TodoListTemporaryCommandClaim?
    private var handledHistoryRevealId: UUID?
    private var ignoredHistoryRevealId: UUID?
    private var historyRevealRequest: TodoHistoryRevealRequest?
    private var hasAppeared = false

    private(set) var isActive = false
    private(set) var editorActions = TodoEditorActions()

    var selectionManager: SelectionManager { actionModule.selectionManager }
    var feedback: TodoListFeedback? { actionModule.feedbackPresenter.feedback }
    var isCurrentList: Bool { commandCoordinator.isCurrent(actionModule) }

    init(
        actionModule: TodoListActionModule,
        commandCoordinator: ActiveListCommandCoordinator? = nil,
        participationIdentity: TodoListParticipationIdentity? = nil,
        historyPresentation: TodoHistoryPresentationCoordinator? = nil,
        claimsCurrentListWhenFirstActivated: Bool = true,
        retainsHistoryRevealsWhileInactive: Bool = true,
        historyRevealMatches: @escaping HistoryRevealMatcher = { $0.destination == .longTerm }
    ) {
        self.actionModule = actionModule
        self.commandCoordinator = commandCoordinator ?? .shared
        self.participationIdentity = participationIdentity ?? .ephemeral(UUID())
        self.historyPresentation = historyPresentation ?? .shared
        self.claimsCurrentListWhenFirstActivated = claimsCurrentListWhenFirstActivated
        self.retainsHistoryRevealsWhileInactive = retainsHistoryRevealsWhileInactive
        self.historyRevealMatches = historyRevealMatches
        editorActions = makeEditorActions()
    }

    /// 声明列表首次出现。不同列表可以选择是否在首次可见时自动成为当前列表。
    func appear(isActive: Bool) {
        guard hasAppeared == false else {
            update(isActive: isActive)
            return
        }
        hasAppeared = true
        update(
            isActive: isActive,
            claimsCurrentListWhenActivating: claimsCurrentListWhenFirstActivated
        )
    }

    /// 声明列表是否正在接收用户操作。重新可用的活动列表立即成为当前列表。
    func update(isActive: Bool) {
        update(isActive: isActive, claimsCurrentListWhenActivating: true)
    }

    private func update(
        isActive: Bool,
        claimsCurrentListWhenActivating: Bool
    ) {
        guard self.isActive != isActive else { return }
        self.isActive = isActive

        if isActive {
            let registration = register()
            if claimsCurrentListWhenActivating {
                _ = commandCoordinator.claim(registration)
            }
            receiveHistoryReveal(historyRevealRequest)
        } else {
            actionModule.feedbackPresenter.clear()
            if let commandRegistration {
                commandCoordinator.unregister(commandRegistration)
                self.commandRegistration = nil
            }
        }
    }

    /// 注册为可接管的列表，但不改变当前列表。用于菜单栏等长期存在的入口。
    @discardableResult
    func register() -> TodoListCommandRegistration {
        if let commandRegistration {
            return commandRegistration
        }
        let registration = commandCoordinator.register(actionModule)
        commandRegistration = registration
        return registration
    }

    /// 在菜单栏实际打开时临时接管；重复通知不会覆盖原来的临时接管。
    func beginTemporaryParticipation() {
        guard temporaryCommandClaim == nil else { return }
        actionModule.feedbackPresenter.clear()
        let registration = register()
        guard let temporaryClaim = commandCoordinator.beginTemporaryClaim(registration) else {
            isActive = false
            return
        }
        temporaryCommandClaim = temporaryClaim
        isActive = true
        receiveHistoryReveal(historyRevealRequest)
    }

    /// 声明菜单栏面板是否实际可见。注册、临时接管和释放顺序由模块自行收敛。
    func updateTemporaryParticipation(isVisible: Bool) {
        register()
        if isVisible {
            beginTemporaryParticipation()
        } else {
            endTemporaryParticipation()
        }
    }

    /// 在菜单栏关闭时结束临时接管，并恢复此前仍有效的列表。
    func endTemporaryParticipation() {
        actionModule.feedbackPresenter.clear()
        isActive = false
        historyRevealRequest = nil
        if let requestId = handledHistoryRevealId {
            ignoredHistoryRevealId = requestId
        }
        guard let temporaryCommandClaim else { return }
        commandCoordinator.endTemporaryClaim(temporaryCommandClaim)
        self.temporaryCommandClaim = nil
    }

    /// 更新列表可响应命令的范围，不改变注册或当前列表归属。
    func updateCommandScope(_ scope: TodoClipboardScope) {
        actionModule.updateCommandScope(scope)
    }

    /// 更新当前列表可展示的历史结果范围，不改变参与身份或命令归属。
    func updateHistoryRevealMatcher(_ matcher: @escaping HistoryRevealMatcher) {
        historyRevealMatches = matcher
        receiveHistoryReveal(historyRevealRequest)
    }

    /// 供列表按钮等直接用户操作使用。接管失败时动作不会执行。
    func performDirectAction(_ action: (TodoListActionModule) -> Void) {
        guard claimCurrentList() else { return }
        action(actionModule)
    }

    /// 消费外层已经定位到本列表的历史结果，并恢复相关用户状态。
    func receiveHistoryReveal(_ request: TodoHistoryRevealRequest?) {
        guard let request else {
            historyRevealRequest = nil
            return
        }
        guard isActive || retainsHistoryRevealsWhileInactive else {
            ignoredHistoryRevealId = request.id
            historyRevealRequest = nil
            return
        }
        guard ignoredHistoryRevealId != request.id else {
            historyRevealRequest = nil
            return
        }
        guard historyRevealMatches(request) else { return }
        historyRevealRequest = request
        guard isActive,
              handledHistoryRevealId != request.id
        else { return }
        guard historyPresentation.consume(request, by: participationIdentity) else {
            historyRevealRequest = nil
            return
        }
        handledHistoryRevealId = request.id
        actionModule.restoreHistorySelection(
            request.selectionState,
            itemId: request.itemId,
            sourceHistoryContext: request.sourceHistoryContext
        )
    }

    var visibleHistoryRevealRequest: TodoHistoryRevealRequest? {
        guard isActive,
              let request = historyRevealRequest,
              historyPresentation.isCurrent(request),
              historyRevealMatches(request)
        else { return nil }
        return request
    }

    private func claimCurrentList() -> Bool {
        guard isActive else {
            actionModule.feedbackPresenter.present(message: "请在当前列表中重试")
            return false
        }
        guard let commandRegistration else {
            actionModule.feedbackPresenter.present(message: "请在当前列表中重试")
            return false
        }
        return commandCoordinator.claim(commandRegistration)
    }

    private func makeEditorActions() -> TodoEditorActions {
        let baseActions = actionModule.editorActions
        var actions = baseActions

        actions.claimCurrentList = { [weak self] in
            _ = self?.claimCurrentList()
        }
        actions.titleChanged = { [weak self] itemId, event in
            self?.performEditorDirectAction {
                baseActions.titleChanged(itemId, event)
            }
        }
        actions.toggleCompleted = { [weak self] itemId in
            self?.performEditorDirectAction {
                baseActions.toggleCompleted(itemId)
            }
        }
        actions.selectItem = { [weak self] itemId, shiftPressed, cursorPosition in
            self?.performEditorDirectAction {
                baseActions.selectItem(itemId, shiftPressed, cursorPosition)
            }
        }
        actions.clearSelection = { [weak self] in
            self?.performEditorDirectAction {
                baseActions.clearSelection()
            }
        }
        actions.captureDragSelectionBefore = { [weak self] in
            self?.performEditorDirectAction {
                baseActions.captureDragSelectionBefore()
            }
        }
        actions.beginDragSelection = { [weak self] itemId, cursorPosition in
            self?.performEditorDirectAction {
                baseActions.beginDragSelection(itemId, cursorPosition)
            }
        }
        actions.updateDragSelection = { [weak self] itemId in
            self?.performEditorDirectAction {
                baseActions.updateDragSelection(itemId)
            }
        }
        actions.addItem = { [weak self] destination in
            self?.performEditorDirectAction {
                baseActions.addItem(destination)
            }
        }
        actions.enterPressed = { [weak self] itemId, action in
            guard let self, self.claimCurrentList() else { return false }
            return baseActions.enterPressed(itemId, action)
        }
        actions.deletePressed = { [weak self] itemId in
            self?.performEditorDirectAction {
                baseActions.deletePressed(itemId)
            }
        }
        actions.indent = { [weak self] itemId in
            self?.performEditorDirectAction {
                baseActions.indent(itemId)
            }
        }
        actions.outdent = { [weak self] itemId in
            self?.performEditorDirectAction {
                baseActions.outdent(itemId)
            }
        }
        actions.moveFocus = { [weak self] itemId, direction, cursorPosition, horizontalOffset in
            self?.performEditorDirectAction {
                baseActions.moveFocus(itemId, direction, cursorPosition, horizontalOffset)
            }
        }
        actions.moveItemByKeyboard = { [weak self] itemId, direction in
            self?.performEditorDirectAction {
                baseActions.moveItemByKeyboard(itemId, direction)
            }
        }
        actions.moveDraggedItem = { [weak self] itemId, destination, index, indentLevel in
            self?.performEditorDirectAction {
                baseActions.moveDraggedItem(itemId, destination, index, indentLevel)
            }
        }
        actions.moveDraggedItemToSidebar = { [weak self] itemId, destination in
            self?.performEditorDirectAction {
                baseActions.moveDraggedItemToSidebar(itemId, destination)
            }
        }
        actions.sectionDateChanged = { [weak self] sectionId, date in
            self?.performEditorDirectAction {
                baseActions.sectionDateChanged(sectionId, date)
            }
        }

        return actions
    }

    private func performEditorDirectAction(_ action: () -> Void) {
        guard claimCurrentList() else { return }
        action()
    }
}
