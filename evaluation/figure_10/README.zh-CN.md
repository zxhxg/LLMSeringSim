# Figure 10

## 本图展示内容

LLMServingSim 2.0 论文中的 Figure 10 是一个 PIM 案例研究，对比了：

- `GPU-only`
- `PIM`
- `PIM-sbi`

生成的图为 `figure_10.pdf`，可视化目标文件为 `figure_10_ref.pdf`。

## 输入与输出

该图不需要已提交的参考测量结果。它完全基于 LLMServingSim 输出生成。

图生成脚本会在以下目录生成 LLMServingSim 输出：

- `logs/`
- `results/`
- `parsed/`

用于绘图的模拟器解析结果位于：

- `parsed/gpu_only_b256_throughput.tsv`
- `parsed/pim_b256_throughput.tsv`
- `parsed/pim_sbi_b256_throughput.tsv`
- `parsed/component_energy.tsv`
- `parsed/energy_per_token.tsv`

生成的图文件为：

- `figure_10.pdf`

可视化目标文件为 `figure_10_ref.pdf`。

## 坐标轴与结果解释

左侧面板：

- X 轴：时间（秒）
- Y 轴：吞吐（token/s）

右侧面板：

- X 轴：系统变体（`GPU-only`、`PIM`、`PIM-sbi`）
- 左 Y 轴：总能量（焦耳）
- 右 Y 轴：每个生成 token 的焦耳数

堆叠柱状图来自 `parsed/component_energy.tsv`，叠加的点和折线来自 `parsed/energy_per_token.tsv`。

## 运行方法

在 `evaluation/` 目录下：

```bash
bash figure_10.sh
```

对比输出结果：

1. 将 `parsed/` 中生成的 parsed TSV 文件与 `evaluation/artifacts/figure_10/parsed/` 中的文件进行比较。  
   若要在 evaluation 目录下进行自动对比，请运行 `bash compare.sh <figure_id>`（例如 `bash compare.sh 10`）。  
   全部选项见 `bash compare.sh --help`。
2. 将 `figure_10.pdf` 与 `figure_10_ref.pdf` 进行比较。
