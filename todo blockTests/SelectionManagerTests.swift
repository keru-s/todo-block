//
//  SelectionManagerTests.swift
//  todo blockTests
//
//  Created by Claude on 2026/1/17.
//

import XCTest
@testable import todo_block

@MainActor
final class SelectionManagerTests: XCTestCase {
    
    var selectionManager: SelectionManager!
    var items: [TodoItem]!
    
    override func setUp() {
        super.setUp()
        selectionManager = SelectionManager()
        
        // Create 5 items
        items = (0..<5).map { i in
            TodoItem(title: "Item \(i)", sortOrder: Double(i))
        }
    }
    
    // MARK: - Selection Tests
    
    @MainActor
    func testSingleSelect() {
        let item = items[0]
        selectionManager.handleSelect(item: item, allItems: items, shiftPressed: false)
        
        XCTAssertEqual(selectionManager.selectedItemIds.count, 1)
        XCTAssertTrue(selectionManager.selectedItemIds.contains(item.id))
        XCTAssertEqual(selectionManager.focusedItemId, item.id)
        XCTAssertEqual(selectionManager.lastSelectedId, item.id)
    }
    
    @MainActor
    func testMultiSelectWithShift() {
        // Select first
        selectionManager.handleSelect(item: items[0], allItems: items, shiftPressed: false)
        
        // Shift select third (should select 0, 1, 2)
        selectionManager.handleSelect(item: items[2], allItems: items, shiftPressed: true)
        
        XCTAssertEqual(selectionManager.selectedItemIds.count, 3)
        XCTAssertTrue(selectionManager.selectedItemIds.contains(items[0].id))
        XCTAssertTrue(selectionManager.selectedItemIds.contains(items[1].id))
        XCTAssertTrue(selectionManager.selectedItemIds.contains(items[2].id))
        XCTAssertEqual(selectionManager.focusedItemId, items[2].id)
    }
    
    @MainActor
    func testReverseMultiSelect() {
        // Select third
        selectionManager.handleSelect(item: items[2], allItems: items, shiftPressed: false)
        
        // Shift select first (should select 0, 1, 2)
        selectionManager.handleSelect(item: items[0], allItems: items, shiftPressed: true)
        
        XCTAssertEqual(selectionManager.selectedItemIds.count, 3)
        XCTAssertTrue(selectionManager.selectedItemIds.contains(items[0].id))
        XCTAssertTrue(selectionManager.selectedItemIds.contains(items[1].id))
        XCTAssertTrue(selectionManager.selectedItemIds.contains(items[2].id))
    }

    @MainActor
    func testLongPressDragSelectionForward() {
        selectionManager.beginDragSelection(item: items[1], allItems: items)
        selectionManager.updateDragSelection(to: items[4], allItems: items)

        XCTAssertEqual(selectionManager.selectedItemIds.count, 4)
        XCTAssertTrue(selectionManager.selectedItemIds.contains(items[1].id))
        XCTAssertTrue(selectionManager.selectedItemIds.contains(items[2].id))
        XCTAssertTrue(selectionManager.selectedItemIds.contains(items[3].id))
        XCTAssertTrue(selectionManager.selectedItemIds.contains(items[4].id))
        XCTAssertEqual(selectionManager.focusedItemId, items[4].id)
    }

    @MainActor
    func testLongPressDragSelectionBackward() {
        selectionManager.beginDragSelection(item: items[4], allItems: items)
        selectionManager.updateDragSelection(to: items[2], allItems: items)

        XCTAssertEqual(selectionManager.selectedItemIds.count, 3)
        XCTAssertTrue(selectionManager.selectedItemIds.contains(items[2].id))
        XCTAssertTrue(selectionManager.selectedItemIds.contains(items[3].id))
        XCTAssertTrue(selectionManager.selectedItemIds.contains(items[4].id))
        XCTAssertEqual(selectionManager.focusedItemId, items[2].id)
    }

    @MainActor
    func testEndLongPressDragSelection() {
        selectionManager.beginDragSelection(item: items[0], allItems: items)
        selectionManager.endDragSelection()
        selectionManager.updateDragSelection(to: items[3], allItems: items)

        XCTAssertEqual(selectionManager.selectedItemIds, Set([items[0].id]))
    }
    
    @MainActor
    func testClearSelection() {
        selectionManager.handleSelect(item: items[0], allItems: items, shiftPressed: false)
        selectionManager.clearSelection()
        
        // clearSelection only works if > 1 selected ?
        // checking implementation: if selectedItemIds.count > 1 { removeAll }
        // Let's test single selection clear
        XCTAssertEqual(selectionManager.selectedItemIds.count, 1) // Should still be 1 if implementaiton is count > 1
        
        // Test multi select clear
        selectionManager.selectedItemIds = [items[0].id, items[1].id]
        selectionManager.clearSelection()
        XCTAssertTrue(selectionManager.selectedItemIds.isEmpty)
    }
    
    // MARK: - Focus Movement Tests
    
    @MainActor
    func testMoveFocusDown() {
        selectionManager.handleSelect(item: items[0], allItems: items, shiftPressed: false)
        selectionManager.moveFocusDown(from: items[0], allItems: items)
        
        XCTAssertEqual(selectionManager.focusedItemId, items[1].id)
        XCTAssertEqual(selectionManager.selectedItemIds.first, items[1].id)
    }
    
    @MainActor
    func testMoveFocusUp() {
        selectionManager.handleSelect(item: items[1], allItems: items, shiftPressed: false)
        selectionManager.moveFocusUp(from: items[1], allItems: items)
        
        XCTAssertEqual(selectionManager.focusedItemId, items[0].id)
    }
    
    @MainActor
    func testMoveFocusBoundaries() {
        // Up at top
        selectionManager.handleSelect(item: items[0], allItems: items, shiftPressed: false)
        selectionManager.moveFocusUp(from: items[0], allItems: items)
        XCTAssertEqual(selectionManager.focusedItemId, items[0].id)
        
        // Down at bottom
        let last = items.last!
        selectionManager.handleSelect(item: last, allItems: items, shiftPressed: false)
        selectionManager.moveFocusDown(from: last, allItems: items)
        XCTAssertEqual(selectionManager.focusedItemId, last.id)
    }
}
