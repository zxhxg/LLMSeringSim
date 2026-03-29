# Task 0：HBF 改造任务拆分

## 总体说明

本轮改造按任务拆分执行，所有任务日志使用中文，统一保存在 `tasks/` 目录。

## task_1_hbf_memory_model

- 目标：新增显式 HBF memory tier
- 模块：
  - `inference_serving/config_builder.py`
  - `astra-sim/astra-sim/system/AstraMemoryAPI.hh`
  - `astra-sim/astra-sim/system/Sys.hh`
  - `astra-sim/astra-sim/system/Sys.cc`
  - `astra-sim/astra-sim/workload/Workload.cc`
  - `astra-sim/extern/memory_backend/analytical/AnalyticalMemory.hh`
  - `astra-sim/extern/memory_backend/analytical/AnalyticalMemory.cc`
  - `astra-sim/astra-sim/network_frontend/analytical/congestion_unaware/main.cc`
  - `astra-sim/astra-sim/network_frontend/analytical/congestion_aware/main.cc`
  - `astra-sim/astra-sim/network_frontend/ns3/AstraSimNetwork.cc`

## task_2_weight_tiering

- 目标：拆分 HBM 常驻权重、HBF 常驻权重与 HBM 权重 buffer
- 模块：
  - `inference_serving/memory_model.py`
  - `inference_serving/scheduler.py`
  - `main.py`

## task_3_ffn_sparse

- 目标：实现 dense FFN 稀疏传输比例 `ffn_ratio`
- 模块：
  - `inference_serving/memory_model.py`
  - `inference_serving/trace_generator.py`

## task_4_prefetch_stall

- 目标：实现 `hbf_predict` / `hbf_prefetch_*` 与 stall 依赖图
- 模块：
  - `inference_serving/trace_generator.py`
  - `inference_serving/request.py`
  - `astra-sim/extern/graph_frontend/chakra/src/converter/llm_converter.py`

## task_5_metrics

- 目标：输出 batch/global 级 HBF 指标
- 模块：
  - `inference_serving/request.py`
  - `main.py`
  - `inference_serving/scheduler.py`

## task_6_docs_examples

- 目标：补全文档与样例配置
- 模块：
  - `README.zh-CN.md`
  - `cluster_config/README.zh-CN.md`
  - `cluster_config/single_node_hbf_instance.json`

## task_final_test

- 目标：仅测试与记录，不修改代码
- 模块：
  - `tasks/task_final_test.md`
