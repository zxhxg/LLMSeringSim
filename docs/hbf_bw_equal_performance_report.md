# HBF 带宽对齐 HBM 后的性能复测与分析报告

## 1. 测试目的

本轮测试在一个新的前提下重新评估 HBF 卸载策略：

- 将所有 HBF 配置中的 `hbf_mem.mem_bw` 调整为与 HBM 相同的带宽，即 `768`

在此基础上，回答以下两个问题：

1. 不同 HBF 参数配置下，卸载到 HBF 的性能如何变化。
2. 在相同硬件与相同负载下，本地不卸载策略与 HBF 卸载策略相比，性能差异如何。

此外，额外分析：

- 每层预取与计算之间的时间差
- 不同配置下，由预取导致的平均每层停顿大小

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

## 3. 测试样本规模

本次固定使用数据集前 `2` 条请求，样本规模如下：

- 总输入 token 数：`44`
- 总输出 token 数：`738`
- 最大输入长度：`25`
- 最大输出长度：`619`

## 4. 本轮使用的配置

### 4.1 本地不卸载基线

- [`single_node_no_hbf_instance.json`](/d:/LLMServingSim/cluster_config/single_node_no_hbf_instance.json)

### 4.2 HBF 组

- [`single_node_hbf_instance.json`](/d:/LLMServingSim/cluster_config/single_node_hbf_instance.json)
- [`single_node_hbf_ffn075.json`](/d:/LLMServingSim/cluster_config/single_node_hbf_ffn075.json)
- [`single_node_hbf_ffn050.json`](/d:/LLMServingSim/cluster_config/single_node_hbf_ffn050.json)
- [`single_node_hbf_ffn025.json`](/d:/LLMServingSim/cluster_config/single_node_hbf_ffn025.json)
- [`single_node_hbf_ffn050_predict2ms.json`](/d:/LLMServingSim/cluster_config/single_node_hbf_ffn050_predict2ms.json)
- [`single_node_hbf_ffn050_predict5ms.json`](/d:/LLMServingSim/cluster_config/single_node_hbf_ffn050_predict5ms.json)

说明：

- 本轮所有 HBF 配置的 `hbf_mem.mem_bw` 已统一设置为 `768`
- 其他 HBF 参数维持各自配置设定不变

## 5. 指标说明

报告中使用以下指标：

- `运行时间`：程序输出的 `Total simulation time`
- `总时延`：程序输出的 `Total latency (s)`
- `首个 token 时间`：`Mean TTFT (ms)`
- `平均生成 token 时间`：`Mean TPOT (ms)`
- `平均 token 间隔`：`Mean ITL (ms)`
- `生成吞吐`：`Average generation throughput (tok/s)`
- `总吞吐`：`Total token throughput (tok/s)`
- `HBF 总传输量`：`HBF total transfer bytes`
- `HBF 总停顿`：`HBF stall time (ns)`
- `平均每层预取时间`：
  - `(HBF predict time + HBF transfer time) / HBF prefetched layers`
- `平均每层停顿时间差`：
  - `HBF stall time / HBF prefetched layers`
  - 这也是本报告里“每层预取和计算之间的时间差”的主要衡量指标

## 6. 测试结果

### 6.1 不同 HBF 配置下的性能

| 配置 | 运行时间 | 总时延(s) | Mean TTFT(ms) | Mean TPOT(ms) | Mean ITL(ms) | 生成吞吐(tok/s) | 总吞吐(tok/s) | HBF 总传输(bytes) | HBF 总停顿(ns) | 平均每层预取时间(ns) | 平均每层停顿时间差(ns) |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `HBF-1.0` | `0h 22m 1.101s` | 26.726 | 60.65 | 42.62 | 42.95 | 27.61 | 29.26 | 8370387943424 | 10937307842 | 569978 | 569978 |
| `HBF-0.75` | `0h 21m 52.017s` | 24.525 | 42.87 | 39.07 | 39.39 | 30.09 | 31.89 | 6680213454848 | 8736559810 | 455290 | 455290 |
| `HBF-0.50` | `0h 22m 54.998s` | 22.324 | 42.32 | 35.51 | 35.83 | 33.06 | 35.03 | 4990038966272 | 6535811778 | 340602 | 340602 |
| `HBF-0.25` | `0h 25m 36.120s` | 20.126 | 38.21 | 31.96 | 32.28 | 36.67 | 38.86 | 3299864477696 | 4335063746 | 225914 | 225914 |
| `HBF-0.50-P2ms` | `0h 24m 2.872s` | 60.600 | 141.67 | 97.33 | 97.66 | 12.18 | 12.90 | 4990038966272 | 44906136178 | 2340202 | 2340202 |
| `HBF-0.50-P5ms` | `0h 24m 5.544s` | 118.168 | 231.45 | 190.32 | 190.66 | 6.25 | 6.62 | 4990038966272 | 102473136178 | 5340202 | 5340202 |

### 6.2 相同配置下，本地不卸载与 HBF 卸载对比

