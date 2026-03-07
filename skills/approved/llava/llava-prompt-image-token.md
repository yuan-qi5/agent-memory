---
title: "LLaVA processor 直接传入纯文本导致找不到 image token"
tags: [llava, multimodal, chat-template, tokenizer, image-token]
created: 2026-03-07
context: "llava_attention_extract.ipynb 中提取注意力时遇到"
status: approved
related: [openvla-prismatic-image-token-position]
---

### 问题

使用 `LlavaProcessor` 处理图像和文本时，直接传入纯问题文本（如 `"What's in the image?"`），导致：

```
ValueError: 32000 is not in list
```

当代码尝试在 `input_ids` 中查找 image token (32000) 时失败。

### 根因

`LlavaProcessor` 不会自动为纯文本添加 `<image>` token。只有当文本中包含 `<image>` 字符串时，tokenizer 才会在 `input_ids` 中插入这个 special token（在当前模型里 token ID 是 32000）。

直接传入 `"What's in the image?"` 这样的纯问题，processor 处理后的 `input_ids` 中没有 32000，导致后续代码找不到图像 token 位置。

需要注意：`576` 指的是视觉 patch 数（24x24），不是 tokenizer 里重复出现的 576 个 `<image>` token。常见注意力提取代码是先找到单个 `<image>` 占位符的位置，再结合模型的图像 patch 数去切片。

### 解决方案

使用 `apply_chat_template` 方法格式化 prompt：

```python
def format_prompt(text, processor):
    messages = [
        {"role": "user", "content": [
            {"type": "image"},
            {"type": "text", "text": text}
        ]}
    ]
    return processor.apply_chat_template(messages, tokenize=False, add_generation_prompt=True)

# 使用
prompt = format_prompt("What's in the image?", processor)
# 结果: "USER: <image>\nWhat's in the image? ASSISTANT:"
```

### 踩坑点

1. **不要手动拼接 prompt 字符串**：虽然 `f"USER: <image>\n{question} ASSISTANT:"` 也能工作，但使用 `apply_chat_template` 更规范，且能自动适配不同模型的对话格式。

2. **processor 参数顺序**：调用 processor 时使用关键字参数 `processor(images=image, text=prompt, ...)` 而非位置参数，避免参数交换的警告。

3. **token 含义不要混淆**：`<image>` 是单个 special token；576 是视觉 patch 数。查找图像位置时找的是 `<image>` 的起始位置，不是 576 个重复 token。

4. **相关模型**：OpenVLA/Prismatic 等 VLA 模型有类似但不同的问题，它们使用 BOS 之后的固定插入位置，而不是 `<image>` token，参见 `openvla-prismatic-image-token-position` skill。
