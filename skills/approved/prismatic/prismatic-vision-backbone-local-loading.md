---
title: "Prismatic vision backbone 默认从 timm/HF 加载，离线时需要改成本地权重"
tags: [prismatic, timm, vision-backbone, dinov2, siglip, offline, local-loading]
created: 2026-03-06
context: "加载原生 Prismatic VLM checkpoint 时报错找不到 timm 模型"
status: approved
related: [prismatic-native-checkpoint-loading]
---

### 问题

离线或受限网络环境下加载原生 Prismatic checkpoint (`prism-dinosiglip-224px+7b`) 时，vision backbone 初始化失败，报错类似：
```
LocalEntryNotFoundError: timm/vit_large_patch14_reg4_dinov2.lvd142m
```

### 根因

在上游默认实现里，`prismatic.load()` 会先读取 checkpoint 中保存的模型权重，再单独 materialize vision backbone。对 `prism-dinosiglip-224px+7b` 这类模型，`DinoSigLIPViTBackbone` 默认使用如下 backbone id：

- DINOv2: `vit_large_patch14_reg4_dinov2.lvd142m`
- SigLIP: `vit_so400m_patch14_siglip_224`

随后直接调用：

```python
timm.create_model(backbone_id, pretrained=True, num_classes=0, img_size=...)
```

这意味着默认行为依赖 timm / HuggingFace 的本地 cache；cache miss 时会尝试联网拉取预训练权重。离线环境下失败的不是 Prismatic checkpoint 本身，而是 vision backbone 的预训练权重解析与下载。

补充一点：常见的 Prismatic finetune checkpoint 通常只包含 `projector` 和 `llm_backbone`，因为默认保存的是 `trainable_module_keys`。但这不是绝对规则；如果走 `full-finetune` 或显式保存 `all_module_keys`，`vision_backbone` 也可能被存进 checkpoint。

### 解决方案

本地运行有两种稳定方案。

#### 方案 1：先预热本地 cache

如果不想改代码，先在能联网的同一环境里成功跑一次 `prismatic.load(...)`，让 timm / HF 把 vision backbone 权重缓存到本地；后续离线运行可以直接复用这份 cache。

#### 方案 2：把 `dinosiglip_vit.py` 改为显式读取本地权重文件

如果运行环境长期离线，或者希望完全避免隐式联网，可以把 `DinoSigLIPViTBackbone` 的初始化改成显式本地加载。推荐做法是保留默认远端行为，同时支持通过本地文件覆盖：

```python
import os

dino_file = os.environ.get("PRISMATIC_DINO_WEIGHTS")
siglip_file = os.environ.get("PRISMATIC_SIGLIP_WEIGHTS")

dino_kwargs = dict(num_classes=0, img_size=self.default_image_size)
siglip_kwargs = dict(num_classes=0, img_size=self.default_image_size)

if dino_file:
    dino_kwargs.update(pretrained=True, pretrained_cfg_overlay=dict(file=dino_file))
else:
    dino_kwargs.update(pretrained=True)

if siglip_file:
    siglip_kwargs.update(pretrained=True, pretrained_cfg_overlay=dict(file=siglip_file))
else:
    siglip_kwargs.update(pretrained=True)

self.dino_featurizer = timm.create_model(self.dino_timm_path_or_url, **dino_kwargs)
self.siglip_featurizer = timm.create_model(self.siglip_timm_path_or_url, **siglip_kwargs)
```

运行前设置本地权重路径：

```bash
export PRISMATIC_DINO_WEIGHTS=/path/to/vit_large_patch14_reg4_dinov2.lvd142m/model.safetensors
export PRISMATIC_SIGLIP_WEIGHTS=/path/to/ViT-SO400M-14-SigLIP/open_clip_pytorch_model.bin
```

### 踩坑点

- 这里说的是 **vision backbone 预训练权重** 的加载机制，不是 `prismatic.load()` 读取的主 checkpoint
- 当前环境可能已经打过本地 patch；这篇记录的是上游默认加载逻辑和可维护的本地离线改法
- 如果你直接改 site-packages，记得这是环境级 patch；升级环境或重建 conda env 后可能丢失
- 如果只是偶尔离线运行，优先考虑预热本地 cache；如果长期本地跑，再考虑改成显式本地加载
- **不要使用 `checkpoint_path` 参数**：
```python
# ❌ 错误 - 会导致 pos_embed shape mismatch
timm.create_model(model_name, checkpoint_path="/path/to/model.safetensors", ...)

# ✅ 正确 - 会自动处理位置编码插值
timm.create_model(model_name, pretrained=True, pretrained_cfg_overlay=dict(file="/path/to/model.safetensors"), ...)
```

原因：
- DINOv2 预训练分辨率是 518px（37x37 patches）
- Prismatic 224px 配置需要 16x16 patches
- `pretrained_cfg_overlay` 会走 timm 的预训练加载逻辑，能处理位置编码插值
- `checkpoint_path` 更像直接灌 state_dict，容易在分辨率不一致时触发 `pos_embed` shape mismatch
