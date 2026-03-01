# Agent Memory System 设计文档

## 1. 项目概述

### 1.1 目标

为 AI coding agent 构建一个**跨工具、可迁移、可自进化**的记忆系统，解决两个核心问题：

1. **Agent Persona（行为约束）**：定义 agent 在协助编码时应遵循的行为准则和偏好（如修改前先告知、编码风格等），确保每次对话都能一致遵守。
2. **Self-Evolving Skills（经验积累）**：将项目中解决复杂问题的经验（如 DeepSpeed Stage3 checkpoint 保存问题）结构化沉淀，使 agent 在未来遇到类似问题时能直接复用已有解决方案。

### 1.2 设计原则

- **纯文本、工具无关**：所有内容均为 Markdown/YAML 文件，不依赖任何特定 agent 的 API 或格式
- **跨工具兼容**：支持 Claude Code、Codex、Kimi Code、Cursor 等主流 coding agent，一处维护多处生效
- **分层加载，按需披露**：persona 始终加载但保持精简；skills 通过索引按需加载，避免 context 膨胀
- **半自动 + 人工审核**：agent 自动生成 skill 草稿，但只有经过人工审核确认的 skill 才进入生产使用
- **可维护性优先**：控制单文件规模，支持去重、合并、归档等生命周期管理

---

## 2. 系统架构

### 2.1 目录结构

```
~/.agent-memory/
├── persona.md                        # 行为约束（精简，每次对话加载）
│
├── workflows/                        # 流程定义（按需加载）
│   ├── skill-generation.md           # 自动生成 skill 草稿的流程与规则
│   └── skill-review.md              # 协助人审核 skill 的流程与规则
│
├── skills/                           # 经验库
│   ├── index.yaml                   # 轻量索引（仅索引 approved 的 skill）
│   ├── stats.yaml                   # 📊 使用频率统计（best-effort 更新）
│   ├── approved/                    # ✅ 经过人工审核，agent 实际参考的
│   │   ├── deepspeed/
│   │   │   ├── _summary.md          # 该类别的概述
│   │   │   ├── stage3-checkpoint.md
│   │   │   └── ...
│   │   ├── pytorch/
│   │   ├── general/                 # 暂时无法归类的 skill
│   │   └── ...
│   └── drafts/                      # 📝 待审核区，agent 自动生成
│       ├── 2026-02-28-xxx.md
│       └── ...
│
├── adapters/                         # 各工具的适配脚本
│   └── init-all.sh                  # 一键初始化各工具配置中的引用
│
└── scripts/
    └── generate-index.sh            # 从 approved/ 的 frontmatter 自动生成 index.yaml
```

### 2.2 drafts/ 与 approved/ 的目录设计

两个目录的使用场景和生命周期完全不同，因此采用不同的组织方式。

#### drafts/：扁平结构 + 日期前缀

```
skills/drafts/
├── 2026-02-28-stage3-save-issue.md
├── 2026-03-01-nccl-timeout.md
└── 2026-03-05-lora-merge-nan.md
```

drafts 是一个**临时队列**（inbox），skill 在这里停留的时间很短（从生成到下次 review）。核心操作就是"列出来，逐个审核"，因此：

- **不需要分类**：分类本身是审核的一部分，agent 在审核时才建议"这个应该放到 deepspeed/ 下"
- **日期前缀**：review 时能看到时间顺序，知道哪些是最近的、哪些积压了很久
- **扁平结构**：让"还有多少待审核"一目了然，不需要递归遍历子目录

#### approved/：二级分类目录 + 语义化文件名

```
skills/approved/
├── deepspeed/
│   ├── _summary.md
│   ├── stage3-checkpoint.md
│   └── zero-offload-oom.md
├── pytorch/
│   ├── _summary.md
│   └── nccl-timeout.md
├── general/                         # 暂时无法归入特定类别的 skill
│   └── conda-env-conflict.md
└── ...
```

approved 是长期存在的知识库，会持续增长，因此采用分层组织：

- **路径即语义**：`approved/deepspeed/stage3-checkpoint.md` 比 `approved/2026-01-15-stage3-checkpoint.md` 更直观
- **`_summary.md` 作为中间层**：agent 不确定是否需要读某个 skill 时，先读 summary 判断该类别是否相关
- **便于批量维护**：如"deepspeed 升级了大版本，把整个目录下的 skill 都 review 一遍"
- **`general/` 兜底**：不属于任何已有子目录的 skill 先放在 `general/` 下，等积累了几个同类的再拆出独立子目录

