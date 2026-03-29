# Task 8：Chakra 解析器容错增强

## 任务目标

为 Chakra 的 LLM trace 解析增加显式列数校验，并兼容新的 HBF 伪层缩写命名。

## 修改文件

- `astra-sim/extern/graph_frontend/chakra/src/converter/llm_converter.py`

## 修改模块

- trace 行解析
- HBF 伪层识别

## 修改函数

- `Layer.__init__`
- `LLMConverter.is_hbf_predict_layer`
- `LLMConverter.is_hbf_prefetch_layer`

## 实现逻辑

- 在 `Layer.__init__` 中增加最小列数检查，若字段数少于 11 列，则直接抛出解析错误。
- 保持原有 HBF 伪层前缀兼容的同时，新增对缩写前缀的识别：
  - `hbf_pred_b`
  - `hbf_pf_attn_b`
  - `hbf_pf_ffn_b`

## 影响范围

- 影响 Chakra 对 trace 文本的错误发现方式。
- 不改变 ET 图生成的核心依赖逻辑。

## 验证方式

- 本地 Python 语法检查通过。
- 新旧 HBF 前缀都能被 converter 正确识别。
