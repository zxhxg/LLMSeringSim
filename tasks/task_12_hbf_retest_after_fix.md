# Task 12：HBF 修复后参数复测

## 任务目标

- 在修复 HBF prefetch 目标层依赖后，重新验证：
  - 不同 `predict` 时间是否会推高端到端 `latency`
  - 不同 `ffn_ratio` 是否会继续正确影响传输量与时延

## 修改文件

- `tasks/task_12_hbf_retest_after_fix.md`

## 修改模块

- 无代码模块修改，本任务仅执行测试与记录。

## 修改函数

- 无

## 测试环境

- 容器：`servingsim_docker`
- 工作目录：`/app/LLMServingSim`
- network backend：`analytical`
- 数据集：`dataset/sharegpt_req100_rate10_llama.jsonl`
- 请求数：`2`

## 预备步骤

在容器中重新安装 Chakra 与编译 ASTRA-Sim：

```bash
docker exec servingsim_docker bash -lc 'cd /app/LLMServingSim && bash ./compile.sh'
```

## 测试用例

### 1. 固定 `ffn_ratio=0.5`，改变 `predict` 时间

- `cluster_config/single_node_hbf_ffn050.json`
- `cluster_config/single_node_hbf_ffn050_predict2ms.json`
- `cluster_config/single_node_hbf_ffn050_predict5ms.json`

### 2. 改变 FFN 传输量

- `cluster_config/single_node_hbf_ffn025.json`

## 运行命令

```bash
python3 main.py --cluster-config cluster_config/single_node_hbf_ffn050.json --fp 16 --block-size 16 --dataset dataset/sharegpt_req100_rate10_llama.jsonl --num-req 2 --log-interval 1.0 --log-level WARNING
python3 main.py --cluster-config cluster_config/single_node_hbf_ffn050_predict2ms.json --fp 16 --block-size 16 --dataset dataset/sharegpt_req100_rate10_llama.jsonl --num-req 2 --log-interval 1.0 --log-level WARNING
python3 main.py --cluster-config cluster_config/single_node_hbf_ffn050_predict5ms.json --fp 16 --block-size 16 --dataset dataset/sharegpt_req100_rate10_llama.jsonl --num-req 2 --log-interval 1.0 --log-level WARNING
python3 main.py --cluster-config cluster_config/single_node_hbf_ffn025.json --fp 16 --block-size 16 --dataset dataset/sharegpt_req100_rate10_llama.jsonl --num-req 2 --log-interval 1.0 --log-level WARNING
```

## 结果汇总

| 用例 | clocks (ns) | latency (s) | attn bytes | ffn bytes | total bytes | predict ns | transfer ns | stall ns |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `ffn_ratio=0.5` | 146978956876 | 146.979 | 1609689989120 | 3380348977152 | 4990038966272 | 7675600 | 124781672719 | 124789348319 |
| `ffn_ratio=0.5, predict=2ms/layer` | 184111528876 | 184.112 | 1609689989120 | 3380348977152 | 4990038966272 | 38378000000 | 124781672719 | 163159672719 |
| `ffn_ratio=0.5, predict=5ms/layer` | 239821771389 | 239.822 | 1609689989120 | 3380348977152 | 4990038966272 | 95945000000 | 124781672719 | 220726672719 |
| `ffn_ratio=0.25` | 104724586986 | 104.725 | 1609689989120 | 1690174488576 | 3299864477696 | 7675600 | 82527302829 | 82534978429 |

## 结果分析

### 1. `predict` 时间敏感性

- 在固定 `ffn_ratio=0.5` 时：
  - `predict ns` 从 `7675600` 提升到 `38378000000` 和 `95945000000`
  - `stall ns` 也同步从 `124789348319` 提升到 `163159672719` 和 `220726672719`
  - `latency` 从 `146.979s` 提升到 `184.112s` 和 `239.822s`

结论：

- 修复后，`predict` 时间已经真正进入关键路径。
- `stall` 增大不再只是统计项，而是会推高总时延。
- 这一结果符合设计的重叠与阻塞模型预期。

### 2. `ffn_ratio` 敏感性

- `ffn_ratio=0.25` 相比 `0.5`：
  - `HBF FFN transfer bytes` 从 `3380348977152` 降到 `1690174488576`
  - `HBF total transfer bytes` 从 `4990038966272` 降到 `3299864477696`
  - `stall ns` 从 `124789348319` 降到 `82534978429`
  - `latency` 从 `146.979s` 降到 `104.725s`

结论：

- FFN 稀疏传输的建模结果依旧保持正确。
- Attention 传输量不变，FFN 传输量按比例缩放，总时延随之下降，符合预期。

## 最终判断

- 修复前：
  - `stall` 会变，但 `latency` 不变，不符合严格时间模型预期。
- 修复后：
  - `predict`、`stall`、`latency` 三者变化方向一致。
  - `ffn_ratio`、传输量、`stall`、`latency` 之间的关系也继续保持正确。

因此可以判断：

- 本次错误已经修复。
- HBF prefetch 的关键依赖链已正确进入仿真图。
- 当前测试结果整体符合预期。
