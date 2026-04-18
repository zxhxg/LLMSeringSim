# Task 1 Test Report

## 0. 简短回顾

### 对 HBF 的理解

HBF 在本任务中被建模为独立于 HBM/CPU/CXL 的 GPU 侧权重存储层。它承载 dense、layer-wise 的权重读取，并且需要有自己的容量、带宽、时延与请求统计。

### 对 HBM + HBF 架构的理解

HBM 负责本地工作集与计算路径，HBF 负责更大容量但更高访问代价的权重层。Task 1 的最小闭环是：权重位于 HBF，计算仍在 NPU/HBM 路径，每层触发一次 dense HBF read，并输出 HBF traffic、latency、throughput。

### 对模拟器主链路的理解

本次改动遵循 `main.py -> config_builder.py -> Scheduler -> MemoryModel -> trace_generator.py -> graph_generator.py -> ASTRA-Sim` 这条主链路。HBF 接入主要落在 Python 侧配置解析、权重常驻统计、trace 后处理与结果汇总，没有把 `controller.py` 或 `logger.py` 当成主实现点。

---

## 1. 本次修改内容

### 修改文件

- `inference_serving/config_builder.py`
- `inference_serving/memory_model.py`
- `inference_serving/scheduler.py`
- `inference_serving/trace_generator.py`
- `inference_serving/utils.py`
- `main.py`
- `cluster_config/README.md`
- `cluster_config/single_node_hbf_shared_frontend.json`
- `cluster_config/single_node_hbf_fully_independent.json`
- `cluster_config/single_node_hbf_fully_serialized.json`

### 各文件改动说明

- `config_builder.py`
  - 新增顶层 `hbf_mem` 解析，并注入 ASTRA-Sim `memory_expansion.json`
  - 新增顶层 `bw_mode` 解析，支持 CLI `--hbf-bw-mode` 覆盖
  - 扩展 placement 解析与校验，使 `weights: "hbf:x"` 成为合法位置
  - 将 `hbf_enabled`、`hbf_mem`、`bw_mode` 写入 cluster 结果，供后续模块使用

- `memory_model.py`
  - 不再默认把整模型权重计入 NPU 常驻内存
  - 按 placement 重新统计 resident NPU / HBF / REMOTE / CXL 权重
  - 新增 HBF 统计字段：`hbf_total_size`、`hbf_used_size`、`hbf_read_bytes`、`hbf_read_requests`、`hbf_read_time_us`
  - 新增 `bw_mode` 对应的 HBF 读时延建模辅助函数

- `scheduler.py`
  - 把 `placement`、`npu_mem.mem_bw`、`hbf_mem`、`bw_mode` 传给 `MemoryModel`

- `trace_generator.py`
  - 保持原有 dense weight-load trace 结构
  - 新增 trace 后处理：当某层 `weight_loc` 为 `HBF` 时，记录 HBF 读请求与字节数，并按 `bw_mode` 给该层补充 frontend penalty
  - 这样可以同时覆盖普通 trace 与 sub-batch interleaving trace

- `utils.py`
  - 输入配置展示中新增 `HBF bw_mode` 字段

- `main.py`
  - 新增 CLI 参数 `--hbf-bw-mode`
  - 启动阶段打印 HBF 是否启用、HBF 配置与实际 `bw_mode`
  - 运行时每个 instance 打印 HBF resident weight usage
  - 结果汇总阶段输出 HBF 统计项

- `cluster_config/README.md`
  - 新增 HBF 配置说明、`bw_mode` 说明、`weights: "hbf:0"` 示例
  - 新增 3 组 HBF 测试配置说明

- 新增 3 组 HBF 配置文件
  - `single_node_hbf_shared_frontend.json`
  - `single_node_hbf_fully_independent.json`
  - `single_node_hbf_fully_serialized.json`

### `bw_mode` 的实现方式

本次实现采用 Python 侧附加 penalty 的方式来表达 frontend 共享关系，同时保留 ASTRA-Sim 已有的 `HBF_MEMORY` load 路径。

