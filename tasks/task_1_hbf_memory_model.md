# Task 1：HBF 内存层建模

## 任务目标

为 LLMServingSim 新增独立的 HBF 内存层，使其在 Python 配置、Chakra ET 和 ASTRA-Sim 后端中都能作为 `HBF_MEMORY` 被显式识别和路由。

## 修改文件

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

## 修改模块

- 集群配置解析
- ASTRA-Sim 内存类型枚举
- 系统层内存句柄绑定
- workload 内存访问路由
- analytical / ns3 memory frontend 装配

## 修改函数

- `build_cluster_config`
- `_mem_str`
- `Workload::issue_mem`
- `AnalyticalMemory::AnalyticalMemory`
- `Sys::Sys`

## 实现逻辑

- 在集群配置顶层新增 `hbf_mem`，解析容量、带宽、时延和设备数。
- 在 placement 中接受 `hbf[:id]`，并允许写入 memory configuration。
- 在 Chakra / ASTRA-Sim 内存类型枚举中新增 `HBF_MEMORY`。
- 在 `Sys` 中新增 `hbf_mem` 句柄，并在初始化时根据 memory level 自动绑定。
- 在 `Workload::issue_mem` 中增加 `HBF_MEMORY` 分支，使 HBF 请求进入独立 memory backend。
- 在 analytical 和 ns3 前端中增加 `hbf_mem` 的 JSON 注入逻辑，确保 memory level 能被构造出来。

## 影响范围

- 影响新的 HBF 配置路径。
- 不影响未启用 `hbf_mem` 的旧配置。
- 为后续 FFN 稀疏、prefetch 和 stall 建模提供底层内存入口。

## 验证方式

- 使用 Python 语法检查确认配置解析侧无语法错误。
- 通过代码检查确认 `HBF_MEMORY` 已在 Chakra、Workload、Sys 和 AnalyticalMemory 中贯通。
- 未启用 HBF 时，原 `LOCAL/REMOTE/CXL/STORAGE` 路径不变。
