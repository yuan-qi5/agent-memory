#!/bin/bash
# scripts/generate-index.sh
# 从 approved/ 下所有 skill 文件的 frontmatter 自动生成 index.yaml
# 确保 index 与实际文件始终同步
#
# 用法：
#   bash ~/.agent-memory/scripts/generate-index.sh
#
# 依赖：标准 Unix 工具（grep, sed, awk），无需额外安装

set -euo pipefail

AGENT_MEMORY_DIR="$HOME/.agent-memory"
APPROVED_DIR="$AGENT_MEMORY_DIR/skills/approved"
INDEX_FILE="$AGENT_MEMORY_DIR/skills/index.yaml"

# 检查目录是否存在
if [ ! -d "$APPROVED_DIR" ]; then
    echo "❌ 错误：$APPROVED_DIR 目录不存在"
    exit 1
fi

# 临时文件
TMP_FILE=$(mktemp)
trap 'rm -f "$TMP_FILE"' EXIT

# 写入头部
cat > "$TMP_FILE" << 'EOF'
# Approved Skills 索引
# 由 scripts/generate-index.sh 自动生成
# 生成时间见 git log 或文件修改时间

skills:
EOF

# 统计计数
count=0

# 遍历 approved/ 下所有 .md 文件（排除 _summary.md）
while IFS= read -r -d '' file; do
    # 跳过 _summary.md
    basename_file=$(basename "$file")
    if [ "$basename_file" = "_summary.md" ]; then
        continue
    fi

    # 提取 frontmatter（第一个 --- 和第二个 --- 之间的内容）
    frontmatter=$(sed -n '/^---$/,/^---$/p' "$file" | sed '1d;$d')

    if [ -z "$frontmatter" ]; then
        echo "⚠️  跳过（无 frontmatter）：$file"
        continue
    fi

    # 从 frontmatter 提取字段
    title=$(echo "$frontmatter" | grep '^title:' | sed 's/^title: *//; s/^"//; s/"$//')
    tags=$(echo "$frontmatter" | grep '^tags:' | sed 's/^tags: *//')

    if [ -z "$title" ]; then
        echo "⚠️  跳过（无 title）：$file"
        continue
    fi

    # 生成 id：从相对路径推导（如 deepspeed/stage3-checkpoint.md → deepspeed-stage3-checkpoint）
    relative_path="${file#$APPROVED_DIR/}"
    id=$(echo "$relative_path" | sed 's/\.md$//; s/\//-/g')

    # 写入条目
    cat >> "$TMP_FILE" << EOF
  - id: $id
    title: "$title"
    tags: $tags
    path: approved/$relative_path
EOF

    count=$((count + 1))

done < <(find "$APPROVED_DIR" -name '*.md' -type f -print0 | sort -z)

# 替换原文件
mv "$TMP_FILE" "$INDEX_FILE"

echo "✅ 已生成 $INDEX_FILE（共 $count 个 skill）"