- `fully_independent`
  - 只保留 HBF 自身的带宽与时延
  - 不增加额外 frontend penalty

- `shared_frontend`
  - 以 `min(hbf_bw, npu_mem_bw)` 作为共享前端的有效带宽
  - 额外 penalty = `size / min(hbf_bw, npu_mem_bw) - size / hbf_bw`

- `fully_serialized`
  - 在 HBF 自身传输之外，再叠加一次 `size / npu_mem_bw`
  - 作为悲观下界

这是基于 Task 1 文档语义做出的 Python 层建模假设，用于在不改 ASTRA-Sim 协议的前提下保证三种模式可区分。

---

## 2. 测试环境说明

- 工作平台：当前已运行容器 `servingsim_docker`
- 仓库路径：`/app/LLMServingSim`
- 网络后端：`analytical`
- 数据集：`dataset/sharegpt_req100_rate10_llama.jsonl`

### Step 0 环境验证命令

```bash
python main.py \
    --cluster-config cluster_config/single_node_single_instance.json \
    --fp 16 --block-size 16 \
    --dataset dataset/sharegpt_req100_rate10_llama.jsonl \
    --output output/example_single_run.csv \
    --num-req 100 --log-interval 1.0
```

### Step 0 验证结果

- 官方示例命令执行成功
- 无依赖错误、无路径错误、无配置缺失错误
- 成功生成 `output/example_single_run.csv`
- 关键结果
  - `Total latency (s): 28.226`
  - `Request throughput (req/s): 3.54`
  - `Total token throughput (tok/s): 1571.81`

---

## 3. 测试配置列表

### 配置 A: HBM + HBF shared_frontend

- 配置文件：`cluster_config/single_node_hbf_shared_frontend.json`
- 命令：

```bash
python main.py \
    --cluster-config cluster_config/single_node_hbf_shared_frontend.json \
    --fp 16 --block-size 16 \
    --dataset dataset/sharegpt_req100_rate10_llama.jsonl \
    --output output/task1_hbf_shared_frontend.csv \
    --num-req 100 --log-interval 1.0 --log-level WARNING
```

### 配置 B: HBM + HBF fully_independent

- 配置文件：`cluster_config/single_node_hbf_fully_independent.json`
- 命令：

```bash
python main.py \
    --cluster-config cluster_config/single_node_hbf_fully_independent.json \
    --fp 16 --block-size 16 \
    --dataset dataset/sharegpt_req100_rate10_llama.jsonl \
    --output output/task1_hbf_fully_independent.csv \
    --num-req 100 --log-interval 1.0 --log-level WARNING
```

### 配置 C: HBM + HBF fully_serialized

- 配置文件：`cluster_config/single_node_hbf_fully_serialized.json`
- 命令：

```bash
python main.py \
    --cluster-config cluster_config/single_node_hbf_fully_serialized.json \
    --fp 16 --block-size 16 \
    --dataset dataset/sharegpt_req100_rate10_llama.jsonl \
    --output output/task1_hbf_fully_serialized.csv \
    --num-req 100 --log-interval 1.0 --log-level WARNING
```

### 配置 D: 原始 HBM + CPU memory 对照组

- 配置文件：`cluster_config/single_node_memory_instance.json`
- 命令：

```bash
python main.py \
    --cluster-config cluster_config/single_node_memory_instance.json \
    --fp 16 --block-size 16 \
    --dataset dataset/sharegpt_req100_rate10_llama.jsonl \
    --output output/task1_memory_control.csv \
    --num-req 100 --log-interval 1.0 --log-level WARNING
```

---

## 4. 测试结果

### 配置 A: HBM + HBF shared_frontend

- 运行成功：是
- 关键日志摘要
  - `HBF enabled: True`
  - `HBF config: size=1024GB, bw=1536GB/s, latency=50ns, devices=1, bw_mode=shared_frontend`
