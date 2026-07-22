# 统一操作单元、撤销恢复与可靠保存：交接说明

## 下一会话的目标

从当前可开始的任务 [#32：建立统一操作单元和单一历史](https://github.com/keru-s/todo-block/issues/32) 开始实施。不要提前实施仍被阻塞的后续任务。

## 已完成的决策与产物

- 总体规格已发布在 [#31](https://github.com/keru-s/todo-block/issues/31)。
- 架构决定已记录在 [ADR 0003](../../docs/adr/0003-rule-owned-changes-unified-operation-application.md)。术语定义补充在 [CONTEXT.md](../../CONTEXT.md)。先阅读这两份资料，不要在实现时重新解释既定规则。
- 任务已按依赖拆分并发布：[#32](https://github.com/keru-s/todo-block/issues/32) → [#33](https://github.com/keru-s/todo-block/issues/33) → [#34](https://github.com/keru-s/todo-block/issues/34)、[#35](https://github.com/keru-s/todo-block/issues/35)、[#36](https://github.com/keru-s/todo-block/issues/36)、[#37](https://github.com/keru-s/todo-block/issues/37) → [#38](https://github.com/keru-s/todo-block/issues/38) → [#39](https://github.com/keru-s/todo-block/issues/39)。所有任务均已标为可开工，且正文已写明前置任务。
- 当前只有 #32 没有前置任务；#34 至 #37 可在 #33 完成后并行。

## 当前仓库状态

- 本轮没有修改应用功能代码，也没有创建提交。
- 工作区已有两份本轮产生、尚未提交的文档：`CONTEXT.md` 的术语补充，以及 `docs/adr/0003-rule-owned-changes-unified-operation-application.md`。
- 新增本交接文件也尚未提交。不要覆盖或丢弃上述文档改动。
- 发布任务后已核对：#32 至 #39 都关联 #31、带有 `ready-for-agent` 标记，并包含正确的前置关系。

## 实施时的重要边界

- 规则各自负责计算完整结果；统一操作单元负责完整应用、历史与恢复。具体含义以 ADR 0003 为准。
- 迁移期间只能有一条正式操作历史，不能让新旧历史同时写入。
- 旧实现只能在新旧行为完整对照通过后移除。
- 只处理当前任务的范围；后续任务中的菜单栏展示、连续输入、保存失败保护等内容不要提前混入 #32，除非 #32 的验收标准明确要求。

## 建议的下一步

1. 阅读 #32、#31、ADR 0003、CONTEXT 和项目的 `AGENTS.md`。
2. 使用 `implement` 推进 #32，并以 `tdd` 先补充其验收所需的自动验证。
3. 完成后按项目规则运行完整测试；确认通过后再考虑提交。
4. 在 #32 实际完成前，不开始 #33 或其后的任务。

## Suggested skills

- `implement`：按已批准的 #32 任务实施。
- `tdd`：先建立统一操作单元与单一历史的行为验证。
- `code-review`：完成 #32 后检查是否有绕过统一入口或破坏既定边界的改动。