| 策略 | 运行时间 | 总时延(s) | Mean TTFT(ms) | Mean TPOT(ms) | Mean ITL(ms) | 生成吞吐(tok/s) | 总吞吐(tok/s) | 总输出 token | 最大输出长度 | HBF 总传输(bytes) | 平均每层停顿时间差(ns) |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `本地不卸载` | `0h 1m 36.319s` | 15.901 | 33.13 | 25.12 | 25.45 | 46.41 | 49.18 | 738 | 619 | - | - |
| `HBF-1.0` | `0h 22m 1.101s` | 26.726 | 60.65 | 42.62 | 42.95 | 27.61 | 29.26 | 738 | 619 | 8370387943424 | 569978 |
| `HBF-0.50` | `0h 22m 54.998s` | 22.324 | 42.32 | 35.51 | 35.83 | 33.06 | 35.03 | 738 | 619 | 4990038966272 | 340602 |
| `HBF-0.25` | `0h 25m 36.120s` | 20.126 | 38.21 | 31.96 | 32.28 | 36.67 | 38.86 | 738 | 619 | 3299864477696 | 225914 |

## 7. 结果分析

### 7.1 HBF 带宽提高后的总体变化

与上一轮 `hbf_mem.mem_bw = 40` 的结果相比，本轮将 HBF 带宽提高到 `768` 后，HBF 组性能明显改善：

- HBF 总时延从“上百秒到两百多秒”下降到了“二十几秒”量级
- 首个 token 时间与平均 token 间隔也明显下降
- HBF-0.25 的总时延已接近本地不卸载基线

这说明：

- HBF 带宽是影响卸载策略性能的关键参数
- 在当前模型里，传输带宽改善会直接减少 stall，并显著改善端到端时延

### 7.2 不同 `ffn_ratio` 下的变化

当 HBF 带宽与 HBM 对齐后，`ffn_ratio` 对性能的影响依然清晰：

- `ffn_ratio` 从 `1.0` 降到 `0.25`
- HBF 总传输量从 `8370387943424` 降到 `3299864477696`
- 平均每层停顿从 `569978ns` 降到 `225914ns`
- 总时延从 `26.726s` 降到 `20.126s`
- 生成吞吐从 `27.61 tok/s` 升到 `36.67 tok/s`

这说明：

- FFN 稀疏传输仍然有效
- 在高带宽 HBF 下，降低 FFN 传输量依然能继续改善性能

### 7.3 不同 `predict` 时间下的变化

固定 `ffn_ratio = 0.5` 后：

- 基线 `HBF-0.50` 的平均每层停顿时间差是 `340602ns`
- `HBF-0.50-P2ms` 提升到 `2340202ns`
- `HBF-0.50-P5ms` 提升到 `5340202ns`

同时，总时延也对应上升：

- `22.324s` -> `60.600s` -> `118.168s`

说明：

- 预取控制路径上的 `predict` 时间已经真实进入关键路径
- stall 增长会直接拖慢总时延

### 7.4 每层预取与计算之间的时间差

本轮额外关注的“每层预取和计算之间的时间差”，在当前实现中可以直接用“平均每层停顿时间差”来理解。

从结果看：

- `HBF-1.0`：约 `0.570 ms / layer`
- `HBF-0.75`：约 `0.455 ms / layer`
- `HBF-0.50`：约 `0.341 ms / layer`
- `HBF-0.25`：约 `0.226 ms / layer`
- `HBF-0.50-P2ms`：约 `2.340 ms / layer`
- `HBF-0.50-P5ms`：约 `5.340 ms / layer`

结论很明确：

- `ffn_ratio` 越小，每层因预取造成的停顿越小
- `predict` 开销越大，每层因预取造成的停顿越大

### 7.5 本地不卸载与 HBF 卸载的对比

即使在 HBF 带宽已经提高到与 HBM 相同后，本地不卸载仍然是性能最优策略：

- 本地不卸载总时延：`15.901s`
- `HBF-1.0` 总时延：`26.726s`
- `HBF-0.50` 总时延：`22.324s`
- `HBF-0.25` 总时延：`20.126s`

但与上一轮相比，差距已经明显缩小：

- `HBF-0.25` 只比本地不卸载慢约 `1.27x`
- `HBF-0.50` 约慢 `1.40x`
- `HBF-1.0` 约慢 `1.68x`

这说明：

- 当 HBF 带宽足够高时，卸载策略不再像之前那样“显著拖慢”
- 在带宽受限解除后，HBF 卸载开始接近“可接受的性能退化”

## 8. 最终结论

### 8.1 关于不同 HBF 配置

- `ffn_ratio` 降低会减少 HBF 传输量、减少每层停顿并提升整体性能
- `predict` 时间升高会显著放大每层停顿，并拖慢总时延
- 本轮结果验证了 HBF prefetch、FFN 稀疏与 stall 模型在高带宽 HBF 下仍然成立

### 8.2 关于本地不卸载与 HBF 卸载

- 本地不卸载依旧是性能最佳方案
- 但当 HBF 带宽提升到与 HBM 相同后，HBF 卸载的性能已经明显改善
- `HBF-0.25` 已经接近本地不卸载的性能区间

### 8.3 关于额外要求中的“每层停顿”

- 本轮已经记录了不同配置下的平均每层停顿时间差
- 它可以直接用来衡量“预取相对计算造成了多大停顿”
- 在当前测试中，这一指标与总时延变化方向一致，具有良好的解释性

## 9. 建议的后续实验

- 固定 `ffn_ratio`，继续扫描更细粒度的 `predict` 参数
- 在 `hbf_mem.mem_bw = 768` 基础上继续提高或降低 HBF 时延，观察延迟敏感性
- 增加请求数与 batch 压力，观察高并发下 HBF 预取收益是否进一步变化
