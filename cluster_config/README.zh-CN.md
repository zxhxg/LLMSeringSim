# cluster_config

该目录包含用于定义 LLMServingSim 集群配置的文件，这些文件描述了硬件拓扑、实例布局、内存层级以及互连参数。

可通过 `--cluster-config cluster_config/{name}.json` 将配置文件传递给 `main.py`。

## 配置格式

```json
{
  "num_nodes": 1,
  "link_bw": 112,
  "link_latency": 0,
  "nodes": [
    {
      "num_instances": 1,
      "cpu_mem": {
        "mem_size": 128,
        "mem_bw": 256,
        "mem_latency": 0
      },
      "instances": [
        {
          "model_name": "meta-llama/Llama-3.1-8B",
          "hardware": "A6000",
          "npu_mem": {
            "mem_size": 40,
            "mem_bw": 768,
            "mem_latency": 0
          },
          "npu_num": 1,
          "npu_group": 1,
          "pd_type": null
        }
      ]
    }
  ]
}
```

### 顶层字段

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `num_nodes` | Integer | 集群中的节点数量 |
| `link_bw` | Float | 节点间链路带宽，单位为 GB/s |
| `link_latency` | Float | 节点间链路时延，单位为 ns |

### 每个节点的字段

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `num_instances` | Integer | 当前节点上的实例数量 |
| `cpu_mem.mem_size` | Float | CPU 内存容量，单位为 GB |
| `cpu_mem.mem_bw` | Float | CPU 内存带宽，单位为 GB/s |
| `cpu_mem.mem_latency` | Float | CPU 内存时延，单位为 ns |

### 每个实例的字段

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `model_name` | String | HuggingFace 模型标识符 |
| `hardware` | String | 硬件目标，对应 `llm_profile/perf_models/` 中的 profile |
| `npu_mem.mem_size` | Float | NPU 内存容量，单位为 GB |
| `npu_mem.mem_bw` | Float | NPU 内存带宽，单位为 GB/s |
| `npu_mem.mem_latency` | Float | NPU 内存时延，单位为 ns |
| `npu_num` | Integer | 当前实例中的 NPU 数量 |
| `npu_group` | Integer | 用于 tensor parallelism 的 NPU 分组大小 |
| `pd_type` | String or null | `"prefill"`、`"decode"` 或用于组合模式的 `null` |

### 可选的每实例字段

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `placement` | Object | 针对权重、KV cache 和 experts 的逐层放置规则 |
| `pim_config` | String | 位于 `pim_config/` 中的 PIM 设备 INI 文件路径 |
| `power` | Object | 功耗模型的电源配置 |
| `cxl_mem` | Object | CXL 内存扩展参数（`mem_size`、`mem_bw`、`mem_latency`） |

## 已提供的配置

| 文件 | 说明 |
| --- | --- |
| `single_node_single_instance.json` | 单节点、单实例（默认） |
| `single_node_single_instance_H100.json` | 单节点、运行在 H100 上的单实例 |
| `single_node_multi_instance.json` | 单节点、多实例 |
| `single_node_pd_instance.json` | 带 P/D 解耦的单节点 |
| `single_node_moe_single_instance.json` | 单节点、单个 MoE 实例 |
| `single_node_moe_multi_instance.json` | 单节点、多个 MoE 实例 |
| `single_node_moe_pd_instance.json` | 单节点、带 P/D 解耦的 MoE |
| `single_node_cxl_instance.json` | 带 CXL 内存扩展的单节点 |
| `single_node_pim_instance.json` | 启用 PIM 内存的单节点 |
| `single_node_power_instance.json` | 启用功耗建模的单节点 |
| `single_node_memory_instance.json` | 单节点内存层级配置 |
| `dual_node_multi_instance.json` | 双节点、多实例 |

## HBF 配置

当需要启用 HBF 权重分层与预取时，需要同时配置顶层 `hbf_mem` 和实例级 `hbf_prefetch`。

顶层 `hbf_mem` 字段：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `mem_size` | Float | HBF 容量，单位为 GB |
| `mem_bw` | Float | HBF 带宽，单位为 GB/s |
| `mem_latency` | Float | HBF 访问时延，单位为 ns |
| `num_devices` | Integer | HBF 设备数量 |

实例级 `hbf_prefetch` 字段：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `enabled` | Boolean | 是否启用 HBF 预取 |
| `ffn_ratio` | Float | FFN 稀疏传输比例，范围 `[0, 1]` |
| `predict_base_ns` | Integer | 基础预测时间 |
| `predict_attn_ns` | Integer | Attention 预测时间 |
| `predict_ffn_ns` | Integer | FFN 预测时间 |

placement 规则中可使用 `hbf[:id]`。例如：

```json
{
  "placement": {
    "default": {
      "weights": "hbf:0",
      "kv_loc": "npu",
      "kv_evict_loc": "cpu"
    }
  }
}
```

在 HBF 模式下，dense hidden-layer 的 Attention / FFN 权重会被自动解释为从 HBF 进入 HBM buffer；不需要再手工逐层拆分 qkv、o_proj 和 FFN 三个投影层的放置规则。