#### 从 drafts 到 approved 的迁移过程

审核通过时，实际发生以下步骤：

```
skills/drafts/2026-02-28-stage3-save-issue.md
    ↓ 审核通过
    1. 修改 frontmatter：status: draft → approved
    2. 文件名从日期前缀改为语义化名称
    3. 移动到对应分类目录：skills/approved/deepspeed/stage3-checkpoint.md
    4. 更新 index.yaml 和 stats.yaml（新增条目，use_count: 0）
    5. 删除 drafts/ 中的原文件
```

文件名在迁移时会变化：drafts 里用 `日期-描述.md` 方便按时间排序，approved 里用 `语义化名称.md` 方便按内容查找。重命名由 agent 自动建议，用户确认即可。

### 2.3 分层加载策略

系统采用**两级加载**，控制每次对话的 context 开销：

| 层级          | 内容                     | 加载时机                       | 预期大小                        |
| ------------- | ------------------------ | ------------------------------ | ------------------------------- |
| L0 - 始终加载 | `persona.md`           | 每次对话开始                   | 尽量精简                        |
| L1 - 按需索引 | `skills/index.yaml`    | agent 遇到技术问题时           | 随 skill 数量线性增长，每条几行 |
| L2 - 按需详情 | `skills/approved/*.md` | 从 index 中定位到相关 skill 后 | 单文件保持短小，过长则拆分      |
| L3 - 特定流程 | `workflows/*.md`       | 触发 skill 生成/审核时         | 单文件适中即可                  |

**关键点**：persona.md 中只包含精简的触发规则（如"遇到技术问题时查阅 index.yaml"），不包含 workflow 的具体步骤。workflow 的细节放在独立文件中，仅在触发时加载。这保证了 persona 不会随着系统复杂度增长而膨胀。

---

## 3. 模块设计

### 3.1 Persona（`persona.md`）

**定位**：每次对话都加载的行为约束文件，必须保持精简。

**内容结构**：

```markdown
# Agent Persona

## 核心原则
- [行为约束：如修改前先告知、不自行删除代码等]

## 编码偏好
- [语言/框架特定的风格偏好]

## 沟通风格
- [语言、格式等偏好]

## Skills 系统
- 遇到技术问题时，先查阅 `skills/index.yaml`，按需读取相关 approved skill
- 读取 approved skill 后，更新 `skills/stats.yaml` 中对应条目的 use_count 和 last_used；如果当前环境不支持写入，跳过此步骤
- 当一次问题解决涉及非平凡方案时，读取 `workflows/skill-generation.md` 并按流程生成草稿
- 当我说"review skills"时，读取 `workflows/skill-review.md` 并协助我审核
```

**设计决策**：

- Skills 系统的触发规则放在 persona 里，但具体的生成/审核流程独立为 workflow 文件
- 这样 persona 不会因 workflow 逻辑的迭代而频繁修改

### 3.2 Skill 生成流程（`workflows/skill-generation.md`）

**定位**：教 agent 什么时候该生成 skill 草稿、怎么生成。仅在触发时加载。

**触发条件**（满足任一）：

- 解决过程超过 3 轮调试
- 涉及查阅官方文档或源码才找到的解决方案
- 解决方案违反直觉或容易踩坑
- 用户主动说"记录一下"或类似表述

**生成规则**：

- 使用统一模板，包含 frontmatter（title, tags, created, context, status）
- 文件名格式：`YYYY-MM-DD-简短描述.md`
- 存入 `skills/drafts/` 目录
- 生成后告知用户，等待审核
- 不记录简单 typo 或一眼可见的错误
- 一个 skill 只解决一个问题，多问题拆成多文件
- 如果和已有 approved skill 相关，在草稿中注明可能需要合并

**Skill 模板**：

```markdown
---
title: [简明标题]
tags: [tag1, tag2, tag3]
created: YYYY-MM-DD
context: [哪个项目/什么场景下遇到的]
status: draft
---

### 问题
[一句话描述问题现象]

### 根因
[为什么会出现这个问题]

### 解决方案
[具体怎么解决的，附代码片段]

### 踩坑点
[容易忽略的细节、边界条件]
```

### 3.3 Skill 审核流程（`workflows/skill-review.md`）

