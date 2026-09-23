# memory-bank / archive — 归档区（**默认不读**）

> 本目录 2026-09-23 从源仓库 ClipboardMerger 逐字迁入（同机同工具链，见 `../decisions.md` 的 `ADR-012`）；
> 同号条目的**当前 cedinia 版本**在 `../pitfalls.md` / `../issues-solved.md` / `../decisions.md`。
> 这里放**主文件腾出来的原文**：过程分析、旧方案、失败尝试、长代码片段。
> 读取方式：只在 `issues-solved.md` / `pitfalls.md` / `decisions.md` 的条目给出
> `见 archive/xxx.md` 指针时，才读**那一节**；不做全文扫描，也不进 `README.md` 索引。

## 文件与格式
| 文件 | 收谁 | 追加方式 |
| --- | --- | --- |
| `issues-solved-archive.md` | 从 `issues-solved.md` 归档的 `ISSUE-nnn` | 按时间倒序追加，标题带原编号 |
| `pitfalls-archive.md` | 从 `pitfalls.md` 归档的 `PIT-nnn` | 同上 |
| `decisions-archive.md` | 已废弃 / 被取代的 `ADR-nnn` | 同上，保留「被 ADR-xxx 取代」关系 |

## 规则
- **逐字搬**，不改编号、不删「复发判据」——归档只为了省 token，不是丢弃信息。
- 归档后主文件原位置留一行摘要 + 指针（格式见 `../WRITING.md` §3）。
- 归档动作属于"条目更新"，要在收尾回复里说明。
