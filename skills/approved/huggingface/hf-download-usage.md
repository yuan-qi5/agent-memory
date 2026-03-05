---
title: "hf download 命令下载 HuggingFace 模型"
tags: [huggingface, download, mirror, china]
created: 2026-03-04
context: "下载 HuggingFace 模型到本地"
status: approved
related: []
---

### 问题

需要从 HuggingFace 下载模型到本地，使用命令行工具。

### 根因

`huggingface_hub` v1.0 迁移后，官方 CLI 主入口为 `hf`，下载推荐使用 `hf download`。国内网络环境下可按需配置镜像源加速。

### 解决方案

```bash
# 安装
pip install -U huggingface_hub

# 国内镜像（`hf download` 无 `--endpoint` 参数，常见做法是设置环境变量）
export HF_ENDPOINT=https://hf-mirror.com

# 基本用法
hf download <REPO_ID> --local-dir <保存路径>

# 完整示例
hf download openvla/openvla-7b --local-dir ./models/openvla-7b

# 带认证（私有/gated 模型）
export HF_TOKEN=hf_xxx
hf download meta-llama/Llama-2-7b --local-dir ./llama2

# 只下载特定文件
hf download gpt2 config.json --local-dir ./gpt2

# 过滤文件
hf download <REPO_ID> \
  --include "*.safetensors" "*.json" \
  --exclude "*.bin" "*.pth" \
  --local-dir ./models
```

### 下载子目录（CLI 与 Python）

`hf download` 支持把子目录路径作为参数下载（例如 `art/`）。需要更灵活的过滤时，可用 Python 的 `snapshot_download` + `allow_patterns`。

```bash
# 方式 1：CLI 直接下载子目录
hf download HuggingFaceM4/FineVision art/ --repo-type dataset --local-dir ./finevision

# 方式 2：Python 按模式过滤下载（推荐先设置环境变量，避免 token 出现在命令历史）
export HF_ENDPOINT=https://hf-mirror.com
export HF_TOKEN=hf_xxx
python - << 'PY'
from huggingface_hub import snapshot_download

snapshot_download(
    repo_id="TRI-ML/prismatic-vlms",
    allow_patterns=["prism-dinosiglip+7b/*"],  # 只下载子目录
    local_dir="/path/to/save",
)
PY
```

### 实际可用参数（hf download -h）

| 参数 | 说明 |
|------|------|
| `--local-dir` | 本地保存路径 |
| `--include` | 只下载匹配的文件模式 |
| `--exclude` | 排除匹配的文件模式 |
| `--token` | 认证 token（也可用 `HF_TOKEN` 环境变量）|
| `--type` / `--repo-type` | 类型：model/dataset/space |
| `--revision` | 指定分支或 commit |
| `--cache-dir` | 缓存目录 |
| `--force-download` | 强制重新下载 |
| `--dry-run` | 干运行，预览下载计划但不实际下载 |
| `--quiet` | 静默模式 |
| `--max-workers` | 并行下载线程数，默认 8 |

### 踩坑点

- **`--local-dir-use-symlinks` 已移除**：这是旧参数，新版 `hf download` 不支持，使用会报错 `No such option: --local-dir-use-symlinks`
- **`--endpoint` 不存在**：`hf download` 没有该命令行参数；切换 Hub endpoint 的常见做法是设置 `HF_ENDPOINT` 环境变量
- **`--dry-run` 可用**：支持干运行模式，预览将要下载的文件而不实际下载
- `HF_TOKEN` 环境变量会被自动读取，无需每次传 `--token`
- **自动续传**：`--resume-download` 参数已移除，下载会自动尝试断点续传
