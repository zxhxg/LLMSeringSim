# Figure 8

## 本图展示内容

LLMServingSim 2.0 论文中的 Figure 8 将 LLMServingSim 2.0 与先前的 LLM 服务模拟器进行对比。它分为：

- `figure_8a.pdf`：面向精度的对比，比较 `TPS`、`TTFT` 和 `TPOT`，并统一归一化到 vLLM
- `figure_8b.pdf`：仿真时间对比

评估场景包括 `SD`、`MD`、`PDD` 和 `SM`。

## 重要说明

**Figure 8b 中的仿真时间取决于执行评测的机器性能。**  
**即使配置和数据集完全相同，不同 CPU、服务器和运行环境下的绝对 `simulation_time_s` 数值也可能不同。**

因此，评测者不应期望得到与保留 artifact 输出完全一致的原始仿真时间数值，除非运行环境与其使用的硬件和软件环境完全一致。  
请使用参考文件和 PDF 对整体行为与相对趋势进行比较，但应将绝对仿真时间数值视为与硬件相关的指标。

## 输入与输出

已提交的参考测量结果保存在：

- `reference/*_latency.tsv`
- `reference/*_sim_time.tsv`

这些文件使用 `framework` 列，并包含如 `TokenSim`、`Vidur`、`APEX`、`LLMServingSim` 和 `vLLM` 等行。

图生成脚本会在以下目录生成 LLMServingSim 2.0 输出：

- `logs/`
- `results/`
- `parsed/`

用于绘图的模拟器解析结果位于：

- `parsed/*_latency.tsv`
- `parsed/*_sim_time.tsv`

生成的图文件为：

- `figure_8a.pdf`
- `figure_8b.pdf`

可视化目标文件为 `figure_8a_ref.pdf` 和 `figure_8b_ref.pdf`。

绘图代码会在绘图阶段将解析得到的 LLMServingSim 2.0 数值与已提交的参考表进行合并。

## 坐标轴与结果解释

Figure 8a：

- X 轴：场景组（`SD`、`MD`、`PDD`、`SM`），每组内包含指标块（`TPS`、`TTFT`、`TPOT`）
- Y 轴：相对于 `vLLM` 的归一化指标值

Figure 8b：

- X 轴：场景（`Single Dense`、`Multi Dense`、`Prefill-Decode Disaggregated`、`Single MoE`）
- Y 轴：仿真时间（秒）

这两张图共同展示了相对于先前模拟器的输出精度和运行开销。

## 运行方法

在 `evaluation/` 目录下：

```bash
bash figure_8.sh
```

对比输出结果：

1. 将 `parsed/` 中生成的 parsed TSV 文件与 `evaluation/artifacts/figure_8/parsed/` 中的文件进行比较。  
   若要在 evaluation 目录下进行自动对比，请运行 `bash compare.sh <figure_id>`（例如 `bash compare.sh 8`）。  
   全部选项见 `bash compare.sh --help`。
2. 将 `figure_8a.pdf`、`figure_8b.pdf` 与 `figure_8a_ref.pdf`、`figure_8b_ref.pdf` 进行比较。
