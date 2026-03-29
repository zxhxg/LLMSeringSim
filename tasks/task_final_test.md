# Task Final：Docker 测试记录

## 测试目标

在 Docker 容器 `servingsim_docker` 中对比 HBF 配置下两组参数：

- `ffn_ratio = 1.0`
- `ffn_ratio < 1.0`（本次准备使用 `0.5`）

预期输出：

- `latency`
- `stall`
- `transfer bytes`

## 测试环境

- 容器：`servingsim_docker`
- 工作目录：`/app/LLMServingSim`
- network backend：`analytical`
- 数据集：`dataset/sharegpt_req100_rate10_llama.jsonl`
- 请求数：`2`

## 已执行步骤

1. 在容器中重新编译当前代码：

```bash
docker exec servingsim_docker bash -lc 'cd /app/LLMServingSim && bash ./compile.sh'
```

2. 运行 `ffn_ratio = 1.0` 用例：

```bash
docker exec servingsim_docker bash -lc 'cd /app/LLMServingSim && python3 main.py --cluster-config cluster_config/single_node_hbf_instance.json --fp 16 --block-size 16 --dataset dataset/sharegpt_req100_rate10_llama.jsonl --num-req 2 --log-interval 1.0 --log-level WARNING'
```

3. 检查容器内是否有残留进程：

```bash
docker exec servingsim_docker bash -lc 'ps -ef | grep -E "python3 main.py|chakra/src/converter|AstraSim_Analytical" | grep -v grep || true'
```

结果：未发现残留的 `main.py` / ASTRA-Sim 进程。

## 错误描述

测试未能进入指标对比阶段。运行 `ffn_ratio = 1.0` 用例时，Chakra 的 LLM converter 在解析生成的 trace 文本时抛出异常：

```text
ValueError: invalid literal for int() with base 10: 'LOCAL'
ValueError: Cannot parse the following layer -- "hbf_prefetch_attn_block_10_1490              LOCAL          0              HBF:0          83886080       LOCAL          0              NONE           0              HBF_PREFETCH"
```

由于第一组用例已经失败，第二组 `ffn_ratio = 0.5` 未继续执行，因此本次没有可用的 `latency / stall / transfer bytes` 对比结果。

## 复现步骤

1. 确保容器 `servingsim_docker` 已启动。
2. 在容器内执行 `bash ./compile.sh`，编译 Chakra 与 ASTRA-Sim。
3. 运行：

```bash
python3 main.py --cluster-config cluster_config/single_node_hbf_instance.json --fp 16 --block-size 16 --dataset dataset/sharegpt_req100_rate10_llama.jsonl --num-req 2 --log-interval 1.0 --log-level WARNING
```

4. 观察 Chakra converter 输出，即可稳定复现上面的 `ValueError`。

## 原因分析

- HBF 预取伪层名称较长，例如：`hbf_prefetch_attn_block_10_1490`。
- trace 文本使用固定宽度格式化输出，`Layername` 列宽当前为 `30`。
- 当 block 编号和 trace 行号变大时，层名长度超过 `30`，会把后续的 `comp_time` 列直接挤压到层名后面，导致字段边界丢失。
- Chakra `Layer.__init__()` 使用 `line.strip().split()` 解析列；在字段边界被破坏后，`col[1]` 变成了 `LOCAL`，从而在 `int(col[1])` 处报错。
- 该错误发生在 trace 转 ET 图阶段，因此测试流程在进入 ASTRA-Sim 指标汇总之前就中断了。

## 建议修改模块

- `inference_serving/utils.py`
  - 调整 `formatter()` / `_FMT` 的列宽，或改为更稳健的分隔符格式。
- `inference_serving/trace_generator.py`
  - 缩短 `hbf_predict_*` / `hbf_prefetch_*` 的伪层命名，避免超过列宽。
- `astra-sim/extern/graph_frontend/chakra/src/converter/llm_converter.py`
  - 为 trace 行解析增加更稳健的容错逻辑，避免因固定宽度文本溢出而直接失败。

## 结论

