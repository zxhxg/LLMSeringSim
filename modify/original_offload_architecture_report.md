# 原模拟器中 HBM + CPU Memory + CXL 卸载机制分析

## 分析范围

本报告聚焦“原模拟器”里已经存在的卸载路径，也就是未引入本次 Task 1 的 HBF 扩展前，代码里关于 NPU(HBM) / CPU memory / CXL 的实现方式。

重点回答 3 个问题：

1. HBM + CPU memory + CXL 是如何实现卸载的？
2. 传输过程中有没有使用 overlap？
3. 有没有使用预测器？如果有，策略是什么？

---

## 一句话结论

原模拟器里的“卸载”并不是单一机制，而是 3 条并行存在的路径：

1. 权重卸载：通过 placement 把层权重放到 `CPU(REMOTE)` 或 `CXL`，运行时按层生成 memory load node。
2. KV 卸载：当 NPU 显存不足时，scheduler 把请求的 KV 从 NPU 换出到 CPU；后续再调度到该请求时再从 CPU 换回。
3. 前缀缓存二级池：开启 prefix caching 后，可把第二级 prefix pool 放在 CPU 或 CXL。

关于 overlap：

- 有“隐式 overlap 机会”，但没有发现专门针对 CPU/CXL 卸载设计的 overlap 调度器。
- 同一个 CPU/CXL device 上的请求在 analytical memory backend 中是串行排队的。
- 文档里提到的 sub-batch interleaving overlap，是给 XPU/PIM 用的，不是给 CPU/CXL 传输用的。

关于预测器：

- 没有找到 CPU/CXL 卸载传输的预测器。
- 原代码里存在的 predictor 是 attention latency predictor，只用于 attention 计算时延估计，不参与 CPU/CXL 卸载决策。

---

## 1. 原模拟器中的卸载是怎么实现的

### 1.1 权重卸载：通过 placement 放到 CPU 或 CXL

配置层面，`cluster_config` 可以把层权重放到 `cxl:x`，而 KV 仍然留在 NPU，KV eviction 位置设为 CPU。一个直接例子见 `cluster_config/single_node_cxl_instance.json`：

- `weights: "cxl:0/1/2/3"`
- `kv_loc: "npu"`
- `kv_evict_loc: "cpu"`

参考：

- `cluster_config/single_node_cxl_instance.json:27`
- `cluster_config/single_node_cxl_instance.json:53`

配置解析时，`config_builder.py` 会把 placement 字符串统一转换成 ASTRA-Sim 可识别的位置：

- `npu -> LOCAL`
- `cpu -> REMOTE:{node_id}`
- `cxl:x -> CXL:x`

同时：

- `cpu_mem` 被写成 `PER_NODE_MEMORY_EXPANSION`
- `cxl_mem` 被写成 `MEMORY_POOL`

参考：

- `inference_serving/config_builder.py:56`
- `inference_serving/config_builder.py:257`
- `inference_serving/config_builder.py:579`

trace 生成时，每一层都会带上 `weight_loc` 和 `weight_size`。如果该层权重不在 `LOCAL`，Chakra 转换器会为它额外生成一个 `weight_load_node`。

参考：

- `inference_serving/trace_generator.py:167`
- `astra-sim/extern/graph_frontend/chakra/src/converter/llm_converter.py:441`

最终在 ASTRA-Sim 里，这个 memory node 会根据 tensor location 分发到不同内存对象：

- `LOCAL_MEMORY -> local_mem`
- `REMOTE_MEMORY -> remote_mem`
- `CXL_MEMORY -> cxl_mem`

参考：

- `astra-sim/astra-sim/workload/Workload.cc:220`

这意味着原模拟器里的“权重卸载”本质上是：

1. 用 placement 决定权重驻留位置；
2. 在 trace/graph 中显式生成 memory load；
3. 由 ASTRA-Sim memory backend 按 bandwidth/latency 模型完成传输时间仿真。

### 1.2 KV 卸载：NPU 不够时换出到 CPU

`inference_serving/README.md` 直接说明了 scheduler 负责 “KV cache block eviction and swapping to CPU”。

参考：

- `inference_serving/README.md:11`

具体实现位于 `scheduler.py`。

当 NPU 可用容量不足时，scheduler 会：

1. 计算需要释放的 KV 大小；
2. 将请求标记为 `req.evict = True`；
3. 从 NPU 释放该部分 KV；
4. 在 CPU 上分配对应空间。

参考：

- `inference_serving/scheduler.py:379`
- `inference_serving/scheduler.py:381`

当后续再次调度到该请求时，如果发现 `req.evict == True`，则：

1. 统计需要 reload 的 KV 大小；
2. 清掉 eviction 标记；
3. 把 KV 从 CPU 重新加载回 NPU；
4. 再释放 CPU 侧副本。

参考：

- `inference_serving/scheduler.py:395`
- `inference_serving/scheduler.py:407`

这条路径里，原版实现是明确的 “NPU <-> CPU swap”，没有看到把普通 KV swap 直接做成 “NPU <-> CXL” 的独立主路径。

