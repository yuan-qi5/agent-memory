---
title: "原生 Prismatic checkpoint 不能直接用 transformers AutoModel 加载"
tags: [prismatic, transformers, automodel, checkpoint, siglip, loading]
created: 2026-03-06
context: "在 openvla 环境中尝试加载 prism-dinosiglip-224px-7b 模型"
status: approved
related: []
---

### 问题

尝试用 `transformers.AutoModelForVision2Seq.from_pretrained(...)` 加载原生 Prismatic checkpoint 时失败，报错类似：

```
ValueError: Unrecognized configuration class ...
```

### 根因

原生 Prismatic checkpoint 不是按 HuggingFace AutoModel 约定组织的推理目录。`prismatic` 包的加载入口会读取本地 `config.json` 和 `checkpoints/latest-checkpoint.pt`，再构造并返回一个 `PrismaticVLM` 对象。

也就是说，这类 checkpoint 的推荐加载方式是 `prismatic.load(...)`，而不是直接交给 `transformers.AutoModel*`。

### 解决方案

安装 `prismatic-vlms` 并使用原生 API：

```bash
pip install prismatic-vlms
```

```python
from prismatic import load

vlm = load("/path/to/prism-dinosiglip-224px+7b")
```

`load()` 返回的是单个 `PrismaticVLM` 对象，不是 `(model, image_processor, tokenizer)` 元组。常见用法是：

```python
prompt_builder = vlm.get_prompt_builder()
prompt_builder.add_turn(role="human", message="Describe the image.")
prompt_text = prompt_builder.get_prompt()

result = vlm.generate(image, prompt_text)
```

### 踩坑点

- 这个结论针对原生 Prismatic checkpoint，不要泛化到所有 OpenVLA 或 HF-compatible 模型
- `load()` 依赖目录中的 `config.json` 和 `checkpoints/latest-checkpoint.pt`
- `PrismaticVLM` 暴露的是 `get_prompt_builder()`、`generate()` 等接口，而不是 HuggingFace `processor + model + tokenizer` 三件套
- 模型名里常见的是 `prism-dinosiglip-224px+7b`，`224px` 和 `7b` 之间是 `+`
