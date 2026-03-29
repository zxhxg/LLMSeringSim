# Task 9：Chakra 依赖回退修复

## 任务目标

修复 HBF 伪层插入后，Chakra 在 `convert_common` / `convert_prefill` 中无法正确找到最近真实前驱节点的问题。

## 修改文件

- `astra-sim/extern/graph_frontend/chakra/src/converter/llm_converter.py`

## 修改模块

- ET 图依赖构建

## 修改函数

- `LLMConverter.get_latest_dependency_node`
- `LLMConverter.convert_common`
- `LLMConverter.convert_prefill`

## 实现逻辑

- 新增 `get_latest_dependency_node()`，从当前层之前向前扫描，返回最近的 `comm_node` 或 `comp_node`。
- 将原先固定使用 `layer_num - 1` / `layer_num - 2` 的回退逻辑，替换为扫描式回退。
- 若扫描后仍找不到合法前驱，则抛出显式错误，避免出现 `NoneType.id` 这类不清晰异常。

## 影响范围

- 影响插入 HBF 伪层后的依赖回退路径。
- 不改变正常层之间的主依赖关系。

## 验证方式

- 本地 Python 语法检查通过。
- HBF 伪层存在时，converter 不再因 `layer_num - 2` 指向空节点而失败。
