//
//  BackupMenuUITests.swift
//  todo blockUITests
//
//  全量备份（PR #59 / issue #54 Testing Decisions）的 File 菜单薄集成测试：
//  验证「文件」菜单里三条备份命令的标题、可用状态与真实接线：
//  - 「导入备份…」「导出备份…」始终可用；点击后分别弹出打开/存储面板，
//    Escape 取消后不产生任何后续窗口，恢复点状态不变；
//  - 「恢复到最近一次导入前…」在无恢复点（-UITestRecoveryState none）时禁用，
//    在有恢复点（seeded）时启用；点击后弹出风险确认 sheet，点「取消」后
//    sheet 消失且待办/日期分组/恢复点/撤销重做状态全部不变（spec #58 验收）。
//
//  恢复点状态通过启动参数 -UITestRecoveryState 控制、测试数据通过
//  -UITestSeedContent 播种（入口见 todo_blockApp.swift 的 BackupRecoveryUITestHook /
//  ContentSeedUITestHook，后者只转发到 Services/TodoStore+UITestSeeding.swift）：
//  XCUITest runner 是沙盒进程（entitlement 只有 read-only 的 / 例外），无法直接
//  改写被测 app 容器里的恢复点文件，所以由 app 在启动时把恢复点目录重定向到
//  测试专用目录并按参数重置。真实的 BackupRecovery 目录和 SwiftData 数据
//  （-UITestInMemoryStore 内存容器）都不会被测试触碰。
//
//  同理，启动期的窗口恢复也必须由 app 自己处理：UI 测试模式下
//  todo_blockApp 对主窗口设置了 .restorationBehavior(.disabled)，
//  保证即使用户以「窗口已关闭」状态退出过 app，测试启动也一定有主窗口。
//  （CopyMarkdownFeedbackLoopUITests 在 runner 侧删 savedState 的做法在沙盒
//  runner 下是静默 no-op，本套测试不依赖它。）
//
//  面板/弹窗只做最薄的验证：点击命令 → 面板/sheet 出现 → 取消 → 消失 →
//  通过菜单可用状态与「无后续窗口」确认数据未被改动。不做文件选择等深度自动化。
//

import AppKit
import XCTest

final class BackupMenuUITests: XCTestCase {

    /// 与 todo_blockApp.swift 中三条备份命令的标题完全一致（含 U+2026 省略号）。
    private enum MenuTitle {
        static let importBackup = "导入备份…"
        static let exportBackup = "导出备份…"
        static let exactRestore = "恢复到最近一次导入前…"
    }

    /// NSOpenPanel / NSSavePanel 的窗口标题（panel.title，见
    /// TodoBackupFileImporter / TodoBackupFileExporter）。沙盒 app 的面板
    /// 进程内呈现，作为 app 的普通窗口出现在 AX 树里。
    private enum PanelTitle {
        static let importBackup = "导入备份"
        static let exportBackup = "导出备份"
        /// 导入成功后才会出现的预览窗口；取消打开面板时绝不能出现。
        static let importPreview = "导入备份预览"
    }

    /// 各用例在首次访问 app 之前设置：none = 无恢复点，seeded = 有恢复点。
    private var recoveryState = "none"

    /// true 时追加 -UITestSeedContent：app 启动后播种「守卫分组」+「守卫待办」。
    private var seedContent = false

    /// 惰性创建以便在 setUp 的跳过检查之后才实例化。
    private lazy var app: XCUIApplication = {
        let app = XCUIApplication()
        // -UITestInMemoryStore：内存容器，不读写用户真实 SwiftData 数据。
        // 无值 flag 必须放在最后——它若紧跟另一个 -key，UserDefaults 参数解析
        // 会把下一个 key 吞成自己的值（见 CopyMarkdownFeedbackLoopUITests 实测注释）。
        var arguments = ["-UITestRecoveryState", recoveryState]
        if seedContent { arguments.append("-UITestSeedContent") }
        arguments.append("-UITestInMemoryStore")
        app.launchArguments = arguments
        return app
    }()

