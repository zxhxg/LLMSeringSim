# LLMServingSim 2.0：面向异构与解耦式 LLM 服务基础设施的统一模拟器

## 当前版本：**v1.0.0**（2026-02-25）

### 亮点

- `llm_profile` 已扩展以支持 MoE 架构（Mixtral-8x7B、Phi-mini-MoE）和 TPU-v6e-1；基于 scikit-learn 的注意力时延预测器替代了表格式查找，从而在不同 batch 大小与序列长度下获得更高精度
- 支持多实例仿真，可配置请求路由策略（Round Robin、Random、Custom），并支持在独立的 prefill 与 decode 实例之间进行 Prefill/Decode（P/D）解耦
- 支持带有跨 NPU expert parallelism 和专家卸载到 CPU 或 CXL 内存的 MoE 仿真，并可配置专家路由策略（Round Robin、Random、Fast、Custom）
- 通过 RadixAttention 实现前缀缓存，并可选择在 CPU 与 CXL 内存之间启用二级前缀池（`--enable-prefix-caching`、`--enable-prefix-sharing`、`--prefix-storage`）
- 支持子批交织（sub-batch interleaving）以实现 XPU 与 PIM 计算重叠（`--enable-sub-batch-interleaving`）
- 提供节点级功耗与能耗建模，覆盖 NPU、CPU、DRAM、互连、NIC 和存储
- 支持 CXL 内存扩展，并可配置多级内存带宽与时延
- 提供逐请求时延指标：TTFT、TPOT 与 ITL，并支持 p99 分位统计

完整变更日志见[此处](CHANGELOG.md)。

## 构建 LLMServingSim

### 1. Git 克隆

```bash
git clone --recurse-submodules https://github.com/casys-kaist/LLMServingSim.git
cd LLMServingSim
```

### 2. 启动 Docker

这一步会配置并启动 Docker 环境。详见 `docker.sh`。

```bash
./docker.sh
```

### 3. 构建 ASTRA-Sim 和 Chakra

这一步会编译 ASTRA-Sim（analytical backend）并安装 Chakra。详见 `compile.sh`。

```bash
./compile.sh
```

## 运行 LLMServingSim

### 1. 设置输入配置

LLMServingSim 的所有配置均由 `inference_serving/config_builder.py` 基于 `cluster_config` 文件自动生成。

`cluster_config` 文件用于指定节点拓扑、实例布局、硬件类型、内存层级以及互连参数，同时也支持针对权重、KV cache 和 experts 的逐层放置规则，以及启用 PIM 的设备配置。

**配置路径：**
- 集群配置：`cluster_config/{config_name}.json`
- 逻辑拓扑配置 **（仅 ns3 backend）**：`astra-sim/inputs/logical_topology/{topology_name}.json`

**数据集路径：**
- 数据集：`dataset/{dataset_name}.jsonl`
- 运行时生成的 trace：`astra-sim/inputs/trace/`

示例配置见 `cluster_config/`，配置格式说明见 `cluster_config/README.md`。

### 2. 运行 LLMServingSim

测试运行：

```bash
python main.py \
    --cluster-config 'cluster_config/single_node_single_instance.json' \
    --fp 16 --block-size 16 \
    --dataset 'dataset/sharegpt_req100_rate10_llama.jsonl' \
    --output 'output/example_single_run.csv' \
    --num-req 100 --log-interval 1.0
```

更多示例见 `run.sh`，其中覆盖多实例、P/D 解耦、MoE、前缀缓存、CXL 内存、PIM、功耗建模以及子批交织等场景：

```bash
./run.sh
```

## `main.py` 的参数

当前版本支持如下模型与硬件：

**模型：** `meta-llama/Llama-3.1-8B`、`meta-llama/Llama-3.1-70B`、`microsoft/Phi-mini-MoE-instruct`、`mistralai/Mixtral-8x7B-v0.1`

