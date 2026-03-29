# HBF 权重分层与预取设计

## 1. 目标

本设计为 LLMServingSim 引入一套显式的 HBF（High Bandwidth Flash）权重分层存储与逐层预取模拟机制，满足以下目标：

- 支持新的 HBF 内存层，显式建模容量、带宽与时延。
- 将权重路径统一为 `HBF -> HBM -> compute`。
- 对 dense Transformer 的 Attention 与 FFN 权重分别建模。
- 支持 `ffn_ratio` 控制 FFN 稀疏加载比例。
- 支持执行 layer `i` 时预取 layer `i+1` 权重，并显式计算 stall。
- 保持旧配置在未启用 HBF 时行为不变。

## 2. 设计范围

- 本轮只覆盖 dense Transformer。
- 若模型配置中包含 `num_local_experts` 且实例启用 `hbf_prefetch.enabled=true`，系统直接报错。
- Prefix cache、PIM、CXL 旧路径保持兼容，但 HBF 指标只在 HBF 模式下输出。

## 3. 参数与放置策略

### 3.1 新增集群参数

顶层新增 `hbf_mem`：

- `mem_size`：HBF 容量，单位 GB
- `mem_bw`：HBF 带宽，单位 GB/s
- `mem_latency`：HBF 访问时延，单位 ns
- `num_devices`：HBF 设备数量

### 3.2 新增实例参数

每个实例新增 `hbf_prefetch`：

- `enabled`：是否启用 HBF 预取
- `ffn_ratio`：FFN 稀疏比例，范围 `[0, 1]`
- `predict_base_ns`：基础预测开销
- `predict_attn_ns`：Attention 预测开销
- `predict_ffn_ns`：FFN 预测开销

### 3.3 HBM / HBF 放置规则

HBM（本地 NPU memory）：

- KV cache
- activations
- embedding / lm_head
- LayerNorm / bias / 无权重算子
- 当前层与下一层预取使用的权重 buffer

HBF：

- Attention 权重：`q_proj / k_proj / v_proj / o_proj`
- FFN 权重：`gate_proj / up_proj / down_proj / fc1 / fc2`

## 4. 时间模型

定义：

- `T_compute`：当前层真实计算时间
- `T_predict`：下一层权重预取预测时间
- `T_transfer`：下一层权重从 HBF 传入 HBM buffer 的时间
- `T_prefetch = T_predict + T_transfer`

规则：

```text
if T_prefetch <= T_compute:
    stall = 0
else:
    stall = T_prefetch - T_compute
```

其中：

- Attention：`transfer_size = full_size`
- FFN：`transfer_size = full_size * ffn_ratio`

## 5. 模块改造

### 5.1 Python 层

- `inference_serving/config_builder.py`
  - 解析 `hbf_mem`
  - 校验 `hbf_prefetch`
  - 接受 `hbf[:id]`
- `inference_serving/memory_model.py`
  - 拆分 HBM 常驻权重、HBF 常驻权重、HBM 权重 buffer
  - 提供 dense 层分类与预取传输量计算
- `inference_serving/request.py`
  - 为 `Batch` 新增 HBF 统计字段
- `inference_serving/scheduler.py`
  - 在实例创建时接入 HBF 配置
- `inference_serving/trace_generator.py`
  - 生成 `hbf_predict`
  - 生成 `hbf_prefetch_attn`
  - 生成 `hbf_prefetch_ffn`
  - 为真实计算层注入 HBF 统计
- `main.py`
  - 汇总并打印 latency / stall / transfer bytes

### 5.2 Chakra 转换层

- `astra-sim/extern/graph_frontend/chakra/src/converter/llm_converter.py`
  - 支持 `HBF_MEMORY`
  - 为 `hbf_predict` 构建计算节点
  - 为 `hbf_prefetch_*` 构建 HBF memory load 节点
  - 将 `compute(i+1)` 同时依赖前一真实层与对应 prefetch 节点

### 5.3 ASTRA-Sim 内存层

- `astra-sim/astra-sim/system/AstraMemoryAPI.hh`
  - 新增 `HBF_MEMORY`
- `astra-sim/astra-sim/workload/Workload.cc`
  - 新增 HBF 路由分支
- `astra-sim/astra-sim/system/Sys.hh`
  - 新增 `hbf_mem` 成员
- `astra-sim/astra-sim/system/Sys.cc`
  - 绑定 HBF memory API
- `astra-sim/extern/memory_backend/analytical/AnalyticalMemory.*`
  - 解析 `HBF_MEMORY`
- `astra-sim/astra-sim/network_frontend/...`
  - analytical / ns3 frontends 装配 `hbf_mem`

## 6. 指标

新增以下统计项：

- `hbf_attn_transfer_bytes`
- `hbf_ffn_transfer_bytes`
- `hbf_total_transfer_bytes`
- `hbf_predict_ns`
- `hbf_transfer_ns`
- `hbf_stall_ns`
- `hbf_prefetch_hit_layers`
- `hbf_prefetch_stall_layers`

## 7. 风险分析

### 7.1 依赖图风险

现有预取依赖不在 trace 文本层，而在 Chakra `llm_converter.py` 中构建。若只修改 trace_generator，会导致 ET 图无法体现 prefetch 与 compute 的重叠关系。

### 7.2 内存类型扩展风险

HBF 不是 CXL 的别名，需要同步修改 Python placement、Chakra memory type 解析和 ASTRA-Sim memory routing，任一处遗漏都会导致 trace 可生成但运行失败。

### 7.3 容量模型风险

为支持执行当前层时预取下一层，本实现将 HBM buffer 视为可容纳正在计算层与已预取下一层的双缓冲上界。若后续需要更严格的 buffer 生命周期，可进一步细化。

### 7.4 MoE 风险

MoE expert 路径与 dense FFN 的权重流不同，本轮不隐式兼容，统一 fail-fast，避免生成错误的 HBF 指标。

## 8. 回滚策略

- 未配置 `hbf_mem` 或 `hbf_prefetch.enabled=false` 时，不进入 HBF 逻辑。
- 若 HBF 路径异常，可通过关闭实例级 `hbf_prefetch.enabled` 回退到旧行为。