- 关键指标
  - `Total latency (s): 35.665`
  - `Request throughput (req/s): 2.80`
  - `Total token throughput (tok/s): 1243.96`
  - `HBF read bytes (MB): 12666751.96`
  - `HBF read requests: 240657`
  - `HBF modeled read time (us): 16118526.89`

### 配置 B: HBM + HBF fully_independent

- 运行成功：是
- 关键日志摘要
  - `HBF enabled: True`
  - `HBF config: size=1024GB, bw=1536GB/s, latency=50ns, devices=1, bw_mode=fully_independent`
- 关键指标
  - `Total latency (s): 28.725`
  - `Request throughput (req/s): 3.48`
  - `Total token throughput (tok/s): 1544.51`
  - `HBF read bytes (MB): 13355994.81`
  - `HBF read requests: 253752`
  - `HBF modeled read time (us): 8504070.13`

### 配置 C: HBM + HBF fully_serialized

- 运行成功：是
- 关键日志摘要
  - `HBF enabled: True`
  - `HBF config: size=1024GB, bw=1536GB/s, latency=50ns, devices=1, bw_mode=fully_serialized`
- 关键指标
  - `Total latency (s): 42.565`
  - `Request throughput (req/s): 2.35`
  - `Total token throughput (tok/s): 1042.32`
  - `HBF read bytes (MB): 12283839.27`
  - `HBF read requests: 233382`
  - `HBF modeled read time (us): 23441002.77`

### 配置 D: 原始 HBM + CPU memory 对照组

- 运行成功：是
- 关键日志摘要
  - `HBF enabled: False`
  - `HBF bw_mode: shared_frontend (inactive because no hbf_mem is configured)`
- 关键指标
  - `Total latency (s): 28.226`
  - `Request throughput (req/s): 3.54`
  - `Total token throughput (tok/s): 1571.81`

### 性能关系检查

按 Task 1 预期，HBF 三种模式应满足：

- latency: `fully_independent <= shared_frontend <= fully_serialized`
- throughput: `fully_independent >= shared_frontend >= fully_serialized`

本次实测结果：

| Mode | Total latency (s) | Request throughput (req/s) | Total token throughput (tok/s) |
| --- | ---: | ---: | ---: |
| `fully_independent` | 28.725 | 3.48 | 1544.51 |
| `shared_frontend` | 35.665 | 2.80 | 1243.96 |
| `fully_serialized` | 42.565 | 2.35 | 1042.32 |

结论：三种模式的性能关系符合预期。

### 对照组兼容性检查

- `single_node_memory_instance.json` 仍可成功运行
- 关闭 HBF 后没有出现副作用
- 对照组结果与 Step 0 官方示例结果保持一致量级，并且本次结果恰好与官方示例相同

---

## 5. 结论

- Task 1 是否完成：是
- 是否可进入下一阶段：是，可以继续做后续更细粒度的 HBF 工具链或 request-granular replay
- 是否存在遗留问题：有一些明确边界内的遗留项，但不影响 Task 1 通过

### 已完成的验收点

- 官方示例命令验证通过
- HBF memory tier 已接入 Python 配置链路
- `weights: "hbf:x"` 已可被 placement 解析与校验
- `shared_frontend` / `fully_independent` / `fully_serialized` 三种 `bw_mode` 均可运行
- HBF 统计项可在结果中体现
- 原有 HBM + CPU memory 路径兼容
- 四组配置都生成了有效 CSV 输出

### 遗留与后续建议

- 当前 `bw_mode` 是 Python 侧 penalty 建模，不是 ASTRA-Sim 协议级别的原生 frontend 争用模型
- 当前 HBF 仍是 dense layer-wise read，没有实现 sparse/page/block/request replay
- 输入配置顶部的 `HBF bw_mode` 项只有在 CLI 显式传入 `--hbf-bw-mode` 时才会显示具体值；当前实际生效模式会在 cluster 解析完成后的 HBF 摘要中打印

总体上，这些都符合 `modify/task1.md` 中对 Task 1 的范围约束，不构成阻塞问题。
