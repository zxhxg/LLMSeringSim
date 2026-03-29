# HBF 卸载策略性能测试报告

## 1. 测试目的

本报告回答两个问题：

1. 不同 HBF 配置与不同参数设置下，卸载到 HBF 策略的性能表现如何。
2. 在相同硬件、相同模型、相同数据集、相同请求数条件下，不卸载参数策略与卸载参数到 HBF 策略相比，性能差异如何。

## 2. 测试环境

- 容器：`servingsim_docker`
- 工作目录：`/app/LLMServingSim`
- 模型：`meta-llama/Llama-3.1-8B`
- 硬件：`A6000`
- NPU 数量：`1`
- network backend：`analytical`
- 数据集：`dataset/sharegpt_req100_rate10_llama.jsonl`
- 请求数：`2`
- `block-size`：`16`
- `fp`：`16`

## 3. 测试样本说明

本次固定使用数据集前 `2` 条请求，因此以下请求规模在所有测试中相同：

- 总输入 token 数：`44`
- 总输出 token 数：`738`
- 最大输入长度：`25`
- 最大输出长度：`619`

说明：

- “最大输出长度”来自测试样本本身，不是模型在运行时额外打印的指标。
- 以下表格中的“运行时间”采用程序输出的 `Total simulation time`。
- 以下表格中的“总时延”采用程序输出的 `Total latency (s)`。

## 4. 配置说明

### 4.1 不卸载基线

- 配置文件：[`single_node_no_hbf_instance.json`](/d:/LLMServingSim/cluster_config/single_node_no_hbf_instance.json)
- 策略：权重保留在本地 NPU，不启用 HBF prefetch。

### 4.2 HBF 卸载组

- `HBF-1.0`：[`single_node_hbf_instance.json`](/d:/LLMServingSim/cluster_config/single_node_hbf_instance.json)
- `HBF-0.75`：[`single_node_hbf_ffn075.json`](/d:/LLMServingSim/cluster_config/single_node_hbf_ffn075.json)
- `HBF-0.50`：[`single_node_hbf_ffn050.json`](/d:/LLMServingSim/cluster_config/single_node_hbf_ffn050.json)
- `HBF-0.25`：[`single_node_hbf_ffn025.json`](/d:/LLMServingSim/cluster_config/single_node_hbf_ffn025.json)
- `HBF-0.50-P5ms`：[`single_node_hbf_ffn050_predict5ms.json`](/d:/LLMServingSim/cluster_config/single_node_hbf_ffn050_predict5ms.json)

其中：

- `ffn_ratio` 越小，表示 FFN 从 HBF 传输到 HBM 的权重越少。
- `HBF-0.50-P5ms` 与 `HBF-0.50` 的主要区别是 `predict_*_ns` 显著提高，用来观察 stall 放大后的影响。

## 5. HBF 策略在不同参数下的性能

| 配置 | 运行时间 | 总时延(s) | Mean TTFT(ms) | Mean TPOT(ms) | Mean ITL(ms) | 生成吞吐(tok/s) | 总吞吐(tok/s) | HBF 总传输(bytes) | HBF stall(ns) |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `HBF-1.0` | `0h 21m 7.414s` | 231.488 | 411.40 | 373.41 | 373.74 | 3.19 | 3.38 | 8370387943424 | 209298068910 |
| `HBF-0.75` | `0h 21m 5.109s` | 189.234 | 309.01 | 305.15 | 305.48 | 3.90 | 4.13 | 6680213454848 | 167043699020 |
| `HBF-0.50` | `0h 19m 6.714s` | 146.979 | 324.53 | 236.88 | 237.21 | 5.02 | 5.32 | 4990038966272 | 124789348319 |
| `HBF-0.25` | `0h 20m 21.169s` | 104.725 | 188.00 | 168.62 | 168.95 | 7.05 | 7.47 | 3299864477696 | 82534978429 |
| `HBF-0.50-P5ms` | `0h 20m 46.198s` | 239.822 | 431.60 | 386.87 | 387.20 | 3.08 | 3.26 | 4990038966272 | 220726672719 |

### 5.1 观察结论

