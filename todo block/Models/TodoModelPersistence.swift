//
//  TodoModelPersistence.swift
//  todo block
//
//  Created by Codex on 2026/2/16.
//

import SwiftData

enum TodoModelContainerFactory {
    static let currentModelVersion = 2

    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema([TodoItem.self, DaySection.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
