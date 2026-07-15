//
//  TodoEditorActions.swift
//  todo block
//

import Foundation
import CoreGraphics

/// 光标位置感知的 Enter 行为分档。AppKit 编辑器在拦截 Return 时
/// 当场读取 selectedRange 算出该走哪一档，外层据此决定建项 / 拆项。
enum EnterAction {
    case insertSiblingAbove
    case insertSiblingBelow
    case splitIntoChild(newCurrentTitle: String, childTitle: String)
}

enum TodoEditorFocusMoveDirection {
    case up
    case down
}

struct TodoEditorActions {
    var claimCurrentList: () -> Void = {}
    var titleChanged: (UUID, TodoTextEditEvent) -> Void = { _, _ in }
    var textSelectionChanged: (UUID, TodoTextSelection) -> Void = { _, _ in }
    var inputSessionEnded: () -> Void = {}
    var toggleCompleted: (UUID) -> Void = { _ in }
    var isItemSelected: (UUID) -> Bool = { _ in false }
    var hasMultipleSelection: () -> Bool = { false }
    var selectItem: (UUID, Bool, Int?) -> Void = { _, _, _ in }
    var clearSelection: () -> Void = {}
    var captureDragSelectionBefore: () -> Void = {}
    var discardPreparedDragSelection: () -> Void = {}
    var beginDragSelection: (UUID, Int?) -> Void = { _, _ in }
    var updateDragSelection: (UUID) -> Void = { _ in }
    var endDragSelection: () -> Void = {}
    var cancelDragSelection: () -> Void = {}
    var addItem: (TodoDropDestination) -> Void = { _ in }
    var enterPressed: (UUID, EnterAction) -> Void = { _, _ in }
    var deletePressed: (UUID) -> Void = { _ in }
    var indent: (UUID) -> Void = { _ in }
    var outdent: (UUID) -> Void = { _ in }
    var moveFocus: (UUID, TodoEditorFocusMoveDirection, Int, CGFloat?) -> Void = { _, _, _, _ in }
    var moveItemByKeyboard: (UUID, TodoKeyboardReorderDirection) -> Void = { _, _ in }
    var moveDraggedItem: (UUID, TodoDropDestination, Int, Int) -> Void = { _, _, _, _ in }
    var moveDraggedItemToSidebar: (UUID, SidebarDestination) -> Void = { _, _ in }
    var sectionDateChanged: (UUID, Date) -> Void = { _, _ in }

    static let readOnly = TodoEditorActions()
}
