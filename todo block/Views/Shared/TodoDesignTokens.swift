//
//  TodoDesignTokens.swift
//  todo block
//

import AppKit
import SwiftUI

/// 集中视图层使用的设计常量（间距/颜色/圆角）。
///
/// 字体不在本文件统一：现状 `.font(.system(size: N))` 与 `.weight(.medium/.semibold)` 组合较多，
/// 抽 token 之前需要先确定一组语义化字体角色（body / heading / secondary / hint），属下一轮工作。
enum TodoDesignTokens {
    // MARK: - Layout

    /// 单级缩进宽度。
    static let indentWidth: CGFloat = 24

    /// 列表中单条 item 的默认高度。
    static let itemHeight: CGFloat = 28

    // MARK: - Colors

    /// 分区背景的强调色。
    static let bucketTint = Color.accentColor.opacity(0.05)

    /// 行选中态的高亮色。
    static let selectionTint = Color.accentColor.opacity(0.2)

    /// 主窗口 / popover / 拖动预览的窗口背景
    static let windowBackground = Color(NSColor.windowBackgroundColor)

    // MARK: - Corners

    /// 桶/卡片外框圆角
    static let bucketCornerRadius: CGFloat = 8

    /// 拖动预览圆角（更紧凑）
    static let dragPreviewCornerRadius: CGFloat = 6
}
