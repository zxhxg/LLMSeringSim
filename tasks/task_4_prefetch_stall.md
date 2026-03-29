# Task 4：Prefetch 依赖图与 Stall 模型

## 任务目标

在 trace 与 Chakra ET 图中引入 `hbf_predict`、`hbf_prefetch_attn`、`hbf_prefetch_ffn`，并实现严格的 stall 计算。

## 修改文件

- `inference_serving/trace_generator.py`
- `inference_serving/request.py`
- `astra-sim/extern/graph_frontend/chakra/src/converter/llm_converter.py`

## 修改模块

- trace 合成
- batch 元数据
- Chakra 依赖关系构图

## 修改函数

- `generate_trace`
- `_synthesize_trace`
- `_append_hbf_prefetch_rows`
- `LLMConverter.get_mem_type`
- `LLMConverter.convert_common`
- `LLMConverter.convert_prefill`

## 实现逻辑

- 在 layer `i` 的 trace 尾部插入面向 layer `i+1` 的三个伪层：
  - `hbf_predict_block_{i+1}`
  - `hbf_prefetch_attn_block_{i+1}`
  - `hbf_prefetch_ffn_block_{i+1}`
- `convert_common` / `convert_prefill` 中：
  - `predict(i+1)` 依赖于当前 block 入口的父节点集合。
  - `prefetch(i+1)` 依赖 `predict(i+1)`。
  - `compute(i+1)` 的 block 入口层额外依赖对应的 prefetch load 节点。
  - 对已经预取到 HBM buffer 的 dense 权重层，跳过重复的逐层 weight load。
- stall 严格按公式实现：
  - `T_prefetch = T_predict + T_transfer`
  - `stall = max(0, T_prefetch - T_compute)`

## 影响范围

- 影响 HBF 模式下 ET 图的节点类型与数据依赖。
- 影响 batch 级 stall 和 prefetch hit 统计。

## 验证方式

- trace 文本中必须出现 `hbf_predict_*` 与 `hbf_prefetch_*`。
- Python 语法检查通过，确保 trace / converter 代码无语法错误。
- 逻辑上 `compute(i+1)` 既保留原前驱，也等待对应 prefetch 完成。
