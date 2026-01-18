//
//  TodoStoreTests.swift
//  todo blockTests
//
//  Created by Claude on 2026/1/17.
//

import XCTest
import SwiftData
@testable import todo_block

@MainActor
final class TodoStoreTests: XCTestCase {
    
    var descriptor: ModelContainer!
    
    override func setUp() async throws { 
        // Use in-memory container for testing
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        descriptor = try ModelContainer(for: TodoItem.self, DaySection.self, configurations: config)
        
        TodoStore.shared.initialize(with: descriptor.mainContext)
        TodoStore.shared.reset()
        
        // Clear shared store cache between tests (important because it's a singleton)
        // Since we re-initialize with a fresh context, it should reload from empty
    }
    
    func testCreateItem() {
        let store = TodoStore.shared
        let date = Date()
        
        let item = store.createItem(title: "Test Item", dayDate: date)
        
        XCTAssertEqual(item.title, "Test Item")
        XCTAssertEqual(store.items(for: date).count, 1)
        XCTAssertEqual(store.items(for: date).first?.id, item.id)
        XCTAssertTrue(store.todoItemsCache.keys.contains(item.id))
    }
    
    func testDeleteItem() {
        let store = TodoStore.shared
        let date = Date()
        let item = store.createItem(title: "To Delete", dayDate: date)
        
        XCTAssertEqual(store.items(for: date).count, 1)
        
        store.deleteItem(item)
        
        XCTAssertEqual(store.items(for: date).count, 0)
        XCTAssertFalse(store.todoItemsCache.keys.contains(item.id))
    }
    
    func testItemSorting() {
        let store = TodoStore.shared
        let date = Date()
        
        let item1 = store.createItem(title: "First", dayDate: date)
        // createItem automatically adds with sortOrder increment
        let item2 = store.createItem(title: "Second", dayDate: date)
        
        let items = store.items(for: date)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].id, item1.id)
        XCTAssertEqual(items[1].id, item2.id)
        XCTAssertLessThan(items[0].sortOrder, items[1].sortOrder)
    }
    
    func testIndent() {
        let store = TodoStore.shared
        let item = store.createItem(dayDate: Date())
        
        XCTAssertEqual(item.indentLevel, 0)
        
        item.indent()
        XCTAssertEqual(item.indentLevel, 1)
        
        item.indent()
        item.indent()
        item.indent() // max 3
        XCTAssertEqual(item.indentLevel, 3)
        
        item.outdent()
        XCTAssertEqual(item.indentLevel, 2)
    }
    
    func testCompleteToggle() {
        let store = TodoStore.shared
        let item = store.createItem(dayDate: Date())
        
        XCTAssertFalse(item.isCompleted)
        
        store.toggleComplete(item)
        XCTAssertTrue(item.isCompleted)
        
        store.toggleComplete(item)
        XCTAssertFalse(item.isCompleted)
    }
    
    func testChildCompletionPropagation() {
        let store = TodoStore.shared
        let date = Date()
        
        /*
         Parent
           Child 1 (indent 1)
           Child 2 (indent 1)
         Sibling (indent 0)
         */
        
        let parent = store.createItem(title: "Parent", dayDate: date, indentLevel: 0)
        let child1 = store.createItem(title: "Child 1", dayDate: date, indentLevel: 1)
        let child2 = store.createItem(title: "Child 2", dayDate: date, indentLevel: 1)
        let sibling = store.createItem(title: "Sibling", dayDate: date, indentLevel: 0)
        
        // Completing parent should complete children
        store.toggleComplete(parent)
        
        XCTAssertTrue(parent.isCompleted)
        XCTAssertTrue(child1.isCompleted)
        XCTAssertTrue(child2.isCompleted)
        XCTAssertFalse(sibling.isCompleted) // Sibling unaffected
        
        // Uncompleting parent
        store.toggleComplete(parent)
        XCTAssertFalse(parent.isCompleted)
        XCTAssertFalse(child1.isCompleted)
        XCTAssertFalse(child2.isCompleted)
    }
}
