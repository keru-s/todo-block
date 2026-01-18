# 数据层重构计划：内存缓存 + 数据同步

## 问题分析

当前架构的问题：
1. `todoItems` 是计算属性，每次访问都查询数据库
2. 快速操作时 index 和数据不同步，导致越界
3. 主窗口和菜单栏各自独立查询，无法实时同步

---

## 解决方案

使用单例 `TodoStore` 作为数据中心，内存缓存 + 异步持久化：

```
┌─────────────┐     ┌─────────────┐
│  主窗口视图  │     │  菜单栏视图  │
└──────┬──────┘     └──────┬──────┘
       │                   │
       └───────┬───────────┘
               │ @Observable
       ┌───────▼───────┐
       │   TodoStore   │  ← 单例，内存缓存
       │  (Observable) │
       └───────┬───────┘
               │ 异步保存
       ┌───────▼───────┐
       │   SwiftData   │
       └───────────────┘
```

---

## Proposed Changes

### [MODIFY] [TodoDataService.swift](file:///Users/songkeru/Repository/notion%20to%20do/notion%20to%20do/Models/TodoDataService.swift)

重命名为 `TodoStore`，改为单例模式：

```swift
@MainActor
@Observable
final class TodoStore {
    static let shared = TodoStore()
    
    // 内存缓存
    private(set) var todoItems: [UUID: TodoItem] = [:]  // 按 ID 索引
    private(set) var daySections: [UUID: DaySection] = [:]
    
    // 按日期分组的待办（计算属性，从缓存派生）
    func items(for date: Date) -> [TodoItem]
    
    // CRUD 操作（直接修改缓存，异步持久化）
    func createItem(...) -> TodoItem
    func deleteItem(_ item: TodoItem)
    func updateItem(_ item: TodoItem)
}
```

---

### [MODIFY] DaySectionView.swift

从计算属性改为监听 TodoStore：

```diff
- private var todoItems: [TodoItem] {
-     dataService.fetchTodoItems(for: section.date)
- }
+ private var todoItems: [TodoItem] {
+     TodoStore.shared.items(for: section.date)
+ }
```

由于 `TodoStore` 是 `@Observable`，当缓存变化时视图自动刷新。

---

### [MODIFY] MenuBarView.swift

同样使用 TodoStore.shared，与主窗口共享状态。

---

### [MODIFY] notion_to_doApp.swift

在 App 启动时初始化 TodoStore 并加载数据：

```swift
@main
struct notion_to_doApp: App {
    init() {
        TodoStore.shared.loadFromDatabase(modelContext)
    }
}
```

---

## 关键设计

### 1. 操作即时响应

```swift
func deleteItem(_ item: TodoItem) {
    // 1. 立即从缓存移除（UI 即时响应）
    todoItems.removeValue(forKey: item.id)
    
    // 2. 异步持久化（不阻塞 UI）
    Task { await persistDelete(item) }
}
```

### 2. 焦点安全

操作直接在缓存数组上进行，index 始终与当前数据一致。

### 3. 多视图同步

TodoStore 是 `@Observable` 单例，任何视图的修改都会触发所有监听视图刷新。

---

## Verification

1. 快速创建/删除多个待办，验证无越界崩溃
2. 在菜单栏标记完成，验证主窗口同步更新
3. 使用方向键导航，验证焦点跟踪正常
