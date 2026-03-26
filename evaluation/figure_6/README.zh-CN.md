# Figure 6

## 本图展示内容

LLMServingSim 2.0 论文中的 Figure 6 用于验证 RTX A6000 上的功耗与能耗建模。它包含三个输出：

- `figure_6a.pdf`：TP1 功耗轨迹
- `figure_6b.pdf`：TP2 功耗轨迹
- `figure_6c.pdf`：能耗拆分

## 输入与输出

已提交的参考测量结果保存在：

- `reference/server_power_tp1.tsv`
- `reference/server_power_tp2.tsv`

图生成脚本会在以下目录生成 LLMServingSim 输出：

- `logs/`
- `results/`
- `parsed/`

用于绘图的模拟器解析结果位于：

- `parsed/power_tp1.tsv`
- `parsed/power_tp2.tsv`
- `parsed/component_energy.tsv`

生成的图文件为：

- `figure_6a.pdf`
- `figure_6b.pdf`
- `figure_6c.pdf`

可视化目标文件为 `figure_6a_ref.pdf`、`figure_6b_ref.pdf` 和 `figure_6c_ref.pdf`。

## 坐标轴与结果解释

Figure 6a 和 6b：

- X 轴：时间（秒）
- Y 轴：功率（瓦）

这两个折线图将 `reference/` 中的真实服务器功耗轨迹，与 `parsed/` 中解析得到的 LLMServingSim 功耗轨迹进行对比。

Figure 6c：

- X 轴：tensor parallel 设置（`TP1`、`TP2`）
- Y 轴：总能量（焦耳）

该堆叠柱状图展示了从模拟器日志中解析得到的各组件能耗拆分。

## 运行方法

在 `evaluation/` 目录下：

```bash
bash figure_6.sh
```

对比输出结果：

1. 将 `parsed/` 中生成的 parsed TSV 文件与 `evaluation/artifacts/figure_6/parsed/` 中的文件进行比较。  
   若要在 evaluation 目录下进行自动对比，请运行 `bash compare.sh <figure_id>`（例如 `bash compare.sh 6`）。  
   全部选项见 `bash compare.sh --help`。
2. 将 `figure_6a.pdf`、`figure_6b.pdf` 和 `figure_6c.pdf` 与对应的 `*_ref.pdf` 文件进行比较。
