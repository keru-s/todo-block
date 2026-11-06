import Foundation
@testable import todo_block

extension SelectionManager {
    /// 准备测试场景时仍通过生产的完整状态入口，不开放逐字段写权限。
    /// 双重可选参数区分“不覆盖”与“明确清空”。
    func configureSelection(
        focusedItemId: UUID?? = nil,
        selectedItemIds: Set<UUID>? = nil,
        lastSelectedId: UUID?? = nil,
        cursorPosition: Int? = nil,
        textSelectionLength: Int? = nil,
        focusesText: Bool? = nil
    ) {
        restore(TodoSelectionState(
            focusedItemId: focusedItemId ?? self.focusedItemId,
            selectedItemIds: selectedItemIds ?? self.selectedItemIds,
            lastSelectedId: lastSelectedId ?? self.lastSelectedId,
            cursorPosition: cursorPosition ?? self.cursorPosition,
            textSelectionLength: textSelectionLength ?? self.textSelectionLength,
            focusesText: focusesText ?? self.focusesText
        ))
    }
}
