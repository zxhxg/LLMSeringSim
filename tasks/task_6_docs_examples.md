# Task 6：中文文档与样例配置

## 任务目标

补充 HBF 相关中文说明、示例配置与工程流程约束，使后续测试和扩展有统一入口。

## 修改文件

- `README.zh-CN.md`
- `cluster_config/README.zh-CN.md`
- `cluster_config/single_node_hbf_instance.json`

## 修改模块

- 项目总览文档
- 集群配置文档
- HBF 示例配置

## 修改函数

- 无

## 实现逻辑

- 在 `README.zh-CN.md` 中新增 HBF 权重分层与预取说明、运行示例和限制说明。
- 在 `cluster_config/README.zh-CN.md` 中新增 `hbf_mem`、`hbf_prefetch`、`hbf[:id]` 的字段说明。
- 新增 `single_node_hbf_instance.json`，给出 dense-only 的最小 HBF 配置样例。

## 影响范围

- 影响项目使用说明，不影响运行逻辑。

## 验证方式

- 文档内容使用中文。
- 示例配置可被配置解析器识别。
