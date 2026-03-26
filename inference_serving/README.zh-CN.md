# inference_serving

该目录包含用于 LLM 推理仿真的核心 Python 模块。

## 模块说明

### `request.py`
定义 `Request` 和 `Batch` 数据类。用于跟踪逐请求状态与时延指标（TTFT、TPOT、ITL）。

### `scheduler.py`
实现实例级调度器，采用 vLLM 风格的连续批处理。负责请求排队、受内存约束的 batch 构建、KV cache block 驱逐与换出到 CPU，以及前缀缓存查找。可在此添加自定义调度策略。

### `router.py`
根据可配置策略（Round Robin、Random、Custom）在实例之间路由传入请求。在 Prefill/Decode 解耦模式下处理请求转发。可在此添加自定义路由策略。

### `gate_function.py`
根据可配置策略（Round Robin、Random、Fast、Custom）将 token 路由到 MoE experts。可在此添加自定义 expert 路由策略。

### `memory_model.py`
跟踪 NPU、CPU 和 CXL 内存使用情况。负责 KV cache block 分配以及用于前缀缓存的 RadixCache。包含 `calculate_sizes` 和 `get_weight`，用于逐层张量大小计算；添加新的模型架构时请修改这里。

### `radix_tree.py`
用于 token 级前缀匹配的 radix tree 数据结构，供前缀缓存使用。移植自 SGLang。

### `power_model.py`
估算每个节点的功率与能耗，覆盖 NPU、CPU、DRAM、互连、NIC 和存储。

### `controller.py`
负责与 ASTRA-Sim 子进程之间的 IPC 协议。将 workload graph 路径写入 ASTRA-Sim 的 stdin，并从 stdout 解析迭代时序。

### `graph_generator.py`
调用 Chakra converter，将文本格式的 execution trace 转换为 ASTRA-Sim 使用的 protobuf workload graph。

### `trace_generator.py`
核心性能估算器。读取 `llm_profile/perf_models/{hardware}/{model}/tp{N}/` 中预先 profile 好的时延数据，并构造逐迭代执行 trace。支持 tensor parallelism（ALLREDUCE 放置）、MoE expert 路由、PIM 注意力卸载和子批交织。包含 `synthesize_trace`；添加新的模型架构时请修改这里。

### `config_builder.py`
解析用户提供的 `cluster_config` JSON，并生成 ASTRA-Sim 输入文件：`astra-sim/inputs/network/network.yml`、`astra-sim/inputs/memory/memory_expansion.json` 和 `astra-sim/inputs/system/system.json`。

### `pim_model.py`
解析 `pim_config/` 中的 PIM 设备 INI 配置文件，推导 trace generator 在 PIM 注意力卸载中使用的带宽、时延和功耗参数。

### `attn_utils.py`
计算作为 scikit-learn 注意力时延预测器输入的注意力特征向量。

### `utils.py`
提供用于加载模型配置、构造 workload 路径和格式化终端输出的辅助函数。

### `logger.py`
配置 LLMServingSim logger。日志级别通过 `main.py` 中的 `--log-level` 设置。
