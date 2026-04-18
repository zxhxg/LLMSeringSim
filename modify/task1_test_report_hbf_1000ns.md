# Task 1 Retest Report: HBF `mem_latency = 1000ns`

## 1. 本轮修改

本轮仅修改 3 个 HBF 配置文件中的 `hbf_mem.mem_latency`：

- `cluster_config/single_node_hbf_shared_frontend.json`
- `cluster_config/single_node_hbf_fully_independent.json`
- `cluster_config/single_node_hbf_fully_serialized.json`

变更内容：

- `mem_latency: 50 -> 1000`

其余字段保持不变：

- `mem_size = 1024`
- `mem_bw = 1536`
- `num_devices = 1`
- `placement = weights: "hbf:0"`
- `bw_mode` 保持原值
- CPU / NPU 配置保持不变

单位判断沿用当前实现与已有日志口径，按 `ns` 解释。因此本轮测试等价于将单次 HBF 访问固定时延从 `50ns` 提升到 `1000ns`。

## 2. 测试条件

四组实验均使用与上一轮 Task 1 相同的参数：

- 数据集：`dataset/sharegpt_req100_rate10_llama.jsonl`
- `--fp 16`
- `--block-size 16`
- `--num-req 100`
- `--log-interval 1.0`
- `--log-level WARNING`
- 网络后端：`analytical`

输出文件全部新增，不覆盖上一轮 `50ns` 结果：

- `output/task1_hbf1000_shared_frontend.csv`
- `output/task1_hbf1000_fully_independent.csv`
- `output/task1_hbf1000_fully_serialized.csv`
- `output/task1_hbf1000_memory_control.csv`

## 3. 本轮复测结果

### 配置 A: HBM + HBF `shared_frontend`

- 运行成功：是
- 启动日志确认：`HBF config: size=1024GB, bw=1536GB/s, latency=1000ns, devices=1, bw_mode=shared_frontend`
- 关键指标
  - `Total latency (s): 35.666`
  - `Request throughput (req/s): 2.80`
  - `Total token throughput (tok/s): 1243.94`
  - `HBF read bytes (MB): 12666751.96`
  - `HBF read requests: 240657`
  - `HBF modeled read time (us): 16347151.04`

### 配置 B: HBM + HBF `fully_independent`

- 运行成功：是
- 启动日志确认：`HBF config: size=1024GB, bw=1536GB/s, latency=1000ns, devices=1, bw_mode=fully_independent`
- 关键指标
  - `Total latency (s): 28.726`
  - `Request throughput (req/s): 3.48`
  - `Total token throughput (tok/s): 1544.46`
  - `HBF read bytes (MB): 13355994.81`
  - `HBF read requests: 253752`
  - `HBF modeled read time (us): 8745134.53`

### 配置 C: HBM + HBF `fully_serialized`

- 运行成功：是
- 启动日志确认：`HBF config: size=1024GB, bw=1536GB/s, latency=1000ns, devices=1, bw_mode=fully_serialized`
- 关键指标
  - `Total latency (s): 42.565`
  - `Request throughput (req/s): 2.35`
  - `Total token throughput (tok/s): 1042.30`
  - `HBF read bytes (MB): 12283839.27`
  - `HBF read requests: 233382`
  - `HBF modeled read time (us): 23662715.67`

### 配置 D: 基准组 `single_node_memory_instance.json`

- 运行成功：是
- 启动日志确认：`HBF enabled: False`
- 关键指标
  - `Total latency (s): 28.226`
  - `Request throughput (req/s): 3.54`
  - `Total token throughput (tok/s): 1571.81`

## 4. 与 50ns 版本对比

上一轮 `50ns` 结果来自 `modify/task1_test_report.md`，对应关键指标如下：

