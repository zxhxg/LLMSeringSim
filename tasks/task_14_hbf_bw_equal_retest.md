# Task 14：HBF 带宽对齐 HBM 后的复测记录

## 任务目标

- 将所有 HBF 配置中的 `hbf_mem.mem_bw` 修改为与 HBM 相同的带宽
- 重新执行上一轮性能测试
- 额外记录不同配置下每层预取导致的停顿大小
- 输出新的测试记录与分析报告

## 修改文件

- `cluster_config/single_node_hbf_instance.json`
- `cluster_config/single_node_hbf_ffn075.json`
- `cluster_config/single_node_hbf_ffn050.json`
- `cluster_config/single_node_hbf_ffn025.json`
- `cluster_config/single_node_hbf_ffn000.json`
- `cluster_config/single_node_hbf_ffn050_predict2ms.json`
- `cluster_config/single_node_hbf_ffn050_predict5ms.json`
- `docs/hbf_bw_equal_performance_report.md`
- `tasks/task_14_hbf_bw_equal_retest.md`

## 修改模块

- HBF 配置文件
- 文档
- 测试记录

## 修改函数

- 无代码函数修改

## 实现逻辑

1. 将所有 HBF 配置的 `hbf_mem.mem_bw` 从 `40` 统一改为 `768`
2. 重新运行以下配置：
   - 本地不卸载基线
   - `HBF-1.0`
   - `HBF-0.75`
   - `HBF-0.50`
   - `HBF-0.25`
   - `HBF-0.50-P2ms`
   - `HBF-0.50-P5ms`
3. 从日志中提取：
   - 总时延
   - TTFT / TPOT / ITL
   - token 吞吐
   - HBF 传输量
   - HBF stall
4. 额外计算：
   - 平均每层预取时间
   - 平均每层停顿时间差

## 验证方式

- 所有测试均在 Docker 容器 `servingsim_docker` 内运行
- 指标来自程序标准输出，不修改模拟器代码逻辑
- 最终结果已整理到：
  - `docs/hbf_bw_equal_performance_report.md`

## 影响范围

- 本任务不改变 HBF 机制实现逻辑
- 仅调整带宽参数并重新测试
- 新报告用于对比“低带宽 HBF”与“高带宽 HBF”条件下的性能差异
