//
//  TodoClipboardManager.swift
//  todo block
//
//  Created by Codex on 2026/2/15.
//

import AppKit
import Observation

@MainActor
@Observable
final class TodoClipboardManager {
    static let shared = TodoClipboardManager()

    private var exportHandler: (() -> String?)?
    private var importHandler: ((String) -> Bool)?
    private var canCopyHandler: (() -> Bool)?
    private var cutHandler: (() -> Bool)?

    private init() {}

    func setActiveContext(
        export: @escaping () -> String?,
        `import`: @escaping (String) -> Bool,
        canCopy: @escaping () -> Bool,
        cut: @escaping () -> Bool
    ) {
        exportHandler = export
        importHandler = `import`
        canCopyHandler = canCopy
        cutHandler = cut
    }

    func activateListContext(
        scope: TodoClipboardScope,
        store: TodoStore,
        selectionManager: SelectionManager
    ) {
        setActiveContext(
            export: {
                store.exportMarkdown(
                    scope: scope,
                    selection: TodoClipboardSelectionSnapshot(
                        focusedItemId: selectionManager.focusedItemId,
                        selectedItemIds: selectionManager.selectedItemIds
                    )
                )
            },
            import: { markdown in
                guard store.importMarkdown(
                        markdown,
                        scope: scope,
                        selection: TodoClipboardSelectionSnapshot(
                            focusedItemId: selectionManager.focusedItemId,
                            selectedItemIds: selectionManager.selectedItemIds
                        ),
                        selectionManager: selectionManager
                    ) != nil else {
                    return false
                }

                return true
            },
            canCopy: {
                store.canCopy(
                    scope: scope,
                    selection: TodoClipboardSelectionSnapshot(
                        focusedItemId: selectionManager.focusedItemId,
                        selectedItemIds: selectionManager.selectedItemIds
                    )
                )
            },
            cut: {
                let selection = TodoClipboardSelectionSnapshot(
                    focusedItemId: selectionManager.focusedItemId,
                    selectedItemIds: selectionManager.selectedItemIds
                )
                let itemIds = store.clipboardItemIds(scope: scope, selection: selection)
                return selectionManager.deleteItems(itemIds, store: store)
            }
        )
    }

    func clearContext() {
        exportHandler = nil
        importHandler = nil
        canCopyHandler = nil
        cutHandler = nil
    }

    var canCopy: Bool {
        canCopyHandler?() ?? false
    }

    @discardableResult
    func copySelectionToPasteboard() -> Bool {
        guard let markdown = exportHandler?(), markdown.isEmpty == false else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(markdown, forType: .string)
    }

    @discardableResult
    func cutSelectionToPasteboard() -> Bool {
        guard let markdown = exportHandler?(), markdown.isEmpty == false else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(markdown, forType: .string) else { return false }
        return cutHandler?() == true
    }

    @discardableResult
    func pasteFromPasteboard() -> Bool {
        guard let content = NSPasteboard.general.string(forType: .string) else { return false }
        return importHandler?(content) == true
    }
}