| Mode | Latency 50ns (s) | Latency 1000ns (s) | Delta (s) | Token TP 50ns | Token TP 1000ns | Delta | HBF read time 50ns (us) | HBF read time 1000ns (us) | Delta (us) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| fully_independent | 28.725 | 28.726 | +0.001 | 1544.51 | 1544.46 | -0.05 | 8504070.13 | 8745134.53 | +241064.40 |
| shared_frontend | 35.665 | 35.666 | +0.001 | 1243.96 | 1243.94 | -0.02 | 16118526.89 | 16347151.04 | +228624.15 |
| fully_serialized | 42.565 | 42.565 | +0.000 | 1042.32 | 1042.30 | -0.02 | 23441002.77 | 23662715.67 | +221712.90 |
| baseline | 28.226 | 28.226 | +0.000 | 1571.81 | 1571.81 | +0.00 | N/A | N/A | N/A |

补充观察：

- 三个 HBF 模式下，`HBF read bytes` 与 `HBF read requests` 本轮与上一轮保持一致。
- 因此，这次变化几乎完全来自“每次 HBF 读取的固定 latency 增大”，而不是访问次数或访问字节数变化。

## 5. 横向分析

### 5.1 三种 `bw_mode` 的排序是否改变

没有改变，时延关系仍然保持：

- `fully_independent (28.726s) < shared_frontend (35.666s) < fully_serialized (42.565s)`

吞吐关系也保持不变：

- `fully_independent (1544.46 tok/s) > shared_frontend (1243.94 tok/s) > fully_serialized (1042.30 tok/s)`

这说明将 `mem_latency` 从 `50ns` 调到 `1000ns` 后，没有改变三种架构模式的相对优劣顺序。

### 5.2 与基准组相比的额外代价

与本轮 baseline (`28.226s`, `1571.81 tok/s`) 相比：

- `fully_independent`
  - 时延额外增加 `+0.500s`
  - token throughput 下降约 `-27.35 tok/s`
- `shared_frontend`
  - 时延额外增加 `+7.440s`
  - token throughput 下降约 `-327.87 tok/s`
- `fully_serialized`
  - 时延额外增加 `+14.339s`
  - token throughput 下降约 `-529.51 tok/s`

因此在 `1000ns` 条件下：

- 最接近 baseline 的仍然是 `fully_independent`
- 最悲观的仍然是 `fully_serialized`

## 6. 纵向分析

### 6.1 为什么 HBF modeled read time 明显上升，但总时延几乎没变

本次将单次 HBF 读取的固定 latency 从 `50ns` 增加到 `1000ns`，等于每次读取额外增加：

- `950ns`

而三种模式对应的 HBF 读请求数分别为：

- `fully_independent`: `253752`
- `shared_frontend`: `240657`
- `fully_serialized`: `233382`

因此仅固定时延项增加的总量约为：

- `253752 * 950ns ≈ 0.241s`
- `240657 * 950ns ≈ 0.229s`
- `233382 * 950ns ≈ 0.222s`

这与本轮 `HBF modeled read time` 的增量完全吻合：

- `fully_independent`: `+241064.40 us`
- `shared_frontend`: `+228624.15 us`
- `fully_serialized`: `+221712.90 us`

也就是说，本轮变化符合模型预期，而且主要体现在 HBF 访问时间统计项里。

### 6.2 为什么总时延只增加了约 0.001s

虽然 HBF modeled read time 增加了约 `0.22s ~ 0.24s`，但整轮仿真总时延几乎不变，只在千分之一秒量级波动。这说明：

1. 当前 `50ns -> 1000ns` 的增量相对于整轮执行中的总计算、调度和已有带宽惩罚仍然较小。
2. 现有 HBF 建模中，主导差异的仍然是 `bw_mode` 对带宽前端关系的影响，而不是单次读取固定 latency。
3. 从结果看，当前模型对 HBF latency 的敏感性存在，但不强；它会稳定推高 `HBF modeled read time`，却不会显著改变端到端吞吐排序。

## 7. 结论

本轮将 HBF `mem_latency` 从 `50ns` 提升到 `1000ns` 后，可以得到三个直接结论：

1. 三种 HBF 模式的性能排序没有变化，`fully_independent` 仍然最好，`fully_serialized` 仍然最差。
2. 增大的固定 HBF latency 会按“请求数 × 950ns”的方式稳定推高 `HBF modeled read time`，这一点与模型完全一致。
3. 在当前工作负载和建模方式下，HBF latency 敏感性是可观测但不强的，影响更多体现在 HBF 内部统计项，而不是显著改变端到端总时延和吞吐。