- 在 HBF 组内部，`ffn_ratio` 从 `1.0` 降到 `0.25` 后，总时延从 `231.488s` 降到 `104.725s`，生成吞吐从 `3.19 tok/s` 升到 `7.05 tok/s`。
- `HBF 总传输量` 随 `ffn_ratio` 下降而明显下降，说明 FFN 稀疏传输模型在性能结果上是可见的。
- `HBF-0.50-P5ms` 与 `HBF-0.50` 的 `HBF 总传输量` 相同，但 `stall` 从 `124789348319ns` 上升到 `220726672719ns`，总时延也从 `146.979s` 上升到 `239.822s`。
- 这说明在当前实现下，`predict` 时间已经真实进入关键路径，而不只是统计项。

## 6. 相同配置下，不卸载与卸载到 HBF 的性能对比

### 6.1 汇总表

| 策略 | 运行时间 | 总时延(s) | Mean TTFT(ms) | Mean TPOT(ms) | Mean ITL(ms) | 生成吞吐(tok/s) | 总吞吐(tok/s) | 总输出 token | 最大输出长度 | HBF 总传输(bytes) | HBF stall(ns) |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `本地不卸载` | `0h 1m 46.072s` | 15.901 | 33.13 | 25.12 | 25.45 | 46.41 | 49.18 | 738 | 619 | - | - |
| `HBF-1.0` | `0h 21m 7.414s` | 231.488 | 411.40 | 373.41 | 373.74 | 3.19 | 3.38 | 738 | 619 | 8370387943424 | 209298068910 |
| `HBF-0.50` | `0h 19m 6.714s` | 146.979 | 324.53 | 236.88 | 237.21 | 5.02 | 5.32 | 738 | 619 | 4990038966272 | 124789348319 |
| `HBF-0.25` | `0h 20m 21.169s` | 104.725 | 188.00 | 168.62 | 168.95 | 7.05 | 7.47 | 738 | 619 | 3299864477696 | 82534978429 |

### 6.2 对比结论

- 在当前 HBF 带宽与时延设置下，`本地不卸载` 的性能明显优于所有 HBF 卸载策略。
- 即使是本轮 HBF 组里表现最好的 `HBF-0.25`，总时延仍是 `本地不卸载` 的约 `6.59x`，生成吞吐也只有 `7.05 tok/s`，显著低于本地策略的 `46.41 tok/s`。
- `HBF-1.0` 相对 `本地不卸载` 的总时延约为 `14.56x`，说明在当前参数下，“完整卸载 + 完整传输”代价非常高。

### 6.3 原因解释

从当前结果看，HBF 卸载策略的瓶颈主要来自：

- HBF 到 HBM 的权重传输量较大。
- HBF 带宽和显式时延会直接累积到 prefetch/stall。
- 即使 prefetch 可以重叠，也仍然存在明显的剩余 stall。

因此，在当前测试配置下：

- HBF 更像是“容量换性能”的策略。
- 如果目标是纯性能最优，那么当前参数下应优先保留本地不卸载策略。
- 如果目标是研究“显存容量受限时的可行退化路径”，那么 HBF 策略仍然有建模价值，尤其是 `ffn_ratio` 较低时。

## 7. 最终结论

### 7.1 关于“不同 HBF 配置与参数”

- `ffn_ratio` 越低，HBF 传输量越小，TTFT、TPOT、ITL、总时延和吞吐都明显改善。
- `predict` 时间越大，stall 越大，总时延也越大。
- 这说明当前 HBF prefetch、FFN 稀疏和 stall 建模已经能稳定反映到最终性能指标上。

### 7.2 关于“本地不卸载 vs 卸载到 HBF”

- 在本次测试使用的硬件和参数下，本地不卸载策略性能最好。
- HBF 卸载策略带来的传输和 stall 开销很大，导致首 token 时间、总运行时间和 token 生成速度都显著变差。
- 目前更适合把 HBF 策略理解为“为容量与分层存储研究服务”的机制，而不是在这组参数下直接提升性能的机制。

## 8. 可继续扩展的测试方向

- 调高 `hbf_mem.mem_bw`，观察 HBF 带宽阈值对性能拐点的影响。
- 调低 `hbf_mem.mem_latency`，观察高延迟建模对 stall 的敏感性。
- 固定 `ffn_ratio`，进一步细扫 `predict_*_ns`，找出 `predict` 成为主瓶颈的区间。
- 增大请求数与 batch 压力，观察 HBF prefetch 在更高并发场景下的收益或劣化。
