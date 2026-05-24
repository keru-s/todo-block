//
//  TodoDesignTokens.swift
//  todo block
//

import AppKit
import SwiftUI

/// 集中视图层使用的设计常量（间距/颜色/圆角）。
///
/// 引擎层（TodoDropLocationEngine / MenuBarManualReorderEngine）仍然以参数注入这些值，
/// 因此 token 只在视图原点引用 —— 引擎层保持值的可测试性。
///
/// 字体不在本文件统一：现状 `.font(.system(size: N))` 与 `.weight(.medium/.semibold)` 组合较多，
/// 抽 token 之前需要先确定一组语义化字体角色（body / heading / secondary / hint），属下一轮工作。
enum TodoDesignTokens {
    // MARK: - Layout

    /// 单级缩进宽度（视图层用作 indent indicator + leading frame；引擎层做 drop indent 解析）
    static let indentWidth: CGFloat = 24

    /// 列表中单条 item 的默认高度（也作为 drop slack 的基准）
    static let itemHeight: CGFloat = 28

    // MARK: - Colors

    /// 桶/卡片背景的强调色（DaySection / LongTermBucket）
    static let bucketTint = Color.accentColor.opacity(0.05)

    /// 行选中态的高亮色（TodoItemView / SidebarView）
    static let selectionTint = Color.accentColor.opacity(0.2)

    /// 主窗口 / popover / 拖动预览的窗口背景
    static let windowBackground = Color(NSColor.windowBackgroundColor)

    // MARK: - Corners

    /// 桶/卡片外框圆角
    static let bucketCornerRadius: CGFloat = 8

    /// 拖动预览圆角（更紧凑）
    static let dragPreviewCornerRadius: CGFloat = 6
}