**定位**：协助人高效审核 skill 草稿，agent 做预处理以降低人的审核成本。仅在用户触发审核时加载。

**触发方式**：用户说"review skills"或类似表述。

**审核流程**：

1. **扫描**：读取 `skills/drafts/` 目录，列出所有待审核草稿
2. **预处理**：对每个草稿进行以下检查：
   - **去重检查**：与 `approved/` 中已有 skill 对比，标注重复或可合并的条目
   - **质量检查**：解决方案是否具体可执行，是否缺少关键信息
   - **分类建议**：建议放入 `approved/` 下的哪个子目录
   - **过期风险**：如果方案依赖特定版本号，标注出来
3. **已有 skill 健康度报告**（可选）：读取 `skills/stats.yaml`，标注长期未使用（如超过 3 个月零引用）的 approved skill，建议归档或清理
4. **呈现**：对每个草稿输出：
   - 📝 标题 + 一句话摘要
   - ⚠️ 预处理发现的问题（如有）
   - 💡 建议：通过 / 修改后通过 / 建议丢弃 / 建议合并到 [已有 skill]
5. **执行用户决策**：
   - **通过**：移动到 `approved/` 对应目录，更新 `index.yaml`
   - **修改后通过**：按用户指示修改内容，然后移动到 `approved/`
   - **丢弃**：删除草稿文件
   - **合并**：将草稿内容整合到指定的已有 skill 中，删除草稿

### 3.4 Skills 索引（`skills/index.yaml`）

**定位**：approved skills 的轻量索引，供 agent 快速定位相关 skill 而无需遍历所有文件。

**格式**：

```yaml
skills:
  - id: deepspeed-stage3-ckpt
    title: "DeepSpeed Stage3 checkpoint 保存不完整"
    tags: [deepspeed, zero3, checkpoint]
    path: approved/deepspeed/stage3-checkpoint.md

  - id: nccl-timeout
    title: "多机训练 NCCL timeout 排查"
    tags: [distributed, nccl, debug]
    path: approved/pytorch/nccl-timeout.md
```

**维护方式**：

- **自动生成**（推荐）：通过 `scripts/generate-index.sh` 扫描 `approved/` 下所有 `.md` 文件的 frontmatter 自动生成，确保 index 与实际文件始终同步
- **审核流程触发**：每次 skill 审核通过时，由 agent 自动更新 index
- 对于能执行命令的 agent（如 Claude Code），可以在加载时动态生成索引而不依赖静态文件

### 3.5 Approved Skills 分类目录

`approved/` 下按技术领域组织子目录，每个子目录包含一个 `_summary.md` 提供该类别的概述：

```
approved/
├── deepspeed/
│   ├── _summary.md          # "DeepSpeed 相关经验，主要涉及 ZeRO 各 stage 的配置与问题排查"
│   └── ...
├── pytorch/
│   ├── _summary.md
│   └── ...
├── transformers/
├── linux-env/
├── general/                 # 暂时无法归入特定类别的 skill，积累同类后再拆分
└── ...
```

**可维护性约束**：

- 单个 skill 文件控制在 **50-100 行**以内，超过则拆分
- 定期合并：多个经常一起使用的小 skill 可合并为一个主题文档
- 过期机制：依赖特定版本的方案在版本升级后标记为 `status: archived`
- 子目录数量建议控制在 10 个以内，避免分类过细

### 3.6 使用频率统计（`skills/stats.yaml`）

**定位**：独立于 skill 内容的使用统计数据，辅助 skill 库的长期维护决策。

**设计决策——为什么用独立文件而非 frontmatter**：

- 统计数据与 skill 内容的变更节奏不同，分离后 skill 文件本身保持稳定
- 如果用 git 管理 skills 库，避免频繁的统计更新产生大量噪音 commit
- 单一文件便于全局查看和排序

**格式**：

```yaml
deepspeed-stage3-ckpt:
  use_count: 5
  last_used: 2026-02-28

nccl-timeout:
  use_count: 2
  last_used: 2026-02-15
```

**更新机制**：

- **触发时机**：agent 每次读取一个 approved skill 后，更新对应条目的 `use_count`（+1）和 `last_used`（当天日期）
- **Best-effort 原则**：这是尽力而为的统计，不是强制要求。如果当前 agent 环境不支持文件写入（如 Cursor），直接跳过，不报错、不中断工作流
- **去重**：同一次对话中多次引用同一个 skill，只计数一次（如果 agent 能做到的话，不强制）