### 1.3 Prefix caching 的二级池：可以放在 CPU 或 CXL

除了普通 KV swap，原模拟器还支持 prefix cache 的二级存储层。

README 明确写到：

- prefix caching 可以启用 second-tier prefix pool
- second-tier prefix pool 可放在 `CPU` 或 `CXL`

参考：

- `README.md:14`
- `README.md:114`

实现上，`memory_model.py` 在启用 prefix caching 且设置 `prefix_storage` 时，会创建一个 second-tier `RadixCache`：

- 若 `prefix_storage == CPU`，容量来自 `cpu_mem`
- 若 `prefix_storage == CXL`，容量来自 `cxl_mem`

参考：

- `inference_serving/memory_model.py:129`
- `inference_serving/memory_model.py:134`
- `inference_serving/memory_model.py:137`

调度阶段，scheduler 会：

1. 根据 prefix hit 情况决定是否需要从 second-tier storage 加载 prefix；
2. 在容量不够时先驱逐 second-tier prefix cache；
3. 对被 evict 的请求，把 prefix blocks 写入 second-tier storage。

参考：

- `inference_serving/scheduler.py:395`
- `inference_serving/scheduler.py:429`
- `inference_serving/scheduler.py:459`
- `inference_serving/memory_model.py:540`

因此，原版 CPU/CXL 的使用场景分成两类：

- CPU：普通 KV swap 的主要落点，也是 prefix second-tier 的可选落点；
- CXL：主要作为权重放置位置，以及 prefix second-tier 的可选落点。

---

## 2. 传输过程中有没有使用 overlap

## 2.1 有 overlap 机会，但不是专门为 CPU/CXL 卸载设计的显式策略

原项目文档里明确提到的 overlap 是：

- `sub-batch interleaving to overlap XPU and PIM computation`

参考：

- `README.md:16`
- `README.md:117`

`trace_generator.py` 里也能看到，`enable_sub_batch_interleaving` 只是在普通 trace 和 interleaved trace 之间切换，其目标是 PIM/XPU 协同，不是 CPU/CXL 内存卸载。

参考：

- `inference_serving/trace_generator.py:103`

所以结论很明确：

- 有显式 overlap 功能，但它对应的是 XPU/PIM；
- 不是 CPU/CXL 卸载传输的专用 overlap 机制。

## 2.2 权重卸载存在“隐式 overlap”

虽然没有专门的 CPU/CXL overlap scheduler，但 Chakra 图构建方式给了权重加载与前后计算重叠的机会。

在 `llm_converter.py` 中：

1. 如果该层权重不在 `LOCAL`，先创建 `weight_load_node`；
2. 随后创建该层 `comp_node`；
3. `comp_node` 依赖 `weight_load_node`，同时也依赖上一层的 `comp_node` 或 `comm_node`。

参考：

- `astra-sim/extern/graph_frontend/chakra/src/converter/llm_converter.py:441`
- `astra-sim/extern/graph_frontend/chakra/src/converter/llm_converter.py:453`
- `astra-sim/extern/graph_frontend/chakra/src/converter/llm_converter.py:490`
- `astra-sim/extern/graph_frontend/chakra/src/converter/llm_converter.py:493`

关键点在于：

- `weight_load_node` 本身通常不会被强制串到上一层计算之后；
- 但当前层 `comp_node` 会同时等待 “上一层完成” 和 “本层 weight_load 完成”。

这意味着如果后端资源允许，`weight_load_node` 可以提前发起，并与前一层计算/通信形成一定程度的重叠。这是一种图依赖层面的“机会型 overlap”，不是显式的预取调度器。

## 2.3 KV load / evict 没有看到专门的流水 overlap 策略

`trace_generator.py` 会把 `kv_load` / `kv_evict` 插到 trace 开头。

参考：

- `inference_serving/trace_generator.py:124`
- `inference_serving/trace_generator.py:127`
- `inference_serving/trace_generator.py:132`

在 Chakra 转换阶段，这两个节点会先被识别成 memory load / store node，并且第一条计算节点会显式依赖它们。

参考：

- `astra-sim/extern/graph_frontend/chakra/src/converter/llm_converter.py:305`
- `astra-sim/extern/graph_frontend/chakra/src/converter/llm_converter.py:355`
- `astra-sim/extern/graph_frontend/chakra/src/converter/llm_converter.py:479`

因此，普通 KV swap 更像是：

1. 先做 `kv_load` / `kv_evict`；
2. 再进入后续计算。

我没有看到这里存在专门的“边传边算”策略，也没有看到 KV reload 的预测式预取。

## 2.4 同一个 CPU/CXL 设备上的请求是串行排队的

在 analytical memory backend 中，`PER_NODE_MEMORY_EXPANSION` 和 `MEMORY_POOL` 都维护了 `ongoing_transaction[device_id]` 和 `pending_requests[device_id]`。

如果某个 device 正忙，则新的 memory request 会进入队列；等前一个完成后再发下一个。

