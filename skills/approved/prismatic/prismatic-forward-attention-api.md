---
title: "PrismaticVLM 提取 attention 不能用 HF 风格 API"
tags: [prismatic, attention, forward, api, huggingface]
created: 2026-03-06
context: "在 vla_vision_extract.ipynb 中提取 Prismatic 模型的注意力图"
status: approved
related: [prismatic-native-checkpoint-loading, openvla-prismatic-image-token-position]
---

### 问题

从 `prismatic.load()` 加载的 `PrismaticVLM` 对象提取 attention 时，使用 HuggingFace 风格 API 会失败：

```python
# 错误用法
inputs = vlm.processor(prompt_text, image, return_tensors="pt")  # AttributeError
outputs = vlm.model(**inputs, output_attentions=True)  # AttributeError
```

### 根因

`PrismaticVLM` 不是 HuggingFace 模型，没有 `processor` 和 `model` 属性。它暴露的是原生 API：
- `vlm.vision_backbone.image_transform` - 图像预处理
- `vlm.llm_backbone.tokenizer` - 文本 tokenizer
- `vlm.forward()` - 前向传播（支持 `output_attentions=True`）

### 解决方案

使用 Prismatic 原生 API：

```python
from prismatic import load

vlm = load("/path/to/prism-dinosiglip-224px+7b")
vlm.to("cuda:0", dtype=torch.bfloat16)

# 获取图像预处理、tokenizer 和数据类型
image_transform = vlm.vision_backbone.image_transform
tokenizer = vlm.llm_backbone.tokenizer
dtype = vlm.vision_backbone.half_precision_dtype  # torch.bfloat16

# 处理输入 - 注意数据类型转换
pixel_values = image_transform(image)  # 返回 {"dino": tensor, "siglip": tensor}
pixel_values = {k: v.unsqueeze(0).to(vlm.device, dtype=dtype) for k, v in pixel_values.items()}
input_ids = tokenizer(prompt_text, return_tensors="pt").input_ids.to(vlm.device)

# 前向传播，提取 attention
with torch.no_grad():
    outputs = vlm.forward(
        input_ids=input_ids,
        pixel_values=pixel_values,
        output_attentions=True
    )

attentions = outputs.attentions  # tuple of attention tensors
```

### 踩坑点

- `image_transform(image)` 返回的是 `Dict[str, torch.Tensor]`，包含 `"dino"` 和 `"siglip"` 两个 key
- **数据类型不匹配**：`pixel_values` 需要转换为模型的半精度类型（bfloat16），否则会报错 `Input type (float) and bias type (c10::BFloat16) should be the same`
- `input_ids` 和 `pixel_values` 需要手动移到正确的设备上（`vlm.device`）
- 图像 token 位置固定在 BOS 之后，详见 `openvla-prismatic-image-token-position` skill
