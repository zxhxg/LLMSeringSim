# Figure 7

## 本图展示内容

LLMServingSim 2.0 论文中的 Figure 7 对比了真实 RTX A6000 部署与 LLMServingSim 2.0 在内存使用量和前缀命中率上的表现。它包含：

- 启用前缀缓存的单实例验证
- 使用 CPU 共享前缀存储的多实例验证

生成的图为 `figure_7.pdf`，可视化参考为 `figure_7_ref.pdf`。

## 输入与输出

已提交的参考测量结果保存在：

- `reference/SD+PC.tsv`
- `reference/MD+PC+PS_inst0.tsv`
- `reference/MD+PC+PS_inst1.tsv`
- `reference/MD+PC+PS_shared_cpu.tsv`

图生成脚本会在以下目录生成 LLMServingSim 输出：

- `logs/`
- `results/`
- `parsed/`

用于绘图的模拟器解析结果位于：

- `parsed/SD+PC.tsv`
- `parsed/MD+PC+PS_inst0.tsv`
- `parsed/MD+PC+PS_inst1.tsv`
- `parsed/MD+PC+PS_shared_cpu.tsv`

生成的图文件为：

- `figure_7.pdf`

可视化目标文件为 `figure_7_ref.pdf`。

## 坐标轴与结果解释

左列，单实例：

- X 轴：时间（秒）
- 上方 Y 轴：GPU 内存使用量（GB）
- 下方 Y 轴：前缀命中率（百分比）

右列，多实例：

- X 轴：时间（秒）
- 上方 Y 轴：GPU 或共享 CPU 内存使用量（GB）
- 下方 Y 轴：前缀命中率（百分比）

实线来自 `reference/` 中处理后的真实系统轨迹，虚线来自 `parsed/` 中解析得到的 LLMServingSim 输出。

## 运行方法

在 `evaluation/` 目录下：

```bash
bash figure_7.sh
```

对比输出结果：

1. 将 `parsed/` 中生成的 parsed TSV 文件与 `evaluation/artifacts/figure_7/parsed/` 中的文件进行比较。  
   若要在 evaluation 目录下进行自动对比，请运行 `bash compare.sh <figure_id>`（例如 `bash compare.sh 7`）。  
   全部选项见 `bash compare.sh --help`。
2. 将 `figure_7.pdf` 与 `figure_7_ref.pdf` 进行比较。
