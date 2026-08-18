//
//  TodoEditorEntry.swift
//  todo block
//

import CoreGraphics
import Foundation

/// 编辑器表面的访问权限。
enum TodoEditorAccess: Equatable {
    case editable
    case readOnly

    var isEditable: Bool {
        self == .editable
    }
}

/// 光标位置感知的 Enter 行为分档。
enum EnterAction {
    case insertSiblingAbove
    case insertSiblingBelow
    case insertSiblingBelowAfterTextReplacement(
        beforeTitle: String,
        newCurrentTitle: String,
        beforeSelection: TodoTextSelection
    )
    case splitIntoChild(newCurrentTitle: String, childTitle: String)
}

enum TodoEditorFocusMoveDirection {
    case up
    case down
}

/// 待办编辑器唯一的动作入口。
///
/// 这个入口同时表达编辑器权限、原生识别结果和连续编辑区过程。视图只把
/// 识别到的事实交给入口；列表参与、用户状态和操作单元仍由列表动作模块
/// 及其已有规则负责。所有闭包都是显式接线，编辑器不会依赖默认空动作。
struct TodoEditorEntry {
    let access: TodoEditorAccess

    private let claimCurrentListAction: () -> Bool
    private let titleChangedAction: (UUID, TodoTextEditEvent) -> Void
    private let textSelectionChangedAction: (UUID, TodoTextSelection) -> Void
    private let inputSessionEndedAction: () -> Void
    private let selectItemAction: (UUID, Bool, Int?) -> Void
    private let clearSelectionAction: () -> Void
    private let captureDragSelectionBeforeAction: () -> Void
    private let discardPreparedDragSelectionAction: () -> Void
    private let beginDragSelectionAction: (UUID, Int?) -> Bool
    private let updateDragSelectionAction: (UUID) -> Void
    private let endDragSelectionAction: () -> Void
    private let cancelDragSelectionAction: () -> Void
    private let hasMultipleSelectionAction: () -> Bool
    private let addItemAction: (TodoDropDestination) -> Void
    private let enterPressedAction: (UUID, EnterAction) -> Bool
    private let deletePressedAction: (UUID, TodoTextSelection) -> Bool
    private let prepareItemDragAction: (UUID) -> Bool
    private let toggleCompletedAction: (UUID) -> Void
    private let indentAction: (UUID) -> Void
    private let outdentAction: (UUID) -> Void
    private let moveFocusAction: (UUID, TodoEditorFocusMoveDirection, Int, CGFloat?) -> Void
    private let moveItemByKeyboardAction: (UUID, TodoParentChildGroupMoveDirection) -> Void
    private let moveDraggedItemAction: (UUID, TodoDropDestination, Int, Int) -> Void
    private let moveDraggedItemToSidebarAction: (UUID, SidebarDestination) -> Void
    private let sectionDateChangedAction: (UUID, Date) -> Void
    private var beforeExplicitAction: () -> Void = {}

    init(
        access: TodoEditorAccess,
        claimCurrentList: @escaping () -> Bool,
        titleChanged: @escaping (UUID, TodoTextEditEvent) -> Void,
        textSelectionChanged: @escaping (UUID, TodoTextSelection) -> Void,
        inputSessionEnded: @escaping () -> Void,
        selectItem: @escaping (UUID, Bool, Int?) -> Void,
        clearSelection: @escaping () -> Void,
        captureDragSelectionBefore: @escaping () -> Void,
        discardPreparedDragSelection: @escaping () -> Void,
        beginDragSelection: @escaping (UUID, Int?) -> Bool,
        updateDragSelection: @escaping (UUID) -> Void,
        endDragSelection: @escaping () -> Void,
        cancelDragSelection: @escaping () -> Void,
        hasMultipleSelection: @escaping () -> Bool,
        addItem: @escaping (TodoDropDestination) -> Void,
        enterPressed: @escaping (UUID, EnterAction) -> Bool,
        deletePressed: @escaping (UUID, TodoTextSelection) -> Bool,
        prepareItemDrag: @escaping (UUID) -> Bool,
        toggleCompleted: @escaping (UUID) -> Void,
        indent: @escaping (UUID) -> Void,
        outdent: @escaping (UUID) -> Void,
        moveFocus: @escaping (UUID, TodoEditorFocusMoveDirection, Int, CGFloat?) -> Void,
        moveItemByKeyboard: @escaping (UUID, TodoParentChildGroupMoveDirection) -> Void,
        moveDraggedItem: @escaping (UUID, TodoDropDestination, Int, Int) -> Void,
        moveDraggedItemToSidebar: @escaping (UUID, SidebarDestination) -> Void,
        sectionDateChanged: @escaping (UUID, Date) -> Void,
        beforeExplicitAction: @escaping () -> Void = {}
    ) {
        self.access = access
        self.claimCurrentListAction = claimCurrentList
        self.titleChangedAction = titleChanged
        self.textSelectionChangedAction = textSelectionChanged
        self.inputSessionEndedAction = inputSessionEnded
        self.selectItemAction = selectItem
        self.clearSelectionAction = clearSelection
        self.captureDragSelectionBeforeAction = captureDragSelectionBefore
        self.discardPreparedDragSelectionAction = discardPreparedDragSelection
        self.beginDragSelectionAction = beginDragSelection
        self.updateDragSelectionAction = updateDragSelection
        self.endDragSelectionAction = endDragSelection
        self.cancelDragSelectionAction = cancelDragSelection
        self.hasMultipleSelectionAction = hasMultipleSelection
        self.addItemAction = addItem
        self.enterPressedAction = enterPressed
        self.deletePressedAction = deletePressed
        self.prepareItemDragAction = prepareItemDrag
        self.toggleCompletedAction = toggleCompleted
        self.indentAction = indent
        self.outdentAction = outdent
        self.moveFocusAction = moveFocus
        self.moveItemByKeyboardAction = moveItemByKeyboard
        self.moveDraggedItemAction = moveDraggedItem
        self.moveDraggedItemToSidebarAction = moveDraggedItemToSidebar
        self.sectionDateChangedAction = sectionDateChanged
        self.beforeExplicitAction = beforeExplicitAction
    }

