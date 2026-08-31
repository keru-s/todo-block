//
//  CopyMarkdownFeedbackLoopUITests.swift
//  todo blockUITests
//
//  反馈回路：复现「多选 todo 后 Cmd+C 复制 Markdown 无反应」。
//  bug 修复前这些测试应保持红色，修复后变绿。
//
//  数据安全：测试以 -UITestInMemoryStore 启动 app（见 todo_blockApp.swift），
//  使用内存 SwiftData 容器，不读写用户真实数据。
//  注意：测试进程会清空并读取系统剪贴板（NSPasteboard.general）。
//

import AppKit
import XCTest

final class CopyMarkdownFeedbackLoopUITests: XCTestCase {

    /// 惰性创建以便在 setUp 的跳过检查之后才实例化。
    private lazy var app: XCUIApplication = {
        let app = XCUIApplication()
        // -UITestInMemoryStore：内存容器，不读写用户真实数据。
        // -addTodayMode blank：固定底栏按钮为空白分组模式，避免依赖用户本机偏好。
        // 注意：无值 flag 必须放在最后——它若紧跟另一个 -key，参数解析会
        // 把下一个 key 吞成自己的值，剩余 token 会导致主窗口不显示（实测）。
        app.launchArguments = [
            "-addTodayMode", "blank",
            "-UITestInMemoryStore",
        ]
        return app
    }()

    override func setUpWithError() throws {
        continueAfterFailure = true

        // 上一个用例的 terminate() 返回时进程可能仍在退出中；若此时 launch()，
        // LaunchServices 可能激活正在退出的旧实例（无窗口、无测试参数），
        // 表现为「主窗口未出现」。先等旧实例彻底消失（最多 10 秒）。
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            let lingering = NSRunningApplication.runningApplications(
                withBundleIdentifier: "com.insight.to-do-block"
            )
            if lingering.isEmpty { break }
            usleep(200_000)
        }

