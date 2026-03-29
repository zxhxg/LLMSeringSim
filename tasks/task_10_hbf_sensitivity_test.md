# Task 10：HBF 参数敏感性测试

## 任务目标

- 在不修改代码的前提下，扩展 HBF 测试覆盖面。
- 分别验证两类敏感性：
  - `ffn_ratio` 改变时，FFN 传输量、总传输量、stall 与 latency 是否按预期变化。
  - `predict_*_ns` 改变时，`T_predict`、stall 与 latency 是否按严格时间模型变化。
- 判断当前实现结果是否符合设计预期，并记录偏差。

## 修改文件

- `cluster_config/single_node_hbf_ffn075.json`
- `cluster_config/single_node_hbf_ffn050.json`
- `cluster_config/single_node_hbf_ffn025.json`
- `cluster_config/single_node_hbf_ffn000.json`
- `cluster_config/single_node_hbf_ffn050_predict2ms.json`
- `cluster_config/single_node_hbf_ffn050_predict5ms.json`
- `tasks/task_10_hbf_sensitivity_test.md`

## 修改模块

- 配置文件：`cluster_config/`
- 测试日志：`tasks/`

## 修改函数

- 本任务未修改代码函数。

## 实现逻辑

1. 以 `cluster_config/single_node_hbf_instance.json` 为基线，生成多组测试配置。
2. 保持模型、数据集、请求数、network backend 不变，仅改变：
   - `hbf_prefetch.ffn_ratio`
   - `hbf_prefetch.predict_base_ns`
   - `hbf_prefetch.predict_attn_ns`
   - `hbf_prefetch.predict_ffn_ns`
3. 在 Docker 容器 `servingsim_docker` 中顺序执行，避免并发仿真互相干扰。
4. 从日志中提取以下指标并进行对比：
   - `Total latency (s)`
   - `HBF attention transfer bytes`
   - `HBF FFN transfer bytes`
   - `HBF total transfer bytes`
   - `HBF predict time (ns)`
   - `HBF transfer time (ns)`
   - `HBF stall time (ns)`

## 测试环境

- 容器：`servingsim_docker`
- 工作目录：`/app/LLMServingSim`
- 数据集：`dataset/sharegpt_req100_rate10_llama.jsonl`
- 请求数：`2`
- network backend：`analytical`

## 测试命令

### FFN 传输量扫描

```bash
python3 main.py --cluster-config cluster_config/single_node_hbf_ffn075.json --fp 16 --block-size 16 --dataset dataset/sharegpt_req100_rate10_llama.jsonl --num-req 2 --log-interval 1.0 --log-level WARNING
python3 main.py --cluster-config cluster_config/single_node_hbf_ffn025.json --fp 16 --block-size 16 --dataset dataset/sharegpt_req100_rate10_llama.jsonl --num-req 2 --log-interval 1.0 --log-level WARNING
python3 main.py --cluster-config cluster_config/single_node_hbf_ffn000.json --fp 16 --block-size 16 --dataset dataset/sharegpt_req100_rate10_llama.jsonl --num-req 2 --log-interval 1.0 --log-level WARNING
```

说明：

- `ffn_ratio = 1.0` 与 `ffn_ratio = 0.5` 复用 `task_final_test.md` 中已成功执行的基线结果。

### Stall 时间扫描

```bash
python3 main.py --cluster-config cluster_config/single_node_hbf_ffn050_predict2ms.json --fp 16 --block-size 16 --dataset dataset/sharegpt_req100_rate10_llama.jsonl --num-req 2 --log-interval 1.0 --log-level WARNING
python3 main.py --cluster-config cluster_config/single_node_hbf_ffn050_predict5ms.json --fp 16 --block-size 16 --dataset dataset/sharegpt_req100_rate10_llama.jsonl --num-req 2 --log-interval 1.0 --log-level WARNING
```

## 结果汇总

### 1. `ffn_ratio` 扫描

| 用例 | latency (s) | attn bytes | ffn bytes | total bytes | predict ns | transfer ns | stall ns |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `ffn_ratio=1.0` | 384.716 | 1609689989120 | 6760697954304 | 8370387943424 | 7675600 | 209290393310 | 209298068910 |
| `ffn_ratio=0.75` | 343.665 | 1609689989120 | 5070523465728 | 6680213454848 | 7675600 | 167036023420 | 167043699020 |
| `ffn_ratio=0.5` | 301.411 | 1609689989120 | 3380348977152 | 4990038966272 | 7675600 | 124781672719 | 124789348319 |
| `ffn_ratio=0.25` | 259.157 | 1609689989120 | 1690174488576 | 3299864477696 | 7675600 | 82527302829 | 82534978429 |
| `ffn_ratio=0.0` | 230.394 | 1609689989120 | 0 | 1609689989120 | 7675600 | 40257600928 | 40265276528 |

