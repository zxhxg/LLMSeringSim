# Task 15：HBF 每层时间预算文档

## 任务目标

- 明确记录“不卸载参数”时 32 个 hidden layer 的完整总时长
- 用该值作为每层可用于“下一层预测 + 传输”的时间预算
- 记录各 HBF 配置下每层 `T_predict + T_transfer` 与对应 stall
- 将结果整理到 `docs/` 中

## 修改文件

- `docs/hbf_layer_time_budget.md`
- `tasks/task_15_hbf_layer_time_budget.md`

## 修改模块

- 文档
- 测试记录

## 修改函数

- 无代码函数修改

## 实现逻辑

1. 从当前 trace 中抽取 32 个 hidden block 的总执行时长
2. 将“input_layernorm 到 down_proj”的整层累计时长定义为该层完整总时长
3. 使用该值作为：
   - 不卸载层时延
   - 下一层可用于 HBF 预测与传输的时间预算
4. 针对每个 HBF 配置计算：
   - `T_predict`
   - `T_transfer`
   - `T_prefetch`
   - `stall = max(0, T_prefetch - T_layer_total)`
5. 输出 32 层明细表与配置汇总表

## 验证方式

- 当前 trace 中共识别出 `32` 个 hidden block
- 32 层总时长一致，均为 `771319 ns`
- 计算结果已写入：
  - `docs/hbf_layer_time_budget.md`

## 影响范围

- 本任务不改动模拟器逻辑
- 只补充层级时间预算与预取/stall 的解释性文档