**统计数据的应用场景**：

- **审核辅助**：在 `skill-review.md` 的审核流程中，呈现每个 approved skill 的使用频率，帮助判断是否需要归档低频 skill
- **库维护**：定期查看 stats.yaml，识别长期零引用的 skill 进行清理或归档
- **合并决策**：高频 skill 值得投入精力持续维护和完善；低频 skill 可考虑合并或精简

**注意事项**：

- 统计数据是近似值，不追求精确，不应作为唯一决策依据
- agent 不应将"更新统计"视为高优先级任务，主任务永远优先

---

## 4. 跨工具兼容与适配

### 4.1 核心思路

三个工具（Claude Code、Codex、Kimi Code）的 VSCode 插件均与其 CLI 版本共享同一引擎和配置系统，都能**读写本地文件系统**。因此适配策略为**引用指向**而非内容同步——只需在各工具的配置文件里写一句引用，指向 `~/.agent-memory/`，无需复制内容。

### 4.2 各工具的配置体系与适配方式

#### Claude Code（VSCode 插件）

**配置层级**（按优先级从低到高）：

- 全局：`~/.claude/CLAUDE.md` — 对所有项目生效
- 项目级：项目根目录 `CLAUDE.md` — 仅对当前项目生效
- 本地（不入 git）：项目根目录 `CLAUDE.local.md`
- 模块化规则：`.claude/rules/*.md` — 支持按文件 glob 匹配
- Auto memory：`~/.claude/projects/<project>/memory/MEMORY.md` — agent 自己写入的笔记

**适配方式**：在全局 `~/.claude/CLAUDE.md` 中写引用：

```markdown
# 全局行为约束
请读取并遵循 ~/.agent-memory/persona.md 中的所有规则。

# Skills 系统
遇到技术问题时，查阅 ~/.agent-memory/skills/index.yaml，按需读取相关 skill。
详细的 skill 生成和审核流程见 ~/.agent-memory/workflows/ 目录。
```

**能力**：可读写文件系统、可执行命令，完整支持本系统的所有功能（包括 skill 生成、审核、统计更新）。

**与 Auto Memory 的关系**：Claude Code 自带的 auto memory 是它独有的机制，agent 会自动在 `~/.claude/projects/<project>/memory/` 下记录项目模式和发现。这与我们的 skills 系统是**互补关系**——auto memory 是 Claude Code 专属的、自动的、项目级的；我们的 skills 是跨工具的、人工审核的、全局的。两者不冲突，可以并存。

#### Codex

Codex 分为 CLI 和 VSCode 插件两种使用方式，配置读取行为不同：

**Codex CLI**：
- 全局：`~/.codex/AGENTS.md`（或 `AGENTS.override.md` 临时覆盖）
- 项目级：从项目根目录到当前工作目录，逐级查找 `AGENTS.md`

**Codex VSCode 插件**：
- 只读取项目根目录下的 `AGENTS.md`
- 不读取全局 `~/.codex/AGENTS.md`

**适配方式**：

| 使用方式     | 适配方法                                           |
| ------------ | -------------------------------------------------- |
| Codex CLI    | 在全局 `~/.codex/AGENTS.md` 中写引用（一次配置）   |
| VSCode 插件  | 在每个项目根目录的 `AGENTS.md` 中写引用（逐项目）   |

引用内容：

```markdown
# 全局行为约束
请读取并遵循 ~/.agent-memory/persona.md 中的所有规则。

# Skills 系统
遇到技术问题时，查阅 ~/.agent-memory/skills/index.yaml，按需读取相关 skill。
详细的 skill 生成和审核流程见 ~/.agent-memory/workflows/ 目录。
```

**能力**：可读写文件系统、可执行命令，完整支持。

#### Kimi Code（VSCode 插件）

**配置体系**：基于 Kimi CLI 封装，同样支持 `AGENTS.md`。

**适配方式**：在项目根目录的 `AGENTS.md` 中手动添加引用（内容与上述相同）。不建议使用 `/init` 命令，因为它会生成项目介绍内容，引入噪声。

**能力**：可通过工具读写文件，支持本系统的核心功能。

### 4.3 适配脚本

由于三个工具都采用**引用指向**策略，适配脚本的职责从"内容同步"简化为"初始化引用文件"。只需运行一次，后续 persona.md 的修改自动生效，无需重新同步。