### 2. 固定 `ffn_ratio=0.5` 的 stall 扫描

| 用例 | latency (s) | ffn bytes | total bytes | predict ns | transfer ns | stall ns |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `baseline(200/100/100ns)` | 301.411 | 3380348977152 | 4990038966272 | 7675600 | 124781672719 | 124789348319 |
| `predict=2ms/layer` | 301.411 | 3380348977152 | 4990038966272 | 38378000000 | 124781672719 | 163159672719 |
| `predict=5ms/layer` | 301.411 | 3380348977152 | 4990038966272 | 95945000000 | 124781672719 | 220726672719 |

## 结果分析

### 1. `ffn_ratio` 相关结果

- `HBF attention transfer bytes` 在所有用例中保持不变，说明 Attention 仍按“全量传输”建模，符合设计预期。
- `HBF FFN transfer bytes` 随 `ffn_ratio` 呈线性变化：
  - `0.75` 时为 `1.0` 的 `75%`
  - `0.5` 时为 `1.0` 的 `50%`
  - `0.25` 时为 `1.0` 的 `25%`
  - `0.0` 时降为 `0`
- `HBF total transfer bytes` 也按“Attention 常量 + FFN 线性缩放”变化，符合 `full_size × ffn_ratio` 的实现目标。
- `HBF transfer time`、`HBF stall time` 与 `latency` 都随 `ffn_ratio` 下降而单调下降，整体趋势符合预期。
- `ffn_ratio=0.0` 时，总传输量退化为纯 Attention 传输量，验证了 FFN 稀疏路径的下界行为。

结论：

- 就 FFN 稀疏加载而言，当前实现与设计目标一致，结果符合预期。

### 2. stall 时间相关结果

- 在固定 `ffn_ratio=0.5` 时，`ffn bytes`、`total bytes`、`transfer ns` 保持不变，说明测试隔离有效。
- `predict ns` 从 `7675600` 提升到 `38378000000` 和 `95945000000` 后，`stall ns` 也同步提升到 `163159672719` 和 `220726672719`。
- `stall ns` 的增量与 `predict ns` 的增量基本一致，说明统计公式 `T_prefetch = T_predict + T_transfer` 与 `stall = max(0, T_prefetch - T_compute)` 的计数逻辑在指标层面是生效的。

但是：

- 三组用例的 `Total latency (s)` 全部保持为 `301.411`，没有随 `predict ns` 的增大而上升。
- 如果严格按照设计目标，“执行 layer i 时为 layer i+1 预取，且 compute(i+1) 必须等待 prefetch(i+1) 完成”，那么更大的 `T_predict` 应该会推高关键路径时间，进而增加总 latency。

结论：

- `stall` 指标本身的统计结果符合预期。
- 但“更大的 stall 是否真正反馈到仿真端到端时延”这一点，目前**不完全符合预期**。
- 这说明当前实现更像是“stall 被正确统计出来了”，但 `predict` 对关键路径的阻塞作用没有完全体现在总 latency 上。

## 可能原因

- `hbf_predict` 伪层的时间可能只进入了统计路径，没有完整进入 ET 图的关键依赖路径。
- 或者 `compute(i+1)` 与 `prefetch(i+1)` 的依赖关系已经建立，但 `predict` 节点本身未成为实际时延瓶颈。
- 也可能是 `predict` 时间只累计到了 batch/global 指标，没有真正约束 ASTRA-Sim 的执行时序。

## 建议关注模块

- `inference_serving/trace_generator.py`
  - 检查 `hbf_predict` 伪层的 `comp_time` 是否真正写入 trace 并落入依赖链。
- `astra-sim/extern/graph_frontend/chakra/src/converter/llm_converter.py`
  - 检查 `HBF_PREDICT` 节点是否被转换为带时间代价的有效执行节点。
- `main.py`
  - 检查 `hbf_stall_ns` 是否只是汇总指标，还是实际来自仿真关键路径。

## 影响范围

- 本任务未改动代码逻辑，不影响现有功能行为。
- 新增测试配置文件可用于后续回归测试和问题复现。
- 该任务确认了：
  - FFN 稀疏建模正确。
  - stall 统计方向正确。
  - `predict -> stall -> latency` 的闭环仍需进一步验证或修正。

## 验证方式

- 所有新增用例均在 Docker 容器内成功执行。
- 通过对比多组日志中的 `transfer bytes / predict ns / stall ns / latency` 判断趋势。
- 结论以实际仿真输出为准，没有在测试阶段修改任何代码。