        // macOS 不允许同 bundle id 的两个实例并存：若用户的 app 正在运行，
        // launch() 只会激活既有实例（真实数据 + 无内存容器参数），必须跳过。
        let running = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.insight.to-do-block"
        )
        try XCTSkipIf(
            running.isEmpty == false,
            "检测到正在运行的 todo block 实例；请先退出再跑 UI 测试，避免误操作真实数据"
        )

        NSPasteboard.general.clearContents()

        // 清除窗口恢复状态：此前若有实例在「窗口已关闭」状态下退出，
        // 保存的恢复状态会让主窗口在下次启动时不再出现。
        // 注意：沙盒 UI 测试 runner 对用户容器只有只读权限，这个删除实际是
        // 静默 no-op；真正的保证来自 app 侧——UI 测试模式下 todo_blockApp
        // 对主窗口设置了 .restorationBehavior(.disabled)（忽略 savedState）。
        let savedState = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Containers/com.insight.to-do-block/Data/tmp/com.insight.to-do-block.savedState")
        try? FileManager.default.removeItem(at: savedState)

        app.launch()
    }

    override func tearDownWithError() throws {
        app.terminate()
        // terminate() 只是把退出事件发给当前进程，不等它真正退出。
        // 若旧进程还没死透下一个用例就 launch()，迟到的退出事件可能被
        // 投递给新实例，表现为新实例启动后立即自行退出
        // （查询报 "Application is not running"）。等进程彻底消失再结束。
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            let alive = NSRunningApplication.runningApplications(
                withBundleIdentifier: "com.insight.to-do-block"
            )
            if alive.isEmpty { break }
            usleep(200_000)
        }
        NSPasteboard.general.clearContents()
    }

    // MARK: - 场景 1：Shift 点击多选 → Cmd+C

    /// 静态调查已确认：Shift 点击多选后 first responder 仍是标题 text view
    /// 且文字选区为空，commandAvailability(.copy) 返回 .unavailable。
    /// 期望（修复后）：剪贴板写入包含三条 todo 的 Markdown checklist。
    @MainActor
    func testShiftClickMultiSelectThenCopyWritesMarkdown() throws {
        let titles = try seedThreeTodos()
        let first = titles.element(boundBy: 0)
        let third = titles.element(boundBy: 2)

        first.click()
        shiftClick(third)

        XCTAssertTrue(
            selectionCountBadge("已选 3 项").waitForExistence(timeout: 3),
            "Shift 点击后未形成 3 项多选，测试前置条件不成立"
        )

        let menuState = inspectCopyMenuItem()
        app.typeKey("c", modifierFlags: .command)
        let clipboard = waitForPasteboardString(timeout: 2)

        assertClipboardContainsMarkdown(
            clipboard,
            scenario: "Shift 点击多选",
            copyMenuItemState: menuState
        )
    }

    // MARK: - 场景 2：从标题文字起手拖选（路径 A）→ Cmd+C

    /// 未解之谜：该路径会把 first responder 移交给行（ TodoEditorRowView ），
    /// 理论上不命中 activeTextView 门控，但用户实测复制仍失败。
    /// 本测试用于暴露第三个断点（菜单 disabled 状态过期 / perform 早退）。
    @MainActor
    func testDragFromTitleMultiSelectThenCopyWritesMarkdown() throws {
        let titles = try seedThreeTodos()
        let first = titles.element(boundBy: 0)
        let third = titles.element(boundBy: 2)

        first.click(forDuration: 0.8, thenDragTo: third)

        XCTAssertTrue(
            selectionCountBadge("已选 3 项").waitForExistence(timeout: 3),
            "从标题拖选后未形成 3 项多选，测试前置条件不成立"
        )

        // 先按 Cmd+C（模拟真人操作：拖选完直接复制，不会先点开菜单），
        // 再读菜单状态做诊断，避免开菜单/Escape 改变 first responder 干扰复现。
        app.typeKey("c", modifierFlags: .command)
        let clipboard = waitForPasteboardString(timeout: 2)
        let menuState = inspectCopyMenuItem()

        assertClipboardContainsMarkdown(
            clipboard,
            scenario: "标题起手拖选（路径 A）",
            copyMenuItemState: menuState
        )
    }

    // MARK: - 数据准备

    /// 通过 UI 创建三条 todo：Alpha / Beta / Gamma，返回标题文本框查询。
    @MainActor
    private func seedThreeTodos() throws -> XCUIElementQuery {
        let window = mainWindow()

        let titles = window.descendants(matching: .textView)
            .matching(identifier: "todo-title")

        // 空库时没有今日分组：底栏按钮是「添加空白待办」，第一次点击只创建分组
        // （TodoListActionModule.addToday 的 .blank 分支不建条目）；分组出现后
        // 按钮变为「添加一个今日待办」，再点一次才会创建首行并聚焦标题。
        for _ in 0..<3 where titles.element(boundBy: 0).exists == false {
            // 窗口刚出现时底栏按钮可能尚未布局完成，用短等待代替即时 exists。
            let addButton = [
                "添加一个今日待办",
                "添加待办",
                "添加空白待办",
                "添加今日待办",
            ].map { window.buttons[$0] }.first { $0.waitForExistence(timeout: 1) }
            guard let addButton else {
                XCTFail("找不到添加待办按钮")
                throw XCTSkip("无法准备测试数据")
            }
            addButton.click()
            _ = titles.element(boundBy: 0).waitForExistence(timeout: 2)
        }

        XCTAssertTrue(
            titles.element(boundBy: 0).waitForExistence(timeout: 5),
            "点击添加按钮后没有出现待办行"
        )
        // 新建行的标题焦点是异步 apply 的（TodoEditorRowView.apply 里的 Task），
        // 稍等再开始打字。
        usleep(500_000)

        // 回车创建新行后焦点是异步移动的（冷启动时可能超过 1s），
        // 直接 typeText 会把文字打进上一行（实测出现过 "AlphaBeta" 粘连）。
        // 每条新行都先显式 click 聚焦再输入，保证确定性。
        app.typeText("Alpha")
        app.typeKey(XCUIKeyboardKey.return.rawValue, modifierFlags: [])
        XCTAssertTrue(titles.element(boundBy: 1).waitForExistence(timeout: 5), "回车后未出现第 2 行")
        titles.element(boundBy: 1).click()
        usleep(300_000)
        app.typeText("Beta")
        app.typeKey(XCUIKeyboardKey.return.rawValue, modifierFlags: [])
        XCTAssertTrue(titles.element(boundBy: 2).waitForExistence(timeout: 5), "回车后未出现第 3 行")
        titles.element(boundBy: 2).click()
        usleep(300_000)
        app.typeText("Gamma")
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])

        XCTAssertEqual(titles.count, 3, "应创建 3 条 todo（Alpha/Beta/Gamma）")
        XCTAssertEqual(titles.element(boundBy: 0).value as? String, "Alpha")
        XCTAssertEqual(titles.element(boundBy: 1).value as? String, "Beta")
        XCTAssertEqual(titles.element(boundBy: 2).value as? String, "Gamma")

        // 确保 Escape 之后没有文字选区残留影响后续操作。
        usleep(300_000)
        return titles
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
        XCTAssertTrue(window.waitForExistence(timeout: 5), "主窗口未出现")
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

    @MainActor
    private func selectionCountBadge(_ title: String) -> XCUIElement {
        mainWindow().staticTexts[title]
    }

    // MARK: - 场景 3 诊断：读取「复制」菜单项 enabled 状态

    /// 打开编辑菜单读取「复制」项是否可用，随后关闭菜单。
    /// 用于区分「菜单项被禁用（Cmd+C 根本没派发）」和「perform 执行了但没写剪贴板」。
    @MainActor
    private func inspectCopyMenuItem() -> String {
        let menuBarItem = ["编辑", "Edit"]
            .map { app.menuBars.menuBarItems[$0] }
            .first { $0.exists }
        guard let menuBarItem else {
            return "未找到编辑菜单"
        }
        menuBarItem.click()

        let copyItem = app.menuItems["复制"]
        let exists = copyItem.waitForExistence(timeout: 3)
        let state = exists
            ? "复制菜单项存在，isEnabled=\(copyItem.isEnabled)"
            : "复制菜单项不存在"

        // 关闭菜单，把焦点还给主窗口。
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        usleep(200_000)
        return state
    }

    // MARK: - 断言

    private func assertClipboardContainsMarkdown(
        _ clipboard: String?,
        scenario: String,
        copyMenuItemState: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let diagnostics = """
            场景：\(scenario)
            菜单诊断：\(copyMenuItemState)
            剪贴板实际内容：\(clipboard.map { "\"\($0)\"" } ?? "<空>")
            """
        guard let clipboard else {
            XCTFail(
                "Cmd+C 后剪贴板仍为空（bug 复现）。\n\(diagnostics)",
                file: file,
                line: line
            )
            return
        }
        XCTAssertTrue(
            clipboard.contains("- [ ] Alpha")
                && clipboard.contains("- [ ] Beta")
                && clipboard.contains("- [ ] Gamma"),
            "剪贴板内容不是三条 todo 的 Markdown checklist。\n\(diagnostics)",
            file: file,
            line: line
        )
    }

    // MARK: - 底层交互

    /// XCUITest 没有 modifier+click API，用 CGEvent 合成 Shift+点击。
    /// 注意：要先把鼠标 move 到目标位置再按下，否则 AppKit 可能用旧光标位置做 hit-test。
    private func shiftClick(_ element: XCUIElement) {
        let frame = element.frame
        let point = CGPoint(x: frame.midX, y: frame.midY)
        let source = CGEventSource(stateID: .hidSystemState)
        let move = CGEvent(
            mouseEventSource: source,
            mouseType: .mouseMoved,
            mouseCursorPosition: point,
            mouseButton: .left
        )
        let mouseDown = CGEvent(
            mouseEventSource: source,
            mouseType: .leftMouseDown,
            mouseCursorPosition: point,
            mouseButton: .left
        )
        let mouseUp = CGEvent(
            mouseEventSource: source,
            mouseType: .leftMouseUp,
            mouseCursorPosition: point,
            mouseButton: .left
        )
        move?.post(tap: .cghidEventTap)
        usleep(100_000)
        mouseDown?.flags = .maskShift
        mouseUp?.flags = .maskShift
        mouseDown?.post(tap: .cghidEventTap)
        usleep(60_000)
        mouseUp?.post(tap: .cghidEventTap)
        usleep(200_000)
    }

    private func waitForPasteboardString(timeout: TimeInterval) -> String? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let string = NSPasteboard.general.string(forType: .string),
               string.isEmpty == false {
                return string
            }
            usleep(100_000)
        }
        return nil
    }
}