- Docker 编译成功。
- 最终测试失败，失败点已经稳定复现。
- 按约束，本任务不在测试阶段修改代码；建议由新会话基于上述模块继续修复。

## 修复后复测

### 复测前置说明

- 已在后续实现任务中修复 trace 列宽溢出、HBF 伪层命名过长以及 Chakra 依赖回溯错误。
- 复测仍在同一容器 `servingsim_docker` 内完成，并重新执行编译。

### 新增修复任务

- `tasks/task_7_trace_format_fix.md`
- `tasks/task_8_converter_parser_hardening.md`
- `tasks/task_9_converter_dependency_fix.md`

### 复测命令

1. 重新编译：

```bash
docker exec servingsim_docker bash -lc 'cd /app/LLMServingSim && bash ./compile.sh'
```

2. 运行 `ffn_ratio = 1.0`：

```bash
docker exec servingsim_docker bash -lc 'cd /app/LLMServingSim && python3 main.py --cluster-config cluster_config/single_node_hbf_instance.json --fp 16 --block-size 16 --dataset dataset/sharegpt_req100_rate10_llama.jsonl --num-req 2 --log-interval 1.0 --log-level WARNING > /tmp/hbf_run_10.log 2>&1; echo EXIT:$?'
```

3. 运行 `ffn_ratio = 0.5`：

```bash
docker exec servingsim_docker bash -lc 'cd /app/LLMServingSim && python3 main.py --cluster-config tmp_hbf_ffn05.json --fp 16 --block-size 16 --dataset dataset/sharegpt_req100_rate10_llama.jsonl --num-req 2 --log-interval 1.0 --log-level WARNING > /tmp/hbf_run_05.log 2>&1; echo EXIT:$?'
```

### 复测结果

两组用例均执行成功，命令返回 `EXIT:0`。

#### `ffn_ratio = 1.0`

- `Total latency (s)`: `384.716`
- `HBF attention transfer bytes`: `1609689989120`
- `HBF FFN transfer bytes`: `6760697954304`
- `HBF total transfer bytes`: `8370387943424`
- `HBF predict time (ns)`: `7675600`
- `HBF transfer time (ns)`: `209290393310`
- `HBF stall time (ns)`: `209298068910`
- `HBF prefetched layers`: `19189`
- `HBF stall layers`: `19189`

#### `ffn_ratio = 0.5`

- `Total latency (s)`: `301.411`
- `HBF attention transfer bytes`: `1609689989120`
- `HBF FFN transfer bytes`: `3380348977152`
- `HBF total transfer bytes`: `4990038966272`
- `HBF predict time (ns)`: `7675600`
- `HBF transfer time (ns)`: `124781672719`
- `HBF stall time (ns)`: `124789348319`
- `HBF prefetched layers`: `19189`
- `HBF stall layers`: `19189`

### 对比结论

- `ffn_ratio = 0.5` 时，`HBF FFN transfer bytes` 从 `6760697954304` 下降到 `3380348977152`，下降 `50%`，符合 `full_size × ffn_ratio` 预期。
- `HBF attention transfer bytes` 保持不变，说明 Attention 仍按全量传输建模。
- `HBF total transfer bytes` 从 `8370387943424` 下降到 `4990038966272`，减少 `3380348977152`，降幅约 `40.38%`。
- `HBF stall time (ns)` 从 `209298068910` 下降到 `124789348319`，减少 `84508720591`，降幅约 `40.38%`。
- `Total latency (s)` 从 `384.716` 下降到 `301.411`，减少 `83.305s`，降幅约 `21.65%`。
- 两组的 `HBF prefetched layers` 与 `HBF stall layers` 相同，说明当前 trace 路径下每个被预取层都仍然发生了 stall，但 stall 持续时间随 FFN 稀疏传输量下降而缩短。

### 最终结论

- 修复后，HBF 分层存储、FFN 稀疏加载、prefetch overlap 与 stall 统计链路已经可以在 Docker 环境中完整跑通。
- 测试结果验证了 `ffn_ratio` 对 FFN 传输量、总传输量、stall 与总时延的影响方向正确。
