# Task 5：HBF 指标统计与输出

## 任务目标

将 HBF 传输、预测和 stall 指标扩展到 batch 级与全局级，并在标准输出中直接展示。

## 修改文件

- `inference_serving/request.py`
- `inference_serving/trace_generator.py`
- `main.py`

## 修改模块

- Batch 元数据
- trace 返回路径
- 主程序指标汇总与打印

## 修改函数

- `Batch.__init__`
- `generate_trace`
- `main`

## 实现逻辑

- 在 `Batch` 中新增 `hbf_metrics` 字典。
- `trace_generator` 在生成 trace 后把本批次 HBF 指标写回 `Batch`。
- `main.py` 在请求完成时累计以下指标：
  - `attn_transfer_bytes`
  - `ffn_transfer_bytes`
  - `total_transfer_bytes`
  - `predict_ns`
  - `transfer_ns`
  - `stall_ns`
  - `prefetch_hit_layers`
  - `prefetch_stall_layers`
- 当任一实例启用 HBF 时，标准输出新增 `HBF Prefetch Results` 小节。

## 影响范围

- 影响 stdout 汇总信息。
- 不影响 CSV 逐请求输出格式。

## 验证方式

- 未启用 HBF 时，不打印 HBF 汇总。
- 启用 HBF 时，可以在 stdout 中直接看到 `transfer bytes` 与 `stall`。
