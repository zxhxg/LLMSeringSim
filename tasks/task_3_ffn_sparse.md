# Task 3：FFN 稀疏传输建模

## 任务目标

实现 `ffn_ratio` 驱动的 FFN 稀疏加载模型，并与 Attention 全量加载区分开来。

## 修改文件

- `inference_serving/config_builder.py`
- `inference_serving/memory_model.py`
- `inference_serving/trace_generator.py`

## 修改模块

- HBF 参数校验
- dense 层分类
- 预取传输量计算

## 修改函数

- `build_cluster_config`
- `get_dense_block_weight_summary`
- `_append_hbf_prefetch_rows`

## 实现逻辑

- 在实例级 `hbf_prefetch` 中新增并校验 `ffn_ratio`，要求取值在 `[0, 1]`。
- dense Transformer 中：
  - Attention 权重传输量固定为 `full_size`。
  - FFN 权重传输量固定为 `full_size * ffn_ratio`。
- 预取统计中分别累计 Attention 与 FFN 的字节量，并输出总传输量。

## 影响范围

- 影响 HBF 模式下的传输字节量、传输时间和最终 stall。
- 不影响未启用 HBF 的 trace 生成路径。

## 验证方式

- `ffn_ratio=1.0` 时 FFN 传输量等于全量权重。
- `ffn_ratio=0.5` 时 FFN 传输量约为全量的一半。
- `ffn_ratio` 越界时配置阶段直接报错。
