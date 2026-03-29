# Task 2：HBM / HBF 权重分层

## 任务目标

重构权重常驻模型，显式区分 HBM 常驻权重、HBF 常驻权重和当前层 HBM weight buffer。

## 修改文件

- `inference_serving/memory_model.py`
- `inference_serving/scheduler.py`
- `main.py`

## 修改模块

- MemoryModel 容量计算
- Scheduler 初始化路径
- 主流程实例参数下发

## 修改函数

- `MemoryModel.__init__`
- `MemoryModel.get_weight`
- `MemoryModel.get_hbf_prefetch_summary`
- `MemoryModel.get_prefetch_predict_ns`
- `MemoryModel.allocate`
- `MemoryModel.free`
- `MemoryModel.is_avail`
- `MemoryModel.need_size`
- `Scheduler.__init__`

## 实现逻辑

- 新增 `Device.HBF`。
- 为 dense 模型定义 HBF Attention/FFN 层集合、HBM 静态权重层集合和无权重层集合。
- HBF 模式下：
  - `embedding / input_layernorm / post_layernorm / final_layernorm / lm_head` 视为 HBM 常驻。
  - `q_proj / k_proj / v_proj / o_proj / gate_proj / up_proj / down_proj` 视为 HBF 常驻。
  - 当前层和下一层预取所需的 weight buffer 计入 HBM。
- `Scheduler` 和 `main.py` 将 `hbf_mem`、`hbf_prefetch` 传入 `MemoryModel`。

## 影响范围

- 影响 HBF 模式下的初始显存占用和容量判断。
- 旧模式仍保持“整模型权重常驻 HBM”的旧行为。

## 验证方式

- 对未启用 HBF 的实例，`get_weight()` 返回行为保持兼容。
- 对启用 HBF 的 dense 模型，`hbf_weight` 与 `weight` 分别映射到 HBF / HBM。
- 对 MoE + HBF 组合执行 fail-fast。
