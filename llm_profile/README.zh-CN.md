# llm_profile

这是一个基于 PyTorch 的 profiling 工具，用于测量 LLM 层时延、注意力时延以及 GPU/系统级功耗。其输出会被 LLMServingSim 用作性能模型和功耗模型。

如果要为 LLMServingSim 支持新的模型或硬件目标，请按以下步骤操作。另请参阅顶层 README 中的 [Adding a New Model & Hardware](../README.md#adding-a-new-model--hardware) 一节。

## 概述

`llm_profile` 会从 Hugging Face 加载模型，并在关键层中插入 PyTorch profiler hooks，以测量 GPU 上的执行时间。它支持 dense 和 MoE 架构，并生成逐层时延 CSV 以及基于 scikit-learn 的注意力时延预测器。GPU 和系统级功耗通过 `nvidia-smi` 与 `ipmitool` 测量，其结果会被纳入 LLMServingSim 的功耗模型。

## 用法

### 1. 环境

请在提供的 Docker 容器中，或原生的 PyTorch + CUDA 环境中运行：

```bash
./docker.sh
```

对于需要访问授权的模型（例如 LLaMA），请按 `docker.sh` 中的说明提供你的 Hugging Face token。

### 2. 对层和注意力进行 profiling

```bash
./profile_layers.sh    # 测量非注意力层的计算时延
./profile_attn.sh      # 在不同 batch 大小和序列长度下测量注意力时延
```

若要减少 profiling 时间和内存占用，可在相应 profiling 脚本中通过 `--num-layer` 减少层数。

### 3. 测量功耗（可选）

对于功耗测量，我们在 `profiler/power/` 下提供了示例脚本，使用 `nvidia-smi` 测量 GPU 功耗，使用 `ipmitool` 测量系统级功耗：

```bash
./profiler/power/profile_gpu_power.sh      # 通过 nvidia-smi 测量 GPU 功耗
./profiler/power/profile_server_power.sh   # 通过 ipmitool 测量系统级功耗
```

当提供启用了 power 设置的 cluster config 时（例如 `cluster_config/single_node_power_instance.json`），LLMServingSim 的功耗模型会使用这些功耗 profiling 结果。

### 4. 构建注意力预测器

```bash
./build_predictor.sh
```

该步骤会基于 profile 得到的注意力数据训练一个 scikit-learn 模型，以支持仿真过程中的实时时延预测（`--enable-attn-prediction`）。预测器覆盖的推理空间可通过 `--max-batch` 和 `--max-len` 进行控制。

## 输出结构

结果将写入：

```
perf_models/{hardware}/{model}/tp{tp_size}/
  layers.csv                              # 逐层计算时延
  attention.csv                           # 按 (batch_size, seq_len) 组织的注意力时延
  predictions/
    attn_decode_predictions.csv           # decode 注意力的预测器输出
    attn_prefill_predictions.csv          # prefill 注意力的预测器输出
```

这些文件会在运行时被 LLMServingSim 自动加载。

## 支持的模型

模型相关的 profiling 代码位于 `models/`：

- `llama.py`：Llama 架构（Llama-3.1-8B、Llama-3.1-70B）
- `mixtral.py`：Mixtral-8x7B（MoE）
- `phimoe.py`：Phi-mini-MoE-instruct（MoE）

## 添加新模型或硬件

1. 参照现有示例，在 `models/` 中新增模型 profiling 脚本。
2. 在 profiling shell 脚本中设置目标硬件名称和模型标识符。
3. 运行上述 profiling 和 predictor 构建步骤。
4. 创建一个引用新硬件名称的 `cluster_config` 条目。