参考：

- `astra-sim/extern/memory_backend/analytical/AnalyticalMemory.cc:166`
- `astra-sim/extern/memory_backend/analytical/AnalyticalMemory.cc:185`
- `astra-sim/extern/memory_backend/analytical/AnalyticalMemory.cc:233`
- `astra-sim/extern/memory_backend/analytical/AnalyticalMemory.cc:251`

这说明：

- 同一个 CPU remote memory device 上，请求默认串行；
- 同一个 CXL pool device 上，请求默认串行；
- overlap 是否发生，依赖于图依赖和底层是否是不同资源，而不是上层专门做了 CPU/CXL 传输 overlap 编排。

---

## 3. 有没有使用预测器

## 3.1 有预测器，但不是给 CPU/CXL 卸载用的

README 的 v1.0.0 highlights 明确提到：

- `scikit-learn-based attention latency predictor replaces tabular lookup`

参考：

- `README.md:7`

代码里 `enable_attn_prediction` 出现在 `trace_generator.py`，它控制的是 attention latency 的建模方式：

- 关闭时：走 profile/perf DB 查表；
- 开启时：走 attention latency predictor。

参考：

- `inference_serving/trace_generator.py:75`
- `inference_serving/trace_generator.py:176`
- `inference_serving/trace_generator.py:318`

因此，这个 predictor 的职责是：

- 根据 attention 的特征估算 attention compute latency；
- 用来替换固定 profile lookup；
- 目标是更准确地覆盖不同 batch size / sequence length。

它不负责：

- 预测 CPU/CXL 传输时间；
- 决定何时 evict/load；
- 决定是否 overlap；
- 决定权重或 KV 的预取时机。

## 3.2 没有找到 CPU/CXL 传输预测器或卸载预测器

本次检查中，没有看到以下机制：

- CPU/CXL memory access predictor
- KV eviction predictor
- 权重 offload prefetch predictor
- 基于未来 token / future layer 的 CPU/CXL 传输预测

原版 CPU/CXL 的时延模型主要还是：

- placement 决定数据在哪；
- trace/graph 决定何时发起 memory node；
- analytical memory backend 用 `latency + size / bw` 建模传输时间，并在同一 device 内串行排队。

参考：

- `astra-sim/extern/memory_backend/analytical/AnalyticalMemory.cc:171`
- `astra-sim/extern/memory_backend/analytical/AnalyticalMemory.cc:190`

---

## 4. 原模拟器对 CPU/CXL 卸载的真实策略总结

如果把原版策略压缩成一句更工程化的话，可以概括为：

“原模拟器使用 placement + trace memory node + analytical memory queue 的组合来实现 CPU/CXL 卸载，具备图级别的隐式 overlap 机会，但没有专门的 CPU/CXL overlap 调度器，也没有 CPU/CXL 卸载预测器。”

更细一点：

1. 权重卸载策略

- 静态 placement 决定哪些层权重在 CPU/CXL；
- 运行到该层时生成相应的 weight load node；
- 当前层计算必须等待本层 weight load 完成。

2. KV 卸载策略

- 当 NPU 容量不足时，由 scheduler 立即把请求 KV 换出到 CPU；
- 请求再次被调度时，再从 CPU 换回；
- 没看到提前预测和预取。

3. Prefix storage 策略

- NPU 做一级 prefix cache；
- CPU 或 CXL 作为二级 prefix pool；
- 根据 hit/miss 和容量情况做 cache insert / eviction / reload。

4. overlap 策略

- CPU/CXL 路径没有专门的 overlap 调度器；
- 权重 load 因为图依赖设计，可能与前一层 compute/comm 形成隐式重叠；
- 同一 memory device 内部仍然串行。

5. predictor 策略

- predictor 只用于 attention latency；
- 不用于 CPU/CXL 卸载决策。

---

## 5. 最终结论

针对你问的“HMB + CPU memory + CXL 是如何实现卸载功能、传输过程中有没有 overlap 和预测器、策略是什么”，可以直接给出最终判断：

1. 原模拟器的卸载功能主要通过三条路径实现：

- 层权重放置到 CPU/CXL；
- KV 在显存不足时换出到 CPU；
- prefix cache 二级池放到 CPU/CXL。

2. CPU/CXL 传输没有看到专门的 overlap 调度器。

- 存在 graph-level 的隐式 overlap 机会，主要体现在 weight load 可以比当前层 compute 更早发起；
- 但普通 KV swap 更接近“先搬再算”；
- 同一 device 上的 memory request 在 analytical backend 中串行。

3. 没有看到 CPU/CXL 传输预测器。

- 唯一明确存在的 predictor 是 attention latency predictor；
- 它服务的是 attention 计算建模，不参与 CPU/CXL offload 的时机选择或带宽竞争调度。

所以，原版 CPU/CXL 卸载策略整体上偏“静态 placement + 按需加载/换出 + backend 排队建模”，而不是“带预测器的主动预取 + 显式 overlap 编排”。
