# Figure 9

## 本图展示内容

LLMServingSim 2.0 论文中的 Figure 9 使用 vLLM framework 将 LLMServingSim 2.0 与真实 TPU 系统进行验证对比。它包含：

- `figure_9a.pdf`：随时间变化的吞吐
- `figure_9b.pdf`：与时延相关指标的误差率表

## 输入与输出

已提交的参考测量结果保存在：

- `reference/SD_throughput.tsv`
- `reference/SD_latency.tsv`

图生成脚本会在以下目录生成 LLMServingSim 输出：

- `logs/`
- `results/`
- `parsed/`

用于绘图的模拟器解析结果位于：

- `parsed/SD_throughput.tsv`
- `parsed/SD_latency.tsv`

生成的图文件为：

- `figure_9a.pdf`
- `figure_9b.pdf`

可视化目标文件为 `figure_9a_ref.pdf` 和 `figure_9b_ref.pdf`。

`SD_latency.tsv` 包含 `throughput_tok_s`、`mean_ttft_ms`、`mean_tpot_ms` 和 `mean_itl_ms`。

## 坐标轴与结果解释

Figure 9a：

- X 轴：时间（秒）
- Y 轴：吞吐（token/s）

该图将 `reference/SD_throughput.tsv` 中处理后的 TPU 基线，与 `parsed/SD_throughput.tsv` 中解析得到的 LLMServingSim 吞吐轨迹进行对比。

Figure 9b：

- 行：`TPS`、`TPOT`、`ITL` 和 `Geomean`
- 数值：解析后的模拟器时延 TSV 与参考时延 TSV 之间的绝对百分比误差

该表总结了 LLMServingSim 2.0 对实测 TPU 时延行为的复现精度。

## 运行方法

在 `evaluation/` 目录下：

```bash
bash figure_9.sh
```

对比输出结果：

1. 将 `parsed/` 中生成的 parsed TSV 文件与 `evaluation/artifacts/figure_9/parsed/` 中的文件进行比较。  
   若要在 evaluation 目录下进行自动对比，请运行 `bash compare.sh <figure_id>`（例如 `bash compare.sh 9`）。  
   全部选项见 `bash compare.sh --help`。
2. 将 `figure_9a.pdf`、`figure_9b.pdf` 与 `figure_9a_ref.pdf`、`figure_9b_ref.pdf` 进行比较。
