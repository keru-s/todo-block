//
//  TodoPreviewSupport.swift
//  todo block
//

import SwiftData

/// Shared in-memory container for `#Preview` blocks.
///
/// Previously each `#Preview` created its own `ModelContainer` and called
/// `TodoStore.shared.initialize(with:)`. Because multiple Previews can run
/// concurrently in Xcode Canvas, the singleton was being reset against
/// different contexts back-to-back, frequently crashing the canvas.
///
/// By routing all Previews through a single in-memory container, repeated
/// `initialize(with:)` calls hit the "same context" short-circuit in
/// `TodoStore.initialize` and become benign (only a `loadFromDatabase()`
/// reload, no cache wipe). The trade-off is that previews see each other's
/// seeded data — acceptable for a dev-only path.
@MainActor
enum TodoPreviewSupport {
    static let sharedContainer: ModelContainer = {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(
            for: TodoItem.self, DaySection.self, configurations: config
        )
    }()

    @discardableResult
    static func bootstrap() -> ModelContainer {
        TodoStore.shared.initialize(with: sharedContainer.mainContext)
        return sharedContainer
    }
}
