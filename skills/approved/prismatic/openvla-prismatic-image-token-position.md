---
title: "OpenVLA/Prismatic 中找不到 <image> token，如何确定图像 token 位置"
tags: [openvla, prismatic, tokenizer, input_ids, bos, image-token, attention]
created: 2026-03-05
context: "Vicrop 项目中提取 OpenVLA/Prismatic 模型的注意力图"
status: approved
related: []
---

### 问题

在提取 OpenVLA/Prismatic VLM 的注意力图时，沿用 LLaVA 风格的 `<image>` 占位符定位图像 token 位置会失败：`input_ids` 中找不到 `<image>` token，tokenizer 资产里也没有定义这个 special token。

### 根因

OpenVLA/Prismatic 的多模态拼接方式与 LLaVA 不同：

- **LLaVA**：在文本序列中使用 `<image>` 占位符，再在模型内部替换为图像 embeddings
- **OpenVLA/Prismatic**：processor 只返回文本 `input_ids` 和图像 `pixel_values`，不会向 `input_ids` 注入 `<image>` token；模型前向时将 `projected_patch_embeddings` 固定插入到 BOS token 之后

本地实现可直接验证这一点（`modeling_prismatic.py`）：
```python
# Build Multimodal Embeddings & Attention Mask =>> Prismatic defaults to inserting after <BOS> token (1:)
multimodal_embeddings = torch.cat(
    [input_embeddings[:, :1, :], projected_patch_embeddings, input_embeddings[:, 1:, :]], dim=1
)
```

### 解决方案

对于 OpenVLA/Prismatic，不要在 tokenizer 或 `input_ids` 中查找 `<image>` 占位符。图像 token 起始位置固定为 1，也就是 BOS 之后：

```python
img_start_pos = 1  # 紧跟 BOS token

att_weights = attentions[att_layer][0, :, -1, img_start_pos:img_start_pos+num_img_tokens]
```

### 踩坑点

- tokenizer 中新增的 special token 是 `<PAD>`，不是 `<image>`
- `input_ids` 只表示文本序列；图像 patches 是在前向过程中插入的
- 224px 版本的 OpenVLA/Prismatic 使用 256 个图像 tokens（16x16）
- 序列结构可理解为 `[BOS] + [image patches] + [text tokens]`
