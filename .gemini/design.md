# 设计规范

## 主题色

统一使用 **蓝色** 作为主题色，遵循 macOS 设计语言。

### 颜色定义

| 用途 | 颜色 | SwiftUI 值 |
|------|------|------------|
| 主题色/强调色 | 系统蓝 | `Color.accentColor` |
| 选中高亮 | 蓝色半透明 | `Color.accentColor.opacity(0.2)` |
| 拖拽插入指示器 | 系统蓝 | `Color.accentColor` |
| 操作按钮 | 系统蓝 | `.foregroundColor(.accentColor)` |
| 完成状态 | 绿色 | `.green` |
| 次要文本 | 灰色 | `.gray` / `.secondary` |

### 使用场景

- **插入线指示器**：蓝色圆点 + 蓝色线条
- **选中项背景**：`accentColor.opacity(0.2)`
- **添加按钮**：蓝色文字 + 图标
- **完成勾选框**：绿色对勾

## 设计原则

1. 遵循 macOS Human Interface Guidelines
2. 使用系统 `accentColor` 确保与用户系统偏好一致
3. 保持视觉简洁，避免过多颜色