`adapters/` 目录下提供一个统一的初始化脚本：

```bash
# adapters/init-all.sh
#!/bin/bash
# 在各工具的全局配置中写入指向 ~/.agent-memory/ 的引用
# 只需运行一次，后续修改 persona.md 自动生效

REFERENCE_CONTENT='# Agent Memory System
请读取并遵循 ~/.agent-memory/persona.md 中的所有规则。
遇到技术问题时，查阅 ~/.agent-memory/skills/index.yaml，按需读取相关 skill。
详细的 skill 生成和审核流程见 ~/.agent-memory/workflows/ 目录。'

# Claude Code
mkdir -p ~/.claude
echo "$REFERENCE_CONTENT" > ~/.claude/CLAUDE.md
echo "✅ Claude Code: ~/.claude/CLAUDE.md"

# Codex
mkdir -p ~/.codex
echo "$REFERENCE_CONTENT" > ~/.codex/AGENTS.md
echo "✅ Codex: ~/.codex/AGENTS.md"

echo ""
echo "Kimi Code: 请在项目根目录的 AGENTS.md 中添加上述引用内容"
echo "（或使用 /init 生成后手动追加）"
```

**注意**：如果你已有自定义的 `~/.claude/CLAUDE.md` 或 `~/.codex/AGENTS.md`，脚本会覆盖原内容。首次运行前请检查是否需要合并已有配置。后续可根据实际需要在引用内容基础上追加工具特定的规则。

---

## 5. 自动化与人工审核的边界

### 5.1 什么可以自动化

| 环节                           | 自动化程度     | 说明                                                      |
| ------------------------------ | -------------- | --------------------------------------------------------- |
| Skill 草稿生成                 | ✅ 全自动      | Agent 检测到触发条件后自动生成                            |
| 草稿存入 drafts/               | ✅ 全自动      | 直接写入文件                                              |
| 预处理检查（去重、质量、分类） | ✅ 全自动      | 审核时 agent 自动执行                                     |
| index.yaml 更新                | ✅ 全自动      | 审核通过后自动更新                                        |
| 使用频率统计                   | ⚡ Best-effort | Agent 读取 skill 后尝试更新 stats.yaml，失败则跳过        |
| 同步到各工具配置               | ✅ 一次性      | 运行 init-all.sh 初始化引用，后续修改 persona.md 自动生效 |

### 5.2 什么需要人工参与

| 环节                                | 原因                           |
| ----------------------------------- | ------------------------------ |
| 决定 skill 是否值得保留             | 很多问题是一次性的，不值得记录 |
| 判断拆分/合并粒度                   | 一次 debug 可能涉及多个知识点  |
| 最终审核确认（通过/修改/丢弃/合并） | 保证 approved 库的质量         |
| Persona 更新                        | 行为偏好的变化需要人主动决定   |

### 5.3 设计哲学

**drafts/ 是 agent 的工作区，approved/ 是人的决策区。** Agent 可以自由向 drafts 写入，但从 drafts 到 approved 的迁移必须经过人的确认。这保证了：

- 不会丢失潜在有价值的经验（自动捕获）
- 不会让低质量内容污染 agent 的知识库（人工把关）

---

## 6. 未来扩展方向

以下是当前设计暂不实现但预留了扩展空间的方向：

- **Embedding 检索**：当 approved skills 超过 30-50 条时，可引入本地向量数据库（如 ChromaDB）做语义检索，通过 MCP server 暴露搜索接口
- **跨项目 skill 共享**：不同项目间的通用 skill 可以通过符号链接或 git submodule 共享
- **多人协作**：将 skills 库托管在 git 仓库，支持团队级的经验共享和 code review 式的 skill 审核

---

## 7. 快速开始

### 第一步：初始化目录结构

运行初始化脚本，创建完整目录和模板文件。

### 第二步：编辑 persona.md

根据个人偏好填充行为约束和编码偏好。

### 第三步：初始化工具配置

运行 `adapters/init-all.sh`，在 Claude Code、Codex 的全局配置中写入指向 `~/.agent-memory/` 的引用。只需运行一次，后续修改 persona.md 自动生效。

### 第四步：日常使用

正常与 agent 对话。当 agent 检测到非平凡问题解决后，会自动在 drafts/ 中生成 skill 草稿。

### 第五步：定期审核

说"review skills"触发审核流程，agent 协助你高效审核并将合格的 skill 迁移到 approved/。
