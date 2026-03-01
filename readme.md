# Agent Memory System

为 AI coding agent 构建的**跨工具、可迁移、可自进化**的记忆系统。

## 这是什么

使用 Claude Code、Codex、Kimi Code、Cursor 等 coding agent 时，你可能遇到过这些问题：

* **行为不一致** ：每次都要重复告诉 agent"改之前先跟我说"、"不要加没必要的 try-except"
* **经验无法沉淀** ：花了半天解决的 DeepSpeed checkpoint 问题，下次遇到又得从头排查
* **工具锁定** ：在 Claude Code 里攒的经验，换到 Codex 就丢了

Agent Memory System 通过纯文本文件（Markdown + YAML）解决这些问题：

* **Persona** ：定义 agent 的行为约束和编码偏好，每次对话自动加载
* **Skills** ：将解决复杂问题的经验结构化记录，agent 遇到类似问题时自动检索复用
* 所有文件工具无关，一处维护，Claude Code / Codex / Kimi Code 等多处生效

## 目录结构

```
~/.agent-memory/
├── persona.md                    # 行为约束（每次对话加载）
│
├── workflows/                    # 流程定义（按需加载）
│   ├── skill-generation.md       # skill 自动生成的触发条件和模板
│   └── skill-review.md          # skill 审核流程
│
├── skills/                       # 经验库
│   ├── index.yaml               # 轻量索引（agent 通过此文件检索 skill）
│   ├── stats.yaml               # 使用频率统计
│   ├── approved/                # ✅ 经过人工审核的 skill
│   │   ├── deepspeed/
│   │   │   ├── _summary.md
│   │   │   └── stage3-checkpoint.md
│   │   ├── pytorch/
│   │   └── general/             # 暂时无法归类的 skill
│   └── drafts/                  # 📝 agent 自动生成的草稿，等待审核
│
├── adapters/
│   └── init-all.sh              # 一键初始化各工具配置
│
└── scripts/
    └── generate-index.sh        # 从 approved/ 自动生成 index.yaml
```

## 快速开始

### 1. 克隆并放置文件

```bash
git clone <repo-url> /tmp/agent-memory-setup
mkdir -p ~/.agent-memory
cp -r /tmp/agent-memory-setup/{persona.md,workflows,skills,adapters,scripts} ~/.agent-memory/
chmod +x ~/.agent-memory/adapters/init-all.sh ~/.agent-memory/scripts/generate-index.sh
```

### 2. 编辑 persona.md

打开 `~/.agent-memory/persona.md`，根据你的偏好填充"编码偏好"部分。其他部分（协作规则、代码生成约束等）已预置了通用的最佳实践，可以直接使用或按需调整。

### 3. 初始化工具配置

```bash
~/.agent-memory/adapters/init-all.sh
```

这会在 Claude Code（`~/.claude/CLAUDE.md`）和 Codex（`~/.codex/AGENTS.md`）的全局配置中写入指向 `~/.agent-memory/` 的引用。只需运行一次，后续修改 persona.md 自动生效。

如果你已有自定义配置，脚本会提示你选择覆盖或跳过。

### 4. 开始使用

正常与 agent 对话即可。系统会在后台工作：

* **自动** ：agent 遵循 persona.md 中的行为约束
* **自动** ：遇到技术问题时，agent 查阅 skills/index.yaml 检索相关经验
* **自动** ：解决非平凡问题后，agent 在 drafts/ 中生成 skill 草稿
* **手动** ：你说"review skills"，agent 协助你审核草稿并将合格的迁移到 approved/

## 核心工作流

### Skill 的生命周期

```
解决问题 → agent 自动生成草稿 → 存入 drafts/
                                      ↓
                              用户说 "review skills"
                                      ↓
                        agent 预处理（去重、质量检查、分类）
                                      ↓
                            用户决策：通过 / 修改 / 丢弃 / 合并
                                      ↓
                          迁移到 approved/，更新 index.yaml
                                      ↓
                        未来的 agent 遇到类似问题时自动检索复用
```

### 分层加载策略

系统不会一次性把所有内容塞进 context window：

| 层级 | 内容                     | 加载时机                       |
| ---- | ------------------------ | ------------------------------ |
| L0   | `persona.md`           | 每次对话开始                   |
| L1   | `skills/index.yaml`    | agent 遇到技术问题时           |
| L2   | `skills/approved/*.md` | 从 index 中定位到相关 skill 后 |
| L3   | `workflows/*.md`       | 触发 skill 生成/审核时         |

### 自动化与人工审核的边界

| 环节                           | 谁做       |
| ------------------------------ | ---------- |
| 生成 skill 草稿                | Agent 自动 |
| 预处理检查（去重、质量、分类） | Agent 自动 |
| 决定 skill 是否保留            | 用户决定   |
| 审核通过后的文件操作           | Agent 执行 |
| 更新 persona.md                | 用户决定   |

设计哲学：**drafts/ 是 agent 的工作区，approved/ 是人的决策区。**

## 跨工具兼容

所有 coding agent 的适配方式都是 **引用指向** ——在各工具的全局配置中写一句引用，指向 `~/.agent-memory/`，不复制内容：

| 工具        | 配置文件                 | 适配方式                |
| ----------- | ------------------------ | ----------------------- |
| Claude Code | `~/.claude/CLAUDE.md`  | `init-all.sh`自动写入 |
| Codex CLI   | `~/.codex/AGENTS.md`   | `init-all.sh`自动写入 |
| Codex VSCode| 项目根目录 `AGENTS.md` | 手动添加引用          |
| Kimi Code   | 项目根目录 `AGENTS.md` | 手动添加引用            |
| Cursor      | `.cursorrules`或 rules | 手动添加引用            |

与各工具自带 memory 的关系：Claude Code 的 Auto Memory、Codex 的 Skills 等是各工具专属的机制。本系统与它们是 **互补关系** ——它们是工具专属的、自动的、项目级的；我们是跨工具的、人工审核的、全局的。两者不冲突，可以并存。

## 脚本说明

### `adapters/init-all.sh`

一键在 Claude Code 和 Codex 的全局配置中写入引用。会检测已有配置文件并提示是否覆盖。

### `scripts/generate-index.sh`

扫描 `skills/approved/` 下所有 skill 文件的 frontmatter，自动生成 `skills/index.yaml`。适用于手动编辑 skill 文件后需要同步索引的场景。

```bash
~/.agent-memory/scripts/generate-index.sh
```

## 设计文档

完整的设计决策和技术细节见 [agent-memory-system-design.md](https://claude.ai/chat/agent-memory-system-design.md)。

## 未来扩展

当前设计预留了以下扩展方向：

* **Embedding 检索** ：approved skills 超过 30-50 条时，引入向量数据库做语义检索
* **跨项目共享** ：通过 git submodule 或符号链接在不同项目间共享通用 skill
* **团队协作** ：将 skills 库托管到 git 仓库，支持 code review 式的 skill 审核
