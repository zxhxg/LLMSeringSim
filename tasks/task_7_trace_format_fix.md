# Task 7：Trace 格式与伪层命名修复

## 任务目标

修复 HBF 预取伪层在 trace 文本中挤压列宽、导致 Chakra 解析失败的问题。

## 修改文件

- `inference_serving/utils.py`
- `inference_serving/trace_generator.py`

## 修改模块

- trace 文本格式化
- HBF 伪层命名

## 修改函数

- `header`
- `formatter`
- `_append_hbf_prefetch_rows`

## 实现逻辑

- 将 trace 文本中 `Layername` 的列宽从 `30` 扩大到 `48`，为长层名保留更稳定的字段边界。
- 将 HBF 伪层命名缩短为：
  - `hbf_pred_b{idx}`
  - `hbf_pf_attn_b{idx}`
  - `hbf_pf_ffn_b{idx}`
- 保持 `misc` 字段继续标记为 `HBF_PREDICT` / `HBF_PREFETCH`，不改变语义。

## 影响范围

- 影响 trace 文本输出格式。
- 不改变 HBF 时间模型、传输量模型和依赖图语义。

## 验证方式

- 本地 Python 语法检查通过。
- 新生成 trace 中，HBF 伪层名不会再溢出到 `comp_time` 列。
