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

    private init() {}

    func setActiveContext(
        export: @escaping () -> String?,
        `import`: @escaping (String) -> Bool,
        canCopy: @escaping () -> Bool
    ) {
        exportHandler = export
        importHandler = `import`
        canCopyHandler = canCopy
    }

    func clearContext() {
        exportHandler = nil
        importHandler = nil
        canCopyHandler = nil
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
    func pasteFromPasteboard() -> Bool {
        guard let content = NSPasteboard.general.string(forType: .string) else { return false }
        return importHandler?(content) == true
    }
}