    func withBeforeExplicitAction(_ action: @escaping () -> Void) -> TodoEditorEntry {
        var copy = self
        copy.beforeExplicitAction = action
        return copy
    }

    /// 只读入口显式拒绝所有编辑器动作；视图同时关闭编辑控件。
    static let readOnly = TodoEditorEntry(
        access: .readOnly,
        claimCurrentList: { false },
        titleChanged: { _, _ in },
        textSelectionChanged: { _, _ in },
        inputSessionEnded: {},
        selectItem: { _, _, _ in },
        clearSelection: {},
        captureDragSelectionBefore: {},
        discardPreparedDragSelection: {},
        beginDragSelection: { _, _ in false },
        updateDragSelection: { _ in },
        endDragSelection: {},
        cancelDragSelection: {},
        hasMultipleSelection: { false },
        addItem: { _ in },
        enterPressed: { _, _ in false },
        deletePressed: { _, _ in false },
        prepareItemDrag: { _ in false },
        toggleCompleted: { _ in },
        indent: { _ in },
        outdent: { _ in },
        moveFocus: { _, _, _, _ in },
        moveItemByKeyboard: { _, _ in },
        moveDraggedItem: { _, _, _, _ in },
        moveDraggedItemToSidebar: { _, _ in },
        sectionDateChanged: { _, _ in }
    )

    @discardableResult
    func claimCurrentList() -> Bool {
        guard access.isEditable else { return false }
        return claimCurrentListAction()
    }

    func titleChanged(_ itemId: UUID, _ event: TodoTextEditEvent) {
        guard access.isEditable else { return }
        titleChangedAction(itemId, event)
    }

    func textSelectionChanged(_ itemId: UUID, _ selection: TodoTextSelection) {
        guard access.isEditable else { return }
        textSelectionChangedAction(itemId, selection)
    }

    func inputSessionEnded() {
        guard access.isEditable else { return }
        inputSessionEndedAction()
    }

    func selectItem(
        _ itemId: UUID,
        shiftPressed: Bool,
        cursorPosition: Int?
    ) {
        guard access.isEditable else { return }
        beforeExplicitAction()
        selectItemAction(itemId, shiftPressed, cursorPosition)
    }

    func selectItem(_ itemId: UUID, _ shiftPressed: Bool, _ cursorPosition: Int?) {
        selectItem(
            itemId,
            shiftPressed: shiftPressed,
            cursorPosition: cursorPosition
        )
    }

    func clearSelection() {
        guard access.isEditable else { return }
        beforeExplicitAction()
        clearSelectionAction()
    }

    func captureDragSelectionBefore() {
        guard access.isEditable else { return }
        captureDragSelectionBeforeAction()
    }

    func discardPreparedDragSelection() {
        guard access.isEditable else { return }
        discardPreparedDragSelectionAction()
    }

    @discardableResult
    func beginDragSelection(_ itemId: UUID, _ cursorPosition: Int?) -> Bool {
        guard access.isEditable else { return false }
        return beginDragSelectionAction(itemId, cursorPosition)
    }

    @discardableResult
    func beginDragSelection(itemId: UUID, cursorPosition: Int? = nil) -> Bool {
        beginDragSelection(itemId, cursorPosition)
    }

