import Foundation

/// 迁移期间保留的兼容入口。长期列表与菜单栏会在后续事项中改为各自长期持有
/// `TodoListActionModule`；在此之前，它们仍通过这个入口取得相同的编辑器行为。
@MainActor
enum TodoEditorActionFactory {
    static func make(
        store: TodoStore,
        selectionManager: SelectionManager,
        sectionById: @escaping (UUID) -> DaySection? = { _ in nil }
    ) -> TodoEditorActions {
        TodoListActionModule(
            store: store,
            selectionManager: selectionManager,
            sectionById: sectionById
        ).editorActions
    }
}