**硬件：** `A6000`、`H100`、`TPU-v6e-1`

可以使用附带的 profiler 扩展新模型和新硬件。详见[添加新模型与硬件](#添加新模型与硬件)。

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `--cluster-config` | `single_node_single_instance.json` | 节点级与实例级配置 |
| `--max-batch` | `0` | 最大 batch 大小；`0` 表示不设上限 |
| `--max-num-batched-tokens` | `2048` | 单次迭代处理的最大 token 数 |
| `--fp` | `16` | 浮点精度位数 |
| `--request-routing-policy` | `RR` | 跨实例请求路由策略（`RR`、`RAND`、`CUSTOM`） |
| `--expert-routing-policy` | `FAST` | MoE 的 expert token 路由策略（`RR`、`RAND`、`FAST`、`CUSTOM`） |
| `--enable-prefix-caching` | `False` | 通过 RadixAttention 启用前缀缓存 |
| `--enable-prefix-sharing` | `False` | 启用二级前缀缓存池化 |
| `--prefix-storage` | `None` | 二级前缀池的存储层级（`None`、`CPU`、`CXL`） |
| `--enable-local-offloading` | `False` | 启用权重卸载到本地内存 |
| `--enable-attn-offloading` | `False` | 启用将注意力计算卸载到 PIM |
| `--enable-sub-batch-interleaving` | `False` | 启用子批交织以实现 XPU/PIM 重叠 |
| `--enable-attn-prediction` | `False` | 启用实时注意力时延预测 |
| `--prioritize-prefill` | `False` | 在调度中优先处理 prefill 请求 |
| `--block-size` | `16` | KV cache block 大小（单位：token） |
| `--dataset` | `None` | `.jsonl` 数据集路径；若为 `None`，则在 `main.py` 中手动添加请求 |
| `--output` | `None` | 逐请求 CSV 输出路径；若为 `None`，仅输出到 stdout |
| `--gen` | `True` | 设为 `False` 可跳过初始化（prefill）阶段 |
| `--num-req` | `100` | 要模拟的请求数量 |
| `--log-interval` | `0.5` | 吞吐日志记录间隔（秒） |
| `--log-level` | `WARNING` | 日志详细级别（`WARNING`、`INFO`、`DEBUG`） |
| `--network-backend` | `analytical` | 网络仿真后端（`analytical`、`ns3`） |

## `main.py` 的输出

### 1. 标准输出

模拟器通过可配置的 logger 报告运行时信息。它会记录每次迭代处理了哪些请求，并周期性汇报吞吐、内存使用和功耗。

将 `--log-level` 调整为 `INFO` 或 `DEBUG` 可启用更详细的输出，包括逐层内存加载与存储活动。

### 2. 输出文件

`{output_path}.csv` 包含逐请求时延指标。示例见 `output/example_run.csv`。

## 添加新模型与硬件

### 1. 构建性能模型

LLMServingSim 使用 `llm_profile/` 中基于 PyTorch 的 profiler，为给定硬件目标生成逐层时延、注意力时延和功耗模型。profile 完成后，创建一个引用新硬件名称的 cluster config，即可像平常一样运行 `main.py`。

完整 profiling 说明见 [`llm_profile/README.md`](llm_profile/README.md)。

### 2. 修改模拟器函数（可选）

当前版本支持基于 Llama 的模型架构。若目标模型偏离该架构，可能需要修改以下内容：

**`inference_serving/memory_model.py`**：函数 `calculate_sizes` 和 `get_weight`

`calculate_sizes` 计算各层类型的输入、权重和输出张量大小。`get_weight` 基于 `calculate_sizes` 聚合整个模型大小。
请根据目标模型架构对其进行修改。

**`inference_serving/trace_generator.py`**：函数 `synthesize_trace`

该函数通过按照模型架构堆叠各层来构造逐迭代执行 trace。修改时请确保：

- ATTENTION 层能够按请求正确拆分
- 第 *i* 层的输出大小与第 *i+1* 层的输入大小一致
- ALLREDUCE 操作在 tensor parallel 同步场景下被正确放置

## 评测

[`evaluation/`](evaluation/) 目录包含论文中 Figure 5 至 Figure 10 的 artifact evaluation 流程，其中包括各图对应的 shell 脚本、绘图代码、处理后的参考输入，以及保存在 `evaluation/artifacts/` 下的示例输出快照。

在运行 artifact evaluation 之前，请先完成上述环境准备步骤（`./docker.sh` 和 `./compile.sh`），并在该环境内执行评测命令。

先进入 `evaluation/`：

```bash
cd evaluation
```

运行单张图：

```bash
bash figure_5.sh
bash figure_6.sh
bash figure_7.sh
bash figure_8.sh
bash figure_9.sh
bash figure_10.sh
```

一次性复现实验全集：

```bash
bash run_all.sh
```

对比生成的 parsed 输出与保留的 artifact 快照：

```bash
# 对比所有图（5-10）
bash compare.sh
# 对比单张图
bash compare.sh 5
# 对比多张指定图
bash compare.sh 5 7 9
# 等价的单图写法
bash compare.sh figure_5
```

在进行可视化验证时，请将生成的 PDF 与各图目录中的对应 `*_ref.pdf` 文件进行比对。

更详细的目录结构、参考结果比对说明和各图说明见 [`evaluation/README.md`](evaluation/README.md)。

## 论文发表

**ISPASS 2026**  
*LLMServingSim 2.0: A Unified Simulator for Heterogeneous and Disaggregated LLM Serving Infrastructure*  
Jaehong Cho<sup>\*</sup>, Hyunmin Choi<sup>\*</sup>, Guseul Heo, Jongse Park (KAIST) [[Paper]]()（待发表）  
<sup>\*</sup>共同一作  
[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.18879965.svg)](https://doi.org/10.5281/zenodo.18879965)

**CAL 2025**  
*LLMServingSim2.0: A Unified Simulator for Heterogeneous Hardware and Serving Techniques in LLM Infrastructure*  
Jaehong Cho, Hyunmin Choi, Jongse Park (KAIST) [[Paper]](https://doi.org/10.1109/LCA.2025.3628325)

**IISWC 2024**  
*LLMServingSim: A HW/SW Co-Simulation Infrastructure for LLM Inference Serving at Scale*  
Jaehong Cho, Minsu Kim, Hyunmin Choi, Guseul Heo, Jongse Park (KAIST) [[Paper]](https://doi.org/10.1109/IISWC63097.2024.00012)  
[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.12803583.svg)](https://doi.org/10.5281/zenodo.12803583)

## 引用

如果你在研究中使用了 LLMServingSim，请引用：

```bibtex
@ARTICLE{11224567,
    author={Cho, Jaehong and Choi, Hyunmin and Park, Jongse},
    journal={IEEE Computer Architecture Letters},
    title={{LLMServingSim2.0: A Unified Simulator for Heterogeneous Hardware and Serving
            Techniques in LLM Infrastructure}},
    year={2025},
    volume={24},
    number={02},
    pages={361-364},
    doi={10.1109/LCA.2025.3628325},
    ISSN={1556-6064},
    publisher={IEEE Computer Society},
    address={Los Alamitos, CA, USA},
    month=jul
}

@INPROCEEDINGS{10763697,
    author={Cho, Jaehong and Kim, Minsu and Choi, Hyunmin and Heo, Guseul and Park, Jongse},
    booktitle={2024 IEEE International Symposium on Workload Characterization (IISWC)},
    title={{LLMServingSim: A HW/SW Co-Simulation Infrastructure for LLM Inference Serving
            at Scale}},
    year={2024},
    pages={15-29},
    doi={10.1109/IISWC63097.2024.00012}
}
```