    func updateDragSelection(_ itemId: UUID) {
        guard access.isEditable else { return }
        updateDragSelectionAction(itemId)
    }

    func updateDragSelection(to itemId: UUID) {
        updateDragSelection(itemId)
    }

    func endDragSelection() {
        guard access.isEditable else { return }
        endDragSelectionAction()
    }

    func cancelDragSelection() {
        guard access.isEditable else { return }
        cancelDragSelectionAction()
    }

    var hasMultipleSelection: Bool {
        access.isEditable && hasMultipleSelectionAction()
    }

    func addItem(_ destination: TodoDropDestination) {
        guard access.isEditable else { return }
        beforeExplicitAction()
        addItemAction(destination)
    }

    @discardableResult
    func enterPressed(_ itemId: UUID, _ action: EnterAction) -> Bool {
        guard access.isEditable else { return false }
        beforeExplicitAction()
        return enterPressedAction(itemId, action)
    }

    @discardableResult
    func deletePressed(
        _ itemId: UUID,
        textSelection: TodoTextSelection
    ) -> Bool {
        guard access.isEditable else { return false }
        beforeExplicitAction()
        return deletePressedAction(itemId, textSelection)
    }

    func deletePressed(_ itemId: UUID, _ textSelection: TodoTextSelection) -> Bool {
        deletePressed(itemId, textSelection: textSelection)
    }

    /// 供已经确认没有文字选区的外部动作使用。
    @discardableResult
    func deletePressed(_ itemId: UUID) -> Bool {
        deletePressed(itemId, textSelection: TodoTextSelection(location: 0, length: 0))
    }

    @discardableResult
    func prepareItemDrag(_ itemId: UUID) -> Bool {
        guard access.isEditable else { return false }
        return prepareItemDragAction(itemId)
    }

    func toggleCompleted(_ itemId: UUID) {
        guard access.isEditable else { return }
        beforeExplicitAction()
        toggleCompletedAction(itemId)
    }

    func indent(_ itemId: UUID) {
        guard access.isEditable else { return }
        beforeExplicitAction()
        indentAction(itemId)
    }

    func outdent(_ itemId: UUID) {
        guard access.isEditable else { return }
        beforeExplicitAction()
        outdentAction(itemId)
    }

    func moveFocus(
        itemId: UUID,
        direction: TodoEditorFocusMoveDirection,
        cursorPosition: Int,
        horizontalOffset: CGFloat?
    ) {
        guard access.isEditable else { return }
        beforeExplicitAction()
        moveFocusAction(itemId, direction, cursorPosition, horizontalOffset)
    }

    func moveFocus(
        _ itemId: UUID,
        _ direction: TodoEditorFocusMoveDirection,
        _ cursorPosition: Int,
        _ horizontalOffset: CGFloat?
    ) {
        moveFocus(
            itemId: itemId,
            direction: direction,
            cursorPosition: cursorPosition,
            horizontalOffset: horizontalOffset
        )
    }

    func moveItemByKeyboard(
        itemId: UUID,
        direction: TodoParentChildGroupMoveDirection
    ) {
        guard access.isEditable else { return }
        beforeExplicitAction()
        moveItemByKeyboardAction(itemId, direction)
    }

    func moveItemByKeyboard(
        _ itemId: UUID,
        _ direction: TodoParentChildGroupMoveDirection
    ) {
        moveItemByKeyboard(itemId: itemId, direction: direction)
    }

    func moveDraggedItem(
        _ itemId: UUID,
        _ destination: TodoDropDestination,
        _ insertionIndex: Int,
        _ indentLevel: Int
    ) {
        guard access.isEditable else { return }
        beforeExplicitAction()
        moveDraggedItemAction(itemId, destination, insertionIndex, indentLevel)
    }

    func moveDraggedItem(
        itemId: UUID,
        destination: TodoDropDestination,
        insertionIndex: Int,
        indentLevel: Int
    ) {
        moveDraggedItem(itemId, destination, insertionIndex, indentLevel)
    }

    func moveDraggedItemToSidebar(
        _ itemId: UUID,
        _ destination: SidebarDestination
    ) {
        guard access.isEditable else { return }
        beforeExplicitAction()
        moveDraggedItemToSidebarAction(itemId, destination)
    }

    func moveDraggedItemToSidebar(
        itemId: UUID,
        destination: SidebarDestination
    ) {
        moveDraggedItemToSidebar(itemId, destination)
    }

    func sectionDateChanged(_ sectionId: UUID, _ date: Date) {
        guard access.isEditable else { return }
        beforeExplicitAction()
        sectionDateChangedAction(sectionId, date)
    }

    @discardableResult
    func escapePressed() -> Bool {
        guard access.isEditable, hasMultipleSelection else { return false }
        clearSelectionAction()
        return true
    }
}
