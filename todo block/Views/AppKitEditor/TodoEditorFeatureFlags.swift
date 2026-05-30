//
//  TodoEditorFeatureFlags.swift
//  todo block
//

import Foundation

enum TodoEditorFeatureFlags {
    static var useAppKitMonthEditor: Bool {
        #if DEBUG
            ProcessInfo.processInfo.environment["TODO_BLOCK_USE_APPKIT_EDITOR"] == "1"
        #else
            false
        #endif
    }
}

