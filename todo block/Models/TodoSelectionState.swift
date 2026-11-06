import Foundation

struct TodoSelectionState: Equatable {
    let focusedItemId: UUID?
    let selectedItemIds: Set<UUID>
    let lastSelectedId: UUID?
    let cursorPosition: Int
    let textSelectionLength: Int
    let focusesText: Bool

    init(selectionManager: SelectionManager) {
        focusedItemId = selectionManager.focusedItemId
        selectedItemIds = selectionManager.selectedItemIds
        lastSelectedId = selectionManager.lastSelectedId
        cursorPosition = selectionManager.cursorPosition
        textSelectionLength = selectionManager.textSelectionLength
        focusesText = selectionManager.focusesText
    }

    init(focusing itemId: UUID?, cursorPosition: Int = 0, focusesText: Bool = true) {
        focusedItemId = itemId
        selectedItemIds = itemId.map { [$0] } ?? []
        lastSelectedId = itemId
        self.cursorPosition = cursorPosition
        textSelectionLength = 0
        self.focusesText = focusesText
    }

    init(
        focusedItemId: UUID?,
        selectedItemIds: Set<UUID>,
        lastSelectedId: UUID?,
        cursorPosition: Int,
        textSelectionLength: Int = 0,
        focusesText: Bool = true
    ) {
        self.focusedItemId = focusedItemId
        self.selectedItemIds = selectedItemIds
        self.lastSelectedId = lastSelectedId
        self.cursorPosition = cursorPosition
        self.textSelectionLength = textSelectionLength
        self.focusesText = focusesText
    }

}
