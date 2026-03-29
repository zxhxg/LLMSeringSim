# Task 11：HBF Prefetch 目标层依赖修复

## 任务目标

- 修复 HBF prefetch 图中 `hbf_predict -> hbf_prefetch -> compute(next layer)` 依赖链没有真正进入 ET 图的问题。
- 解决“`stall` 指标变化，但总 `latency` 不变化”的核心错误。

## 修改文件

- `astra-sim/extern/graph_frontend/chakra/src/converter/llm_converter.py`

## 修改模块

- Chakra LLM converter

## 修改函数

- `LLMConverter.get_hbf_target_block`

## 问题现象

- 修复前，`hbf_predict` 节点会生成，但对应的 `hbf_prefetch` 内存节点父依赖为空。
- `input_layernorm` 也不会依赖这些 prefetch 节点。
- 因此 `predict` 时间只会体现在统计项 `hbf_stall_ns` 中，不会进入 ASTRA-Sim 的关键路径。

## 根因分析

- trace 最终写盘时，会把层名统一追加行号后缀，例如：
  - `hbf_pred_b1` 会变成 `hbf_pred_b1_13`
  - `hbf_pf_attn_b1` 会变成 `hbf_pf_attn_b1_14`
- 修复前的 `get_hbf_target_block()` 使用“按 `_` 分割后取第一个纯数字 token”的方式提取 block id。
- 对于上述层名，它提取到的是：
  - `13`
  - `14`
- 这些数字实际上是 trace 行号，不是目标 block id。
- 于是：
  - `pending_prefetch[target_block]["predict"]`
  - `pending_prefetch[target_block]["loads"]`
  - `current_block_idx`
  三者无法对齐，导致 prefetch 依赖链失效。

## 实现逻辑

1. 将 `get_hbf_target_block()` 改为基于层名前缀的精确正则匹配，而不是基于数字 token 猜测。
2. 同时兼容旧命名与短命名：
   - `hbf_predict_block_*`
   - `hbf_prefetch_attn_block_*`
   - `hbf_prefetch_ffn_block_*`
   - `hbf_pred_b*`
   - `hbf_pf_attn_b*`
   - `hbf_pf_ffn_b*`
3. 只提取真正的目标 block id，忽略最终 trace 自动追加的行号后缀。

## 修复后关键行为

- `hbf_pred_b1_13` 解析为 block `1`
- `hbf_pf_attn_b1_14` 解析为 block `1`
- `hbf_pf_ffn_b1_15` 解析为 block `1`
- 这样 `pending_prefetch[1]` 才能正确挂到 block 1 的 `input_layernorm` 上。

## 验证方式

### 1. 静态校验

- 本地执行 `python -m py_compile astra-sim/extern/graph_frontend/chakra/src/converter/llm_converter.py` 通过。

### 2. Docker 运行时校验

- 在容器中重新执行：

```bash
docker exec servingsim_docker bash -lc 'cd /app/LLMServingSim && bash ./compile.sh'
```

- 重新安装 Chakra 后，运行时加载的 `chakra.src.converter.llm_converter` 已包含新的正则解析逻辑。

### 3. ET 图依赖校验

修复后，首个 HBF prefetch 链路在 ET 图中的依赖如下：

- `COMP_NODE_hbf_pred_b1_13` parents=`[1]`
- `MEM_LOAD_NODE_hbf_pf_attn_b1_14_WEIGHT` parents=`[21]`
- `MEM_LOAD_NODE_hbf_pf_ffn_b1_15_WEIGHT` parents=`[21]`
- `COMP_NODE_input_layernorm_16` parents=`[20, 22, 23]`

这说明：

- prefetch 节点已经正确依赖 predict 节点
- 下一层 compute 已经正确依赖 prefetch 节点

## 影响范围

- 影响所有启用 HBF prefetch 的 dense Transformer trace。
- 不影响未启用 HBF 的原有路径。
- 不改变 FFN 稀疏比例、HBF 传输量或 HBF 统计口径，只修复依赖挂载错误。
