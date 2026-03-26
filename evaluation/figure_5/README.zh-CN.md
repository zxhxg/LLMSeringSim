# Figure 5

## 本图展示内容

LLMServingSim 2.0 论文中的 Figure 5 对比了真实 GPU 系统与基于 vLLM serving stack 的 LLMServingSim 2.0 在时间维度上的吞吐表现。该图包含八个子图：`A6000` 和 `H100` 两种硬件，每种硬件下分别包含 `MD`、`SD+PC`、`PDD` 和 `SM`。

- `MD`：多实例稠密服务
- `SD+PC`：启用前缀缓存的单实例稠密服务
- `PDD`：prefill/decode 解耦
- `SM`：单实例 MoE 服务

## 输入与输出

已提交的参考测量结果保存在：

- `A6000/reference/*_throughput.tsv`
- `H100/reference/*_throughput.tsv`

图生成脚本会在以下目录生成 LLMServingSim 输出：

- `A6000/logs/`、`A6000/results/`、`A6000/parsed/`
- `H100/logs/`、`H100/results/`、`H100/parsed/`

用于绘图的模拟器解析结果位于：

- `A6000/parsed/*_throughput.tsv`
- `H100/parsed/*_throughput.tsv`

生成的图文件为：

- `figure_5.pdf`

可视化目标文件为 `figure_5_ref.pdf`。

## 坐标轴与结果解释

- X 轴：时间（秒）
- Y 轴：吞吐（token/s）

每个子图都会将 `reference/` 中处理后的真实系统基线，与 `parsed/` 中解析得到的 LLMServingSim 结果叠加展示。目标是验证模拟吞吐轨迹在时间维度上与实测结果的吻合程度。

## 运行方法

在 `evaluation/` 目录下：

```bash
bash figure_5.sh
```

对比输出结果：

1. 将 `A6000/parsed/` 和 `H100/parsed/` 中生成的 parsed TSV 文件，与 `evaluation/artifacts/figure_5/A6000/parsed/` 和 `evaluation/artifacts/figure_5/H100/parsed/` 中的文件进行比较。  
   若要在 evaluation 目录下进行自动对比，请运行 `bash compare.sh <figure_id>`（例如 `bash compare.sh 5`）。  
   全部选项见 `bash compare.sh --help`。
2. 将 `figure_5.pdf` 与 `figure_5_ref.pdf` 进行比较。
