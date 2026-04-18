五步开发任务清单（详细版）

Step 1：实现最小版 HBM+HBF 模拟器，只支持 dense full read
目标

在 LLMServingSim 中引入一个新的 HBF memory tier，并支持：

权重放在 HBF
每层按 dense full read 从 HBF 读取
输出 HBF 读取时间和 HBF traffic
为什么先做这一步

LLMServingSim 当前支持：

placement
cxl_mem
memory_model.py 跟踪 NPU/CPU/CXL
scheduler.py 管 request / KV swap
trace_generator.py 合成执行 trace。

你先把 HBF 加进去，不碰稀疏和 layout，最容易验证系统通不通。

需要修改的文件
1. cluster_config/README.md

新增 HBF 配置说明。

新增字段示例：

"hbf_mem": {
  "mem_size": 1024,
  "mem_bw": 512,
  "mem_latency": 2.0,
  "page_size": 4096,
  "num_devices": 1,
  "bw_mode": "shared_frontend"
}

并允许 placement 写：

"weights": "hbf:0"
2. cluster_config/*.json

新增一个示例配置，例如：

cluster_config/single_node_hbf_instance.json

要求：

weights 默认在 hbf:0
kv_loc 仍在 npu
kv_evict_loc 仍可保留 cpu
3. inference_serving/config_builder.py

扩展配置解析逻辑：

识别 hbf_mem
识别 weights: hbf:x
将 HBF tier 注入生成的 simulator config
4. inference_serving/memory_model.py

新增 HBF 内存池与统计：

hbf_total_size
hbf_used_size
hbf_read_bytes
hbf_read_requests
hbf_read_time_us

并新增方法：

allocate_hbf_weight()
get_weight_from_hbf()
5. inference_serving/trace_generator.py

第一版只需要支持：

当层权重位于 HBF 时
生成一个 dense full read event
计算时间：
𝑇
𝑟
𝑒
𝑎
𝑑
=
𝐿
ℎ
𝑏
𝑓
+
𝐷
𝑙
𝑎
𝑦
𝑒
𝑟
𝐵
ℎ
𝑏
𝑓
T
read
	​

=L
hbf
	​

+
B
hbf
	​

D
layer
	​

	​


如果 bw_mode=shared_frontend，则需要做带宽约束修正。

6. inference_serving/logger.py

输出新增指标：

HBF total read bytes
HBF total read requests
HBF total read time
average HBF read size
Step 1 的输入输出
输入
普通 dataset
普通 model config
single_node_hbf_instance.json
输出
每层是否从 HBF 读取
每层 HBF 读取大小
每层 HBF 读取时间
总 HBF 读取时间
end-to-end token latency / throughput
Step 1 验收标准
simulator 能读 weights: hbf:0
能正确把完整权重层记到 HBF
能输出 dense full read 的 HBF timing
不启用稀疏时结果稳定运行
日志中有 HBF 统计字段
Step 2：在真实推理框架中提取“逻辑访问 trace”
目标

不要在模拟器里直接猜 sparse 访问，而是用真实模型推理得到：

每一步
每一层
在不同稀疏率下
逻辑上需要哪些 block

注意：这里只提取逻辑访问，不做 layout，不做 scheduling。

为什么这样做

因为如果你直接把 layout/scheduling 也掺进 trace 生成里，后面无法保证：

trace 与策略自洽
不同策略之间可公平比较

所以第二步只拿：

模型语义层的真实需求

需要开发的新代码

建议单独建目录：

tools/trace_collection/
文件 1：collect_logical_trace.py

功能：

基于 Hugging Face / PyTorch / 自写推理脚本
对目标模型（如 Llama-2 / Llama-3）执行推理
在每个 step、每层记录：
layer_id
phase: prefill / decode
sparsity_ratio
selected logical blocks
selected_block_count
文件 2：block_partition.py

功能：

定义 FFN block 划分方式
block 大小可配置
例如：
64 neurons
128 neurons
256 neurons
文件 3：sparsity_driver.py

功能：

控制不同稀疏率实验
例如 sweep：
5%
10%
20%
30%
50%
100%
第二步的输出文件格式

建议输出 JSONL，每行一个逻辑访问事件。

文件名
artifacts/logical_trace_llama2_7b.jsonl
每行格式
{
  "model": "llama2-7b",
  "phase": "decode",
  "step": 123,
  "layer_id": 17,
  "layer_type": "ffn",
  "sparsity_ratio": 0.1,
  "block_size": 128,
  "selected_blocks": [2, 5, 9, 11],
  "selected_block_count": 4
}
Step 2 验收标准
能对指定模型输出逻辑 block trace
稀疏率可 sweep
trace 中不包含物理 page，不包含 layout，不包含 scheduling
同一输入重复运行结果稳定
Step 3：离线做 layout / placement / mapping
目标

把第二步得到的逻辑 block 访问转换成：

物理 page 访问
touched page count
segment count
average segment length
page amplification

这是第三步最关键的概念：

placement

决定数据在哪一层：

第一版固定：
weights 在 HBF
active working set 在 HBM
layout

决定同一层内部怎么排：

random
original contiguous
co-access-aware
mapping

决定：

block b17 在 HBF 中对应哪些 page range
需要开发的新代码

建议单独目录：

tools/layout_mapping/
文件 1：build_layout.py

输入：

模型结构
block 定义
layout 策略

输出：

block -> page range 映射表

支持三种 layout：

random_layout

随机分配 block 地址

contiguous_layout

按 layer/block 原始顺序连续分配

coaccess_layout

基于逻辑 trace 统计 block 共访问关系，再把共访问 block 放得更近

文件 2：coaccess_stats.py

从逻辑 trace 中统计：

𝐴
𝑖
𝑗
=
𝑃
(
𝑖
,
𝑗
 co-access
)
A
ij
	​

=P(i,j co-access)

输出 block 共访问矩阵。

文件 3：apply_mapping.py

把第二步的逻辑 trace 转成物理访问 trace：

输入：

logical trace
layout mapping

输出：

touched pages
page ranges
segment count
average segment length
real bytes read
第三步输出文件格式
文件名
artifacts/physical_trace_llama2_7b_contiguous.jsonl
每行格式
{
  "model": "llama2-7b",
  "phase": "decode",
  "step": 123,
  "layer_id": 17,
  "sparsity_ratio": 0.1,
  "layout_type": "coaccess_layout",
  "selected_blocks": [2, 5, 9, 11],
  "touched_pages": 48,
  "page_ranges": [[100, 111], [130, 135], [220, 243]],
  "segment_count": 3,
  "avg_segment_length_pages": 16,
  "real_bytes_read": 196608,
  "page_amplification_ratio": 1.42
}
Step 3 验收标准
同一 logical trace 在不同 layout 下给出不同 physical trace
能正确统计：
touched pages
segment count
avg segment length
coaccess_layout 确实能减少 segment count
Step 4：离线做 scheduling / request materialization
目标

把第三步的 page 访问结果进一步转成：

最终 HBF 请求流
请求数
每次请求大小
是否 dense-over-sparse
最终读取时间估计参数

这里要明确：

layout 是静态的
scheduling 是动态的

layout 决定“能不能连续读”
scheduling 决定“要不要把它合并成连续读”

需要开发的新代码

建议目录：

tools/scheduling/
文件 1：materialize_requests.py

输入：

physical trace
scheduling policy

输出：

最终请求列表

支持四种 policy：

dense_full

不做稀疏，整层连续读取

naive_sparse

按 selected blocks/page ranges 直接读，不合并

grouped_sparse

对相邻 page ranges 合并读

dense_over_sparse

比较 dense full 与 sparse grouped 的时间模型，自动选更快者

文件 2：request_cost_model.py

实现请求时间模型：

𝑇
=
𝑁
𝑟
𝑒
𝑞
⋅
𝐿
ℎ
𝑏
𝑓
+
𝐷
𝑟
𝑒
𝑎
𝑙
𝐵
𝑒
𝑓
𝑓
T=N
req
	​

⋅L
hbf
	​

+
B
eff
	​

D
real
	​

	​


其中：

N_req: 请求数
L_hbf: 单次请求启动延迟
D_real: 实际读取字节数
B_eff: 有效带宽

并支持：

additive_bandwidth
shared_frontend_bandwidth
文件 3：summarize_requests.py

把 request trace 汇总成模拟器可直接读取的参数文件。

第四步输出文件格式
文件名
artifacts/request_trace_llama2_7b_grouped_sparse.jsonl
每行格式
{
  "model": "llama2-7b",
  "phase": "decode",
  "step": 123,
  "layer_id": 17,
  "policy": "grouped_sparse",
  "request_count": 3,
  "request_sizes_bytes": [49152, 24576, 98304],
  "total_bytes_read": 172032,
  "estimated_hbf_time_us": 7.3
}
给模拟器的汇总文件
{
  "model": "llama2-7b",
  "policy": "grouped_sparse",
  "per_layer_stats": [
    {
      "layer_id": 17,
      "avg_request_count": 3.7,
      "avg_total_bytes_read": 185000,
      "avg_segment_count": 3.2,
      "avg_estimated_hbf_time_us": 8.1
    }
  ]
}
Step 4 验收标准
能从 physical trace 生成 request trace
naive_sparse 和 grouped_sparse 的请求数不同
dense_over_sparse 能基于 cost model 自动决策
输出 request-level 统计
Step 5：把第三、四步结果接入模拟器，完成 end-to-end replay
目标

让改造后的 LLMServingSim 不再自己“猜”稀疏访问，而是直接使用：

第四步生成的 request stats / request traces
计算不同策略下的 end-to-end 推理时间
为什么这么做

因为 LLMServingSim 当前擅长的是：

serving 请求流
latency 统计
内存层次配置
per-layer placement。

而你的 HBF 核心问题是：

page-level weight access
fragmentation
dense vs sparse fetch

所以最合理的是让它吃“已经 materialized 的 HBF request 参数”。

需要修改的文件
1. inference_serving/trace_generator.py

新增模式：

如果提供 --hbf-request-stats path.json
则对每层读取不再只按 get_weight() 估算
而是优先读取 request stats
2. inference_serving/controller.py

让 controller 能把：

HBF 读时间
HBF 请求次数
HBF bytes
并入每层执行时间
3. inference_serving/logger.py

输出最终对比字段：

dense full HBF time
naive sparse HBF time
grouped sparse HBF time
dense_over_sparse HBF time
total token latency
throughput
HBF read requests
HBF bytes
avg effective bandwidth
4. main.py

新增参数：

--enable-hbf
--hbf-request-stats <path>
--hbf-policy dense_full|naive_sparse|grouped_sparse|dense_over_sparse
Step 5 验收标准
simulator 能吃 request stats 文件
能输出不同 HBF policy 的 end-to-end latency
能跑以下 baseline：
Full HBM
Dense HBF
Naive sparse HBF
Grouped sparse HBF
Dense-over-sparse HBF
输出 CSV 中有 per-request/per-layer HBF 统计