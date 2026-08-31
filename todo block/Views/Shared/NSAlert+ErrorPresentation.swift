//
//  NSAlert+ErrorPresentation.swift
//  todo block
//
//  Created by Kimi on 2026/8/30.
//

import AppKit

extension NSAlert {
    /// 以 critical 样式弹出模态错误提示（备份导出/导入/恢复失败共用）。
    static func presentError(message: String, error: any Error) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = message
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}
