# Task 13：HBF 性能测试汇总文档

## 任务目标

- 对 HBF 卸载策略做系统化性能测试汇总。
- 覆盖两类问题：
  - 不同 HBF 配置与参数下的性能表现。
  - 相同配置下，本地不卸载与卸载到 HBF 的性能对比。
- 将结果整理为中文文档输出到 `docs/`。

## 修改文件

- `cluster_config/single_node_no_hbf_instance.json`
- `docs/hbf_performance_report.md`
- `tasks/task_13_hbf_performance_report.md`

## 修改模块

- 配置文件：`cluster_config/`
- 文档：`docs/`
- 任务日志：`tasks/`

## 修改函数

- 无代码函数修改。

## 实现逻辑

1. 新增一个“不卸载到 HBF”的单节点基线配置：
   - 权重放置在本地 NPU
   - `hbf_prefetch.enabled = false`
2. 复用已验证通过的 HBF 配置：
   - `ffn_ratio = 1.0 / 0.75 / 0.5 / 0.25`
   - `ffn_ratio = 0.5, predict = 5ms/layer`
3. 在 Docker 容器内运行测试，提取以下可稳定获取的指标：
   - `Total simulation time`
   - `Total latency (s)`
   - `Mean TTFT`
   - `Mean TPOT`
   - `Mean ITL`
   - `Average generation throughput`
   - `Total token throughput`
   - `Total generated tokens`
   - `HBF transfer bytes / predict / transfer / stall`
4. 从数据集前 `2` 条请求中补充：
   - 最大输入长度
   - 最大输出长度

## 影响范围

- 不改动模拟器代码逻辑。
- 新增基线配置仅用于测试与对照。
- 输出文档可直接用于后续实验讨论和报告撰写。

## 验证方式

- 在容器 `servingsim_docker` 中运行以下代表性配置：
  - `cluster_config/single_node_no_hbf_instance.json`
  - `cluster_config/single_node_hbf_instance.json`
  - `cluster_config/single_node_hbf_ffn075.json`
  - `cluster_config/single_node_hbf_ffn050.json`
  - `cluster_config/single_node_hbf_ffn025.json`
  - `cluster_config/single_node_hbf_ffn050_predict5ms.json`
- 检查日志中的吞吐、时延、TTFT、TPOT、ITL 与 HBF 指标是否完整。
- 最终结果汇总到：
  - `docs/hbf_performance_report.md`