    override func setUpWithError() throws {
        continueAfterFailure = false

        // 上一个用例的 terminate() 返回时进程可能仍在退出中；若此时 launch()，
        // LaunchServices 可能激活正在退出的旧实例（无窗口、无测试参数）。
        // 先等旧实例彻底消失。
        waitForProcessExit()

        // macOS 不允许同 bundle id 的两个实例并存：若用户的 app 正在运行，
        // launch() 只会激活既有实例（无测试参数），必须跳过。
        let running = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.insight.to-do-block"
        )
        try XCTSkipIf(
            running.isEmpty == false,
            "检测到正在运行的 todo block 实例；请先退出再跑 UI 测试，避免误操作真实数据"
        )
    }

    override func tearDownWithError() throws {
        app.terminate()
        // terminate() 只是把退出事件发给当前进程，不等它真正退出。
        // 若旧进程还没死透下一个用例就 launch()，迟到的退出事件可能被
        // 投递给新实例，表现为新实例启动后立即自行退出
        // （查询报 "Application is not running"）。等进程彻底消失再结束。
        waitForProcessExit()
    }

    /// 轮询直到没有 bundle id 为 com.insight.to-do-block 的进程存活（上限 10 秒）。
    private func waitForProcessExit() {
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            let alive = NSRunningApplication.runningApplications(
                withBundleIdentifier: "com.insight.to-do-block"
            )
            if alive.isEmpty { return }
            usleep(200_000)
        }
    }

    // MARK: - 冒烟：菜单接线与可用状态

    /// 干净状态（无恢复点）：三条命令都在「文件」菜单里；
    /// 导入/导出可用，精确恢复禁用——验证恢复可用性正确反映到菜单。
    @MainActor
    func testBackupCommandsPresentAndExactRestoreDisabledWithoutRecoveryPoint() throws {
        recoveryState = "none"
        launchApp()

        let importState = waitForMenuItem(MenuTitle.importBackup, expectedEnabled: true)
        let exportState = waitForMenuItem(MenuTitle.exportBackup, expectedEnabled: true)
        let restoreState = waitForMenuItem(MenuTitle.exactRestore, expectedEnabled: false)

        XCTAssertTrue(importState.exists, "文件菜单缺少「\(MenuTitle.importBackup)」")
        XCTAssertTrue(exportState.exists, "文件菜单缺少「\(MenuTitle.exportBackup)」")
        XCTAssertTrue(restoreState.exists, "文件菜单缺少「\(MenuTitle.exactRestore)」")
        XCTAssertTrue(importState.isEnabled, "「\(MenuTitle.importBackup)」应始终可用")
        XCTAssertTrue(exportState.isEnabled, "「\(MenuTitle.exportBackup)」应始终可用")
        XCTAssertFalse(restoreState.isEnabled, "无恢复点时「\(MenuTitle.exactRestore)」应禁用")
    }

    /// 恢复点存在时「恢复到最近一次导入前…」应变为可用——
    /// 验证菜单命令与 TodoBackupRecoveryCoordinator.hasRecoveryPoint 的接线。
    @MainActor
    func testExactRestoreEnabledWhenRecoveryPointExists() throws {
        recoveryState = "seeded"
        launchApp()

        let restoreState = waitForMenuItem(MenuTitle.exactRestore, expectedEnabled: true)

        XCTAssertTrue(restoreState.exists, "文件菜单缺少「\(MenuTitle.exactRestore)」")
        XCTAssertTrue(restoreState.isEnabled, "恢复点存在时「\(MenuTitle.exactRestore)」应可用")
    }

    // MARK: - 点击接线验证：面板/sheet 出现与取消

    /// 点击「导入备份…」应弹出打开面板；Escape 取消后导入预览窗口不出现，
    /// 且恢复点状态未被触碰（精确恢复仍禁用）。
    @MainActor
    func testImportBackupOpensPanelAndCancelKeepsStateUnchanged() throws {
        recoveryState = "none"
        launchApp()

        XCTAssertTrue(clickFileMenuItem(MenuTitle.importBackup), "无法点击「\(MenuTitle.importBackup)」")

        let panel = app.windows[PanelTitle.importBackup]
        XCTAssertTrue(panel.waitForExistence(timeout: 5), "点击「导入备份…」后没有出现打开面板")

        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        XCTAssertTrue(waitForDisappearance(panel, timeout: 5), "Escape 后打开面板未消失")

        XCTAssertFalse(
            app.windows[PanelTitle.importPreview].exists,
            "取消打开面板后不应出现导入预览窗口（导入不应继续）"
        )
        let restoreState = waitForMenuItem(MenuTitle.exactRestore, expectedEnabled: false)
        XCTAssertFalse(restoreState.isEnabled, "取消导入面板不应改变恢复点状态（仍应无恢复点）")
    }

    /// 点击「导出备份…」应弹出存储面板；Escape 取消后不出现任何错误弹窗，
    /// 恢复点状态不变（精确恢复仍禁用）。
    @MainActor
    func testExportBackupOpensSavePanelAndCancelKeepsStateUnchanged() throws {
        recoveryState = "none"
        launchApp()

        XCTAssertTrue(clickFileMenuItem(MenuTitle.exportBackup), "无法点击「\(MenuTitle.exportBackup)」")

        let panel = app.windows[PanelTitle.exportBackup]
        XCTAssertTrue(panel.waitForExistence(timeout: 5), "点击「导出备份…」后没有出现存储面板")

        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        XCTAssertTrue(waitForDisappearance(panel, timeout: 5), "Escape 后存储面板未消失")

        XCTAssertTrue(app.dialogs.count == 0, "取消存储面板后不应残留任何弹窗")
        let restoreState = waitForMenuItem(MenuTitle.exactRestore, expectedEnabled: false)
        XCTAssertFalse(restoreState.isEnabled, "取消存储面板不应改变恢复点状态（仍应无恢复点）")
    }

    /// 有恢复点时点击「恢复到最近一次导入前…」应弹出风险确认 sheet；
    /// 点「取消」后 sheet 消失，恢复点不被消费（恢复命令保持可用）。
    @MainActor
    func testExactRestoreShowsConfirmationAndCancelKeepsCheckpoint() throws {
        recoveryState = "seeded"
        launchApp()

        XCTAssertTrue(clickFileMenuItem(MenuTitle.exactRestore), "无法点击「\(MenuTitle.exactRestore)」")

        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "点击「恢复到最近一次导入前…」后没有出现确认 sheet")
        XCTAssertTrue(
            sheet.staticTexts["恢复到最近一次导入前？"].exists,
            "确认 sheet 缺少风险说明标题"
        )
        XCTAssertTrue(sheet.buttons["取消"].exists, "确认 sheet 缺少「取消」按钮")
        XCTAssertTrue(sheet.buttons["恢复"].exists, "确认 sheet 缺少「恢复」按钮")

        sheet.buttons["取消"].click()
        XCTAssertTrue(waitForDisappearance(sheet, timeout: 5), "点「取消」后确认 sheet 未消失")

        // 检查点未被消费：恢复命令仍可用。若取消误触发了恢复，
        // consumeRecoveryPoint 会移除检查点，此断言会立刻暴露。
        let restoreState = waitForMenuItem(MenuTitle.exactRestore, expectedEnabled: true)
        XCTAssertTrue(restoreState.isEnabled, "取消确认 sheet 不应消费恢复点（恢复命令应仍可用）")
    }

    /// spec #58 验收：取消精确恢复后，待办、日期分组、恢复点、撤销/重做状态
    /// 四类状态全部不变。启动时播种「守卫分组」+「守卫待办」（-UITestSeedContent，
    /// 播种不经 undoManager），再做一次真实的 UI 文字编辑使「撤销」可用，
    /// 记录前置状态 → 打开确认 sheet → 取消 → 逐项比对。
    @MainActor
    func testExactRestoreCancelKeepsDataCheckpointAndUndoState() throws {
        recoveryState = "seeded"
        seedContent = true
        launchApp()

        let window = mainWindow()
        let titles = window.descendants(matching: .textView)
            .matching(identifier: "todo-title")
        XCTAssertTrue(titles.element(boundBy: 0).waitForExistence(timeout: 5), "播种的守卫待办未出现")
        XCTAssertEqual(titles.count, 1, "应只有播种的一条待办")
        XCTAssertEqual(titles.element(boundBy: 0).value as? String, "守卫待办")
        XCTAssertTrue(sectionHeaderExists(in: window), "播种的日期分组「守卫分组」未出现")

        // 一次真实的 UI 文字编辑（点击标题 → 输入 X → Escape 结束编辑），
        // 让操作历史里出现一个可撤销操作。落点位置不确定，编辑后的实际标题
        // 读出来作为后续比对的基准。
        titles.element(boundBy: 0).click()
        usleep(500_000)
        app.typeText("X")
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        usleep(300_000)
        guard let editedTitle = titles.element(boundBy: 0).value as? String,
              editedTitle != "守卫待办", editedTitle.contains("X")
        else {
            XCTFail("文字编辑未生效，前置条件不成立")
            return
        }

        // 前置状态：撤销可用（刚产生的编辑）、重做不可用（尚未撤销过）、恢复点存在。
        let undoBefore = waitForMenuItem("撤销", inMenu: ["编辑", "Edit"], expectedEnabled: true)
        let redoBefore = waitForMenuItem("恢复", inMenu: ["编辑", "Edit"], expectedEnabled: false)
        let restoreBefore = waitForMenuItem(MenuTitle.exactRestore, expectedEnabled: true)
        XCTAssertTrue(undoBefore.isEnabled, "文字编辑后「撤销」应可用")
        XCTAssertFalse(redoBefore.isEnabled, "尚未撤销过时「恢复」应不可用")
        XCTAssertTrue(restoreBefore.isEnabled, "有恢复点时恢复命令应可用")

        // 打开确认 sheet 并取消。
        XCTAssertTrue(clickFileMenuItem(MenuTitle.exactRestore), "无法点击「\(MenuTitle.exactRestore)」")
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "点击「恢复到最近一次导入前…」后没有出现确认 sheet")
        sheet.buttons["取消"].click()
        XCTAssertTrue(waitForDisappearance(sheet, timeout: 5), "点「取消」后确认 sheet 未消失")

        // 待办与日期分组不变。
        XCTAssertEqual(titles.count, 1, "取消恢复后待办条数变了")
        XCTAssertEqual(
            titles.element(boundBy: 0).value as? String, editedTitle,
            "取消恢复后待办标题变了"
        )
        XCTAssertTrue(sectionHeaderExists(in: window), "取消恢复后日期分组丢失")

        // 恢复点未被消费。
        let restoreAfter = waitForMenuItem(MenuTitle.exactRestore, expectedEnabled: true)
        XCTAssertTrue(restoreAfter.isEnabled, "取消恢复不应消费恢复点（恢复命令应仍可用）")

        // 撤销/重做可用性与取消前一致。
        let undoAfter = waitForMenuItem("撤销", inMenu: ["编辑", "Edit"], expectedEnabled: true)
        let redoAfter = waitForMenuItem("恢复", inMenu: ["编辑", "Edit"], expectedEnabled: false)
        XCTAssertEqual(
            undoAfter.isEnabled, undoBefore.isEnabled,
            "取消恢复后「撤销」可用性变了（前=\(undoBefore.isEnabled) 后=\(undoAfter.isEnabled)）"
        )
        XCTAssertEqual(
            redoAfter.isEnabled, redoBefore.isEnabled,
            "取消恢复后「恢复」可用性变了（前=\(redoBefore.isEnabled) 后=\(redoAfter.isEnabled)）"
        )
    }

    // MARK: - 启动与窗口

    @MainActor
    private func launchApp() {
        app.launch()
        // 主窗口出现意味着 ContentView.onAppear 已执行，
        // TodoBackupRecoveryCoordinator.hasRecoveryPoint 已按恢复点状态刷新。
        if mainWindow().waitForExistence(timeout: 10) == false {
            // 诊断打进断言消息（print 在 runner 日志里不保证可见）：
            // app 进程状态、窗口列表、菜单栏内容——区分「进程没起来」
            // 「起来了但无窗口」「有窗口但标题不符」三种失败形态。
            let running = NSRunningApplication
                .runningApplications(withBundleIdentifier: "com.insight.to-do-block")
                .map { "pid=\($0.processIdentifier) active=\($0.isActive) finishedLaunching=\($0.isFinishedLaunching)" }
                .joined(separator: "; ")
            let windowTitles = app.windows.allElementsBoundByIndex.map { "'\($0.title)'" }
            let menuBarTitles = app.menuBars.menuBarItems.allElementsBoundByIndex.map { $0.title }
            XCTFail(
                "主窗口未出现。app.state=\(app.state.rawValue) "
                    + "runningApps=[\(running)] "
                    + "windows(\(app.windows.count))=\(windowTitles) "
                    + "menuBarItems=\(menuBarTitles)"
            )
        }
    }

    @MainActor
    private func mainWindow() -> XCUIElement {
        var window = app.windows["待办"].exists
            ? app.windows["待办"]
            : app.windows.firstMatch
        if window.waitForExistence(timeout: 10) == false {
            // 兜底：XCUITest 以后台方式启动 app，SwiftUI Window scene 偶发不创建
            // 主窗口。注意「窗口」菜单里没有 reopen 项（实测该菜单只有系统窗口
            // 管理项，SwiftUI 不为 Window scene 注册菜单项），所以通过
            // LaunchServices 对运行中的 app 重发 reopen（等价于点击 Dock 图标），
            // SwiftUI 会响应 reopen 呈现主窗口。
            reopenApp()
            window = app.windows["待办"].exists
                ? app.windows["待办"]
                : app.windows.firstMatch
        }
        if window.waitForExistence(timeout: 8) == false {
            reopenApp()
            window = app.windows["待办"].exists
                ? app.windows["待办"]
                : app.windows.firstMatch
        }
        return window
    }

    /// 对运行中的被测 app 重发 reopen 事件（不重启、不重传启动参数）。
    @MainActor
    private func reopenApp() {
        guard let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.insight.to-do-block"
        ) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in }
    }

    // MARK: - 菜单交互

    /// 打开指定菜单栏菜单读取菜单项的 enabled 状态，读取后关闭菜单。
    /// hasRecoveryPoint 在 onAppear 里同步赋值，但 SwiftUI command 的 disabled
    /// 状态推送到 AppKit 菜单是异步的：菜单未真正打开（或启动后初期）时，
    /// NSMenuItem 可能还停留在默认 enabled=true。因此只在菜单确认打开后读取，
    /// 且状态不符预期时重开菜单重试，吸收推送时序抖动。
    @MainActor
    private func waitForMenuItem(
        _ title: String,
        inMenu menuBarTitles: [String] = ["文件", "File"],
        expectedEnabled: Bool,
        timeout: TimeInterval = 10
    ) -> (exists: Bool, isEnabled: Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        var last: (exists: Bool, isEnabled: Bool) = (false, false)
        repeat {
            if let item = openMenuItem(title, inMenu: menuBarTitles) {
                let isEnabled = item.isEnabled
                closeMenu()
                last = (true, isEnabled)
                if isEnabled == expectedEnabled { break }
            } else {
                usleep(300_000)
            }
        } while Date() < deadline
        return last
    }

    /// 打开「文件」菜单并点击指定菜单项（点击后菜单自动关闭，命令开始执行）。
    @MainActor
    private func clickFileMenuItem(_ title: String) -> Bool {
        guard let item = openMenuItem(title, inMenu: ["文件", "File"]) else { return false }
        item.click()
        return true
    }

    /// 点击指定菜单栏项并返回指定标题的菜单项；找不到时关闭菜单并返回 nil。
    /// 注意 click 是切换语义：已打开时再点会把菜单关掉。所以每次都先 Escape
    /// 回到「无菜单打开」的确定状态再点击，并等 menu 元素确认出现后才读取，
    /// 避免读到未验证菜单里的默认 enabled 状态。
    @MainActor
    private func openMenuItem(_ title: String, inMenu menuBarTitles: [String]) -> XCUIElement? {
        guard let menuBarItem = menuBarTitles
            .map({ app.menuBars.menuBarItems[$0] })
            .first(where: { $0.exists })
        else { return nil }

        closeMenu()
        menuBarItem.click()

        let menu = menuBarItem.menus.firstMatch
        guard menu.waitForExistence(timeout: 3) else { return nil }

        let item = menu.menuItems[title]
        guard item.waitForExistence(timeout: 3) else {
            closeMenu()
            return nil
        }
        return item
    }

    /// 日期分组标题的可见性：分组头是 TodoEditorSectionView 里的 NSButton
    /// （titleButton.title = 分组标题），按 button 查询。
    @MainActor
    private func sectionHeaderExists(in window: XCUIElement) -> Bool {
        window.buttons["守卫分组"].exists
    }

    @MainActor
    private func closeMenu() {
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        usleep(200_000)
    }

    // MARK: - 通用等待

    private func waitForDisappearance(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists == false { return true }
            usleep(100_000)
        }
        return element.exists == false
    }
}
