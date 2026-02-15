//
//  ModelCompatibilityTests.swift
//  todo blockTests
//
//  Created by Codex on 2026/2/16.
//

import SwiftData
import XCTest

@testable import todo_block

@MainActor
final class ModelCompatibilityTests: XCTestCase {
    private let schemaVersionDefaultsKey = "todo.block.schema.version"

    override func setUp() async throws {
        UserDefaults.standard.removeObject(forKey: schemaVersionDefaultsKey)
    }

    func testInitializeMigratesEmptyContainerKindToScheduled() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: TodoItem.self, DaySection.self, configurations: config)
        let context = container.mainContext

        let legacyItem = TodoItem(
            title: "legacy",
            containerKindRaw: "",
            dayDate: Date()
        )
        context.insert(legacyItem)
        try context.save()

        TodoStore.shared.reset()
        TodoStore.shared.initialize(with: context)

        let migratedItem = TodoStore.shared.todoItemsCache[legacyItem.id]
        XCTAssertEqual(migratedItem?.containerKind, .scheduled)
        XCTAssertEqual(
            UserDefaults.standard.integer(forKey: schemaVersionDefaultsKey),
            TodoModelContainerFactory.currentModelVersion
        )
    }
}
