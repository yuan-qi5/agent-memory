#!/bin/bash
# adapters/init-all.sh
# 在各 coding agent 的全局配置中写入指向 ~/.agent-memory/ 的引用
# 只需运行一次，后续修改 persona.md 等文件自动生效，无需重新运行
#
# 注意：如果你已有自定义的配置文件，脚本会提示你选择覆盖或跳过
# 建议首次运行前检查是否需要合并已有配置

set -euo pipefail

AGENT_MEMORY_DIR="$HOME/.agent-memory"

REFERENCE_CONTENT='# Agent Memory System
# 详见 https://github.com/<your-repo>/agent-memory-system-design.md

请读取并遵循 ~/.agent-memory/persona.md 中的所有规则。

遇到技术问题时，查阅 ~/.agent-memory/skills/index.yaml，按需读取相关 skill。
详细的 skill 生成和审核流程见 ~/.agent-memory/workflows/ 目录。'

# 检查 agent-memory 目录是否存在
if [ ! -d "$AGENT_MEMORY_DIR" ]; then
    echo "❌ 错误：$AGENT_MEMORY_DIR 目录不存在"
    echo "请先创建目录结构并放置 persona.md 等文件"
    exit 1
fi

# 写入配置文件的通用函数
# 参数：$1 = 目标文件路径，$2 = 工具名称
write_config() {
    local target_file="$1"
    local tool_name="$2"
    local target_dir
    target_dir=$(dirname "$target_file")

    # 创建目录（如果不存在）
    mkdir -p "$target_dir"

    # 如果文件已存在且非空，提示用户
    if [ -f "$target_file" ] && [ -s "$target_file" ]; then
        echo ""
        echo "⚠️  $tool_name: $target_file 已存在且非空"
        echo "   现有内容的前 3 行："
        head -3 "$target_file" | sed 's/^/   > /'
        echo ""
        read -rp "   覆盖？(y/N) " choice
        case "$choice" in
            y|Y)
                echo "$REFERENCE_CONTENT" > "$target_file"
                echo "✅ $tool_name: 已覆盖 $target_file"
                ;;
            *)
                echo "⏭️  $tool_name: 已跳过"
                ;;
        esac
    else
        echo "$REFERENCE_CONTENT" > "$target_file"
        echo "✅ $tool_name: 已写入 $target_file"
    fi
}

echo "🔧 Agent Memory System - 初始化工具配置"
echo "   引用目录：$AGENT_MEMORY_DIR"
echo ""

# Claude Code
write_config "$HOME/.claude/CLAUDE.md" "Claude Code"

# Codex CLI（VSCode 插件不读取全局配置，需要在项目根目录手动添加）
write_config "$HOME/.codex/AGENTS.md" "Codex CLI"

echo ""
echo "────────────────────────────────────"
echo ""
echo "📌 Codex VSCode 插件："
echo "   不读取全局 ~/.codex/AGENTS.md，需要在每个项目根目录的 AGENTS.md 中手动添加引用"
echo ""
echo "📌 Kimi Code："
echo "   请在项目根目录的 AGENTS.md 中手动添加上述引用内容"
echo ""
echo "📌 其他工具（Cursor 等）："
echo "   如果工具支持全局指令文件，将上述引用内容添加到对应的配置文件中"
echo "   如果工具支持 AGENTS.md 标准，可以创建符号链接："
echo "   ln -s ~/.codex/AGENTS.md <工具配置目录>/AGENTS.md"
echo ""
echo "完成。后续修改 ~/.agent-memory/ 下的文件会自动生效，无需重新运行此脚本。"