# Evaluation README

## 概述

该目录包含 LLMServingSim 2.0 论文中 Figure 5 到 Figure 10 的 artifact evaluation 流程。可运行和编辑的是各个工作目录 `figure_*` 文件夹。它们包含已提交的配置、参考输入、绘图代码和参考 PDF。当你运行每个 figure 脚本时，`logs/`、`results/` 和 `parsed/` 等运行时输出会在这些文件夹中生成。`artifacts/` 文件夹则保存了先前生成输出的冻结副本，用于对比。

关于每张图的具体说明，例如图的目标、坐标轴定义、参考输入、生成的 TSV 文件以及预期的 PDF，请查看各个 `figure_X/` 文件夹中的 `README.md`。

## 目录说明

- `fonts/`：绘图脚本使用的本地字体。
- `parser/`：用于将日志转换为 TSV 的解析器，涵盖吞吐、功耗、内存、时延、仿真时间和能耗拆分。
- `figure_5.sh` 到 `figure_10.sh`：逐图复现实验脚本。
- `figure_5/` 到 `figure_10/`：各图专属的配置、参考输入、绘图脚本和 `*_ref.pdf` 可视化参考。
- `artifacts/`：先前运行保留下来的输出，包括生成的 `logs/`、`results/`、`parsed/` 以及图形 PDF。

在每个工作用的 `figure_*` 文件夹中：

- `config/`：该图脚本所使用的 cluster config。
- `reference/`：作为对比基线的真实系统或既有工作数据。
- `figure_X.py`：绘图代码。
- `figure_X_ref.pdf` 或 `figure_Xa_ref.pdf`：用于可视化对比的参考 PDF。

`figure_5/` 按硬件划分，因此其已提交输入保存在 `A6000/` 和 `H100/` 下。

## 结构

```text
evaluation/
├── README.md
├── fonts/
├── parser/
├── run_all.sh
├── figure_5.sh ... figure_10.sh
├── figure_5/
│   ├── A6000/{config,reference}/
│   ├── H100/{config,reference}/
│   ├── figure_5.py
│   └── figure_5_ref.pdf
├── figure_6/
│   ├── config/
│   ├── reference/
│   ├── figure_6.py
│   └── figure_6a_ref.pdf, figure_6b_ref.pdf, figure_6c_ref.pdf
├── figure_7/ ... figure_10/
└── artifacts/
    └── figure_5/ ... figure_10/
```

运行 figure 脚本时，会在已提交输入旁边创建当前图目录下的 `logs/`、`results/` 和 `parsed/` 子目录。

## 运行评测

在 `evaluation/` 目录下运行单张图：

```bash
bash figure_5.sh
```

运行全部图的流程：

```bash
bash run_all.sh
```

这些脚本已经会调用 `main.py`、所需的 parser 以及对应图的绘图脚本。大多数数据集路径都定义在各 shell 脚本顶部附近。如果你的数据集存放在其他位置，请在运行前更新这些变量。

## 与参考结果对比

### 1）脚本对比

在 `evaluation/` 目录下使用 compare 脚本：

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

该脚本会将生成的 parsed TSV 输出与 `evaluation/artifacts/` 中为 Figure 5 到 Figure 10 保留的快照进行对比。

Figure 8 说明：`*_sim_time.tsv` 总是会被检查并报告，但仿真时间差异被视为符合预期的、与硬件相关的波动，不会导致 compare 结果失败。

### 2）可视化对比

进行可视化验证时，请将生成的 PDF 与各图文件夹中对应的 `*_ref.pdf` 文件进行比较。

每张图的具体对比目标和结果解释，请参见各个 `figure_X/README.md`。

## 图表索引

- [`figure_5/README.md`](figure_5/README.md)：针对 RTX A6000 和 H100 的 GPU 吞吐验证。
- [`figure_6/README.md`](figure_6/README.md)：服务器功耗轨迹与能耗拆分。
- [`figure_7/README.md`](figure_7/README.md)：内存使用与前缀命中率验证。
- [`figure_8/README.md`](figure_8/README.md)：与既有 LLM 服务模拟器的对比。
- [`figure_9/README.md`](figure_9/README.md)：TPU 吞吐验证与时延误差表。
- [`figure_10/README.md`](figure_10/README.md)：仅 GPU 与 GPU+PIM 的案例研究。
