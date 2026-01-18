# Notion 风格 To-Do Mac 应用

## 任务分解

### 阶段一：数据模型设计
- [x] 设计 `TodoItem` 模型（支持层级、排序、完成状态）
- [x] 设计 `DaySection` 模型（日期分组）
- [x] 配置 SwiftData Schema

### 阶段二：核心视图实现
- [x] 实现主界面布局 (`ContentView`)
- [x] 实现侧边栏月份列表 (`SidebarView`)
- [x] 实现待办事项列表 (`TodoListView`)
- [x] 实现日期分组视图 (`DaySectionView`)
- [x] 实现单个待办事项视图 (`TodoItemView`)

### 阶段三：键盘交互
- [x] Enter 键创建新待办
- [x] Backspace 删除空待办
- [x] Tab 键增加缩进
- [x] Shift+Tab 减少缩进
- [x] 上下方向键导航
- [x] 焦点跟随滚动

### 阶段四：拖拽功能
- [x] 实现拖拽句柄（鼠标悬停显示）
- [x] 实现同日期内拖拽排序
- [x] 实现跨日期拖拽
- [x] 拖拽时显示层级指示器

### 阶段五：菜单栏组件
- [x] 实现菜单栏图标
- [x] 实现今日待办弹出窗口
- [ ] 实现菜单栏内拖拽排序

### 阶段六：数据层优化
- [x] 重构为 TodoStore 单例架构
- [x] 实现内存缓存 + 异步持久化
- [x] 主窗口与菜单栏数据同步

### 阶段七：测试与验证
- [x] 修复菜单栏编辑状态下无中划线问题（通过复用 TodoItemView 解决）
- [x] 菜单栏支持 Shift+Click 多选、Delete 删除等高级功能（通过复用 TodoItemView 解决）
- [x] 优化跨窗口同步速度（添加 item.title 监听）测试
- [x] 项目编译通过
- [ ] 手动功能测试

## 阶段八：UI/UX 设计
- [x] 设计应用图标 (Liquid Glass 风格)
- [/] 筛选并确定最终图标

## 后续优化项

- [ ] 多行文本自适应高度（需使用 NSTextView 替代 NSTextField）

## 阶段九：重构与维护
- [x] 项目重命名 "notion to do" -> "todo block"
