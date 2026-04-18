# Task 1 执行文档

本文件是面向后续 Codex 新会话的独立执行文档。后续实现者应默认以本文件作为 Task 1 的唯一任务入口，不应再混用 `modify/tasks.md` 作为主要执行依据。

目标是让一个新的会话在不依赖当前对话上下文的情况下，也能完整理解 Task 1 要做什么、为什么这样做、应该改哪些模块、如何测试、何时才算完成。

---

# 1. Task 1 的目标边界

Task 1 只做最小可运行的 HBM + HBF 双层架构接入，不做完整 sparse/page/block 工具链，不做 Step 2 到 Step 5 的端到端闭环。

Task 1 必须完成的内容：

- 在当前模拟器中正确实现 HBM + HBF 双层架构
- 正确引入 `bw_mode` 参数
- 支持三种带宽建模模式：
  - `shared_frontend`
  - `fully_independent`
  - `fully_serialized`
- 支持 HBM + HBF 配置运行
- 保持原有 HBM + CPU memory 路径兼容
- 在完成全部测试后输出修改说明和性能对比文档

Task 1 不要求完成的内容：

- 不要求实现真实 sparse 逻辑 trace 提取
- 不要求实现 layout / page 映射工具链
- 不要求实现 request materialization 工具链
- 不要求实现完整的 request-level HBF replay

Task 1 的最小闭环定义如下：

- 权重位于 HBF
- 计算发生在 NPU/HBM 路径
- 每层执行一次 dense HBF read
- 输出 HBF bytes、HBF requests、HBF time、latency、throughput
- 三种 `bw_mode` 下结果可区分

---

# 2. 先建立正确概念

## 2.1 对 HBF 的理解

在本项目中，HBF 应被建模为一种独立的、位于 GPU 侧的权重存储层，而不是 CPU/CXL 的别名，也不是简单的另一种远端内存。

对模拟器而言，HBF 至少需要具备这些独立属性：

- 独立的 memory location type
- 独立的 bandwidth
- 独立的 latency
- 可配置的 device count
- 对访问请求具有独立的 queueing 与 contention 行为

HBF 最自然的职责，是承载那些无法长期常驻于 HBM、但又需要比主机侧更高吞吐的大容量模型权重。

Task 1 中，HBF 先被视为 dense layer-wise 权重读取层。后续任务中，它还应升级为 request-granular weight layer，但这不是 Task 1 的交付范围。

## 2.2 对 HBM + HBF 架构的理解

HBM 是本地高带宽工作内存，用于承载当前活跃数据。

HBF 是位于 HBM 之外、更深一层的 GPU 侧权重存储层，用于承载容量更大但访问代价更高的权重数据。

HBM + HBF 架构不是两个存储名字的并列，而是一种层次化设计：

- 热数据在 HBM
- 更冷、更大容量的权重在 HBF
- 按层或按块从 HBF 拉到计算路径

Task 1 只需要表达这三层语义中的第一层和最小第二层：

- placement：哪些权重在 HBF
- access pattern：Task 1 只支持 dense full read
- system effect：HBF 读如何影响 per-layer latency、总 latency 和 throughput

## 2.3 HBM 与 HBF 向 GPU die 供数的带宽处理

HBM 与 HBF 应先被视为两个独立 memory tier，但它们向 GPU die / compute path 供数时，不应默认完全独立。

Task 1 需要支持三种 `bw_mode`：

- `shared_frontend`
  - 默认模式
  - HBM 和 HBF 是独立 memory tier，但通往 GPU die / compute path 的前端存在共享约束
  - 这是主实验默认模式
- `fully_independent`
  - 理论乐观上界
  - HBM 与 HBF 可并行供数，有效带宽可近似独立叠加
- `fully_serialized`
  - 理论悲观下界
  - HBM 与 HBF 的访问基本串行化处理

Task 1 对 `bw_mode` 的最低要求：

- 三种模式都必须可通过配置切换
- 默认模式必须为 `shared_frontend`
- 所有实验日志中必须记录当前 `bw_mode`
- 主结果使用 `shared_frontend`
- 另两种模式用于上界/下界敏感性分析

---

# 3. 先理解模拟器主链路再动手

后续新会话在开始实现之前，必须先理解以下闭环：

`main.py`  
→ `config_builder.py` 解析 cluster config 并生成 ASTRA-Sim 输入配置  
→ `Router` 将数据集请求注入不同实例  
→ `Scheduler` 在每个实例内做 continuous batching  
→ `MemoryModel` 管理权重占用、KV cache、prefix cache 与 swap/evict  
→ `trace_generator.py` 将当前 batch 展开为文本 trace  
→ `graph_generator.py` 调 Chakra 将 trace 转为 workload graph  
→ `ASTRA-Sim` 执行系统级仿真  
→ `Controller` 负责与 ASTRA-Sim 子进程通信并接收 iteration 完成事件  
→ `Scheduler.add_done()` 更新请求状态  
→ `main.py` 汇总 latency、throughput、power 与 CSV 输出

## 3.1 模块职责边界

- `main.py`
  - 参数入口
  - 主循环
  - 统计输出
- `config_builder.py`
  - cluster config 解析
  - placement 解析
  - ASTRA-Sim memory config 生成
- `Router`
  - 请求注入与实例路由
- `Scheduler`
  - continuous batching
  - inflight batch 生命周期管理
- `MemoryModel`
  - 权重大小估算
  - NPU/CPU/CXL 内存占用管理
  - KV cache / prefix cache
- `trace_generator.py`
  - 逐层 trace 生成
  - weight/input/output memory location 指定
- `graph_generator.py`
  - Chakra graph 转换
- `Controller`
  - ASTRA-Sim 进程通信
  - iteration 完成事件解析
- `ASTRA-Sim`
  - system-level timing / memory access / network backend

## 3.2 对 Task 1 特别重要的责任划分

- HBF 配置接入主要落在 `config_builder.py`
- HBF 权重占用与统计主要落在 `memory_model.py`
- HBF 读事件进入 trace 主要落在 `trace_generator.py`
- HBF 的最终汇总统计主要落在 `main.py` 或新增汇总逻辑

## 3.3 明确不要误改的地方

- 不要把 `controller.py` 当成主要 HBF 统计实现点，除非需要扩展 ASTRA-Sim 的 stdout 协议
- 不要把 `logger.py` 当成业务统计汇总模块，它主要负责日志格式
- 不要把 HBF 简单当成 CPU/CXL 别名
- 不要在未理解主链路前直接改 `trace_generator.py`

---

# 4. 当前代码事实与 Task 1 的修订原则

后续执行者必须基于当前仓库真实状态工作，而不是基于原始任务文档的假设。

已确认的代码事实：

- `modify/tasks.md` 文件本身是正常 UTF-8 中文
- 当前工作区不存在可直接使用的 `tasks/` 目录，新增文档默认落在 `modify/`
- `astra-sim` 与 Chakra 已存在 `HBF_MEMORY` 相关支持
- 当前 Python 层尚未完整支持 `weights: hbf:x`
- 当前 `config_builder.py` 只原生处理 `npu/cpu/cxl`
- 当前 `memory_model.py` 默认把整模型权重计入 NPU 常驻内存

因此 Task 1 的修订原则是：

- Task 1 不是“底层从零发明 HBF”
- Task 1 是“补齐 Python 侧 HBF 接入、placement、统计和 `bw_mode`”
- `controller.py` 不是 Task 1 的主修改点
- `logger.py` 不是 Task 1 的主修改点

---

# 5. Task 1 需要修改的模块与要求

## 5.1 `cluster_config/README.md`

需要新增：

- HBF 配置说明
- `bw_mode` 配置说明
- 至少一个 HBM + HBF 示例片段

建议说明的配置字段：

```json
"hbf_mem": {
  "mem_size": 1024,
  "mem_bw": 512,
  "mem_latency": 2.0,
  "num_devices": 1
}
```

以及：

```json
"bw_mode": "shared_frontend"
```

同时说明 placement 可写：

```json
"weights": "hbf:0"
```

注意：

- `page_size` 等字段如果当前 Python 层或后端不消费，不要在 Task 1 中假装已经原生支持
- 只写当前 Task 1 真正实现的字段

## 5.2 `cluster_config/`

必须准备四组测试配置对应的配置文件。

建议固定文件名如下，避免后续新会话再做命名决策：

- `cluster_config/single_node_hbf_shared_frontend.json`
- `cluster_config/single_node_hbf_fully_independent.json`
- `cluster_config/single_node_hbf_fully_serialized.json`
- `cluster_config/single_node_memory_instance.json`
  - 作为原始 HBM + CPU memory 对照组

要求：

- 前三组配置都启用 HBF
- 三者除 `bw_mode` 外尽量保持一致
- 对照组保持原始 HBM + CPU memory 路径

## 5.3 `inference_serving/config_builder.py`

Task 1 中必须完成：

- 识别顶层 `hbf_mem`
- 识别 placement 中的 `weights: hbf:x`
- 将 HBF tier 注入 ASTRA-Sim memory config
- 让 placement 校验支持 HBF location
- 让 `bw_mode` 被读取并保存在 cluster-level 或 instance-level 配置中，供后续时间模型使用

需要特别注意：

- 当前 `_mem_str()` 只识别 `npu/cpu/cxl`，需要扩展为支持 `hbf`
- 当前 placement 校验逻辑必须能识别 `HBF:0` 这类设备
- 不要破坏原有 `npu/cpu/cxl` 路径

## 5.4 `inference_serving/memory_model.py`

Task 1 中必须完成：

- 正确区分 HBM 常驻权重与 HBF 权重
- 不再默认把全部模型权重算进 NPU 常驻内存
- 增加 HBF 统计字段

建议新增统计项：

- `hbf_total_size`
- `hbf_used_size`
- `hbf_read_bytes`
- `hbf_read_requests`
- `hbf_read_time_us`

建议新增能力：

- 能根据 placement 判断哪些层权重常驻 HBM，哪些位于 HBF
- 能提供 layer-wise HBF read size 查询
- 能为 trace 生成层提供 HBF 读时间估算所需信息

## 5.5 `inference_serving/trace_generator.py`

Task 1 中必须完成：

- 当层权重位于 HBF 时，生成对应的 dense HBF read 行为
- 读时间建模需支持三种 `bw_mode`

Task 1 的最低建模要求：

- dense full read
- layer-wise read
- 能区分三种 `bw_mode`

建议的时间模型处理方式：

- `fully_independent`
  - 作为乐观上界
- `shared_frontend`
  - 作为默认模式
- `fully_serialized`
  - 作为悲观下界

注意：

- Task 1 不要求在 `trace_generator.py` 中实现 sparse/page/block 逻辑
- Task 1 不要求完整 request replay

## 5.6 `main.py`

Task 1 中必须完成：

- 增加与 HBF 相关的参数入口
- 增加与 `bw_mode` 相关的参数入口
- 输出 HBF 统计和当前 `bw_mode`

建议新增参数：

- `--enable-hbf`
- `--hbf-bw-mode shared_frontend|fully_independent|fully_serialized`

如果实现上不需要单独 `--enable-hbf`，也可以通过配置文件自动启用，但必须保证日志里能明确看出当前是否启用了 HBF。

## 5.7 不建议作为 Task 1 主修改点的文件

- `inference_serving/controller.py`
  - 除非需要扩展 ASTRA-Sim 输出协议，否则不应作为主要实现点
- `inference_serving/logger.py`
  - 仅负责格式，不应承担业务统计汇总

---

# 6. Task 1 的自动化测试与验收流程

## 6.1 测试平台要求

- 使用当前正在运行的容器作为唯一实验平台
- 不新建额外环境
- 不假设用户会重新装依赖
- 开发前必须做环境验证
- 环境验证必须使用官方 README 中的最小示例命令

## 6.2 Step 0：环境可用性验证

必须先阅读仓库 `README.md` 并执行官方最小示例命令。

当前官方示例命令如下：

```bash
python main.py \
    --cluster-config 'cluster_config/single_node_single_instance.json' \
    --fp 16 --block-size 16 \
    --dataset 'dataset/sharegpt_req100_rate10_llama.jsonl' \
    --output 'output/example_single_run.csv' \
    --num-req 100 --log-interval 1.0
```

验收标准：

- 命令成功执行
- 无依赖错误
- 无路径错误
- 无配置文件缺失错误
- 能生成基础运行输出

只有 Step 0 成功，才允许进入 Task 1 功能实现。

如果 Step 0 失败：

- 必须先定位失败原因
- 只修复与当前任务直接相关的问题
- 不允许跳过环境验证

## 6.3 Step 1：实现 Task 1 功能

实现范围严格限定为：

- 引入 HBF memory tier
- 引入 `bw_mode`
- 支持 `shared_frontend`
- 支持 `fully_independent`
- 支持 `fully_serialized`
- 支持 HBM + HBF 配置运行
- 保持原始 HBM + CPU memory 路径兼容

## 6.4 Step 2：生成测试配置与运行命令

至少准备四组配置：

- 配置 A：HBM + HBF，`bw_mode = shared_frontend`
- 配置 B：HBM + HBF，`bw_mode = fully_independent`
- 配置 C：HBM + HBF，`bw_mode = fully_serialized`
- 配置 D：原始 HBM + CPU memory 配置

每组都必须有：

- 明确的配置文件
- 明确的运行命令

建议运行命令模板如下：

```bash
python main.py \
    --cluster-config '<CONFIG_PATH>' \
    --fp 16 --block-size 16 \
    --dataset 'dataset/sharegpt_req100_rate10_llama.jsonl' \
    --output '<OUTPUT_PATH>' \
    --num-req 100 --log-interval 1.0
```

如果 `bw_mode` 通过 CLI 指定，则在命令中补充：

```bash
--hbf-bw-mode <MODE>
```

## 6.5 Step 3：执行四组配置测试

依次运行 A / B / C / D。

每组测试必须检查：

- 程序是否正常结束
- 是否有报错、异常退出或空输出
- 是否正确加载预期配置
- 日志中是否显示当前 memory tier 配置
- 日志中是否显示当前 `bw_mode`

HBM + HBF 配置额外检查：

- HBF 是否被识别为独立 memory tier
- 权重读取是否走 HBF 路径
- HBF 相关统计是否存在
- 三种 `bw_mode` 结果是否可区分

HBM + CPU 对照组额外检查：

- 原有 CPU memory 路径是否仍可正常运行
- 不引入 HBF 时是否没有副作用
- 行为是否与原始逻辑一致或至少逻辑一致

## 6.6 性能结果的预期关系

对 HBM + HBF 三种模式，在其他条件一致时，预期如下：

若指标是 latency：

`fully_independent <= shared_frontend <= fully_serialized`

若指标是 throughput：

`fully_independent >= shared_frontend >= fully_serialized`

如果结果不满足这个大致关系：

- 必须检查实现是否正确
- 必须检查日志和配置是否真的生效
- 不允许直接忽略异常结果

HBM + CPU memory 对照组不参与三种 `bw_mode` 的排序比较，它的职责是：

- 验证原有功能没有被破坏
- 作为 HBF 架构的兼容性对照组

## 6.7 Task 1 通过条件

只有满足以下所有条件，Task 1 才算完成：

- 官方示例命令验证通过
- HBM + HBF 的三种 `bw_mode` 都能成功运行
- 原始 HBM + CPU memory 配置能成功运行
- 四组配置都能生成有效输出
- HBF 统计项能在输出中体现
- 三种 `bw_mode` 的性能关系总体符合预期
- 没有明显运行时错误、配置错误或逻辑错误
- 最终测试报告已写入 `modify/`

## 6.8 停止条件

只有在以下条件都满足时，才允许停止：

- 所有功能测试都已完成
- 所有关键输出都已核验
- 没有未解决的严重问题
- 最终文档已生成

以下情况不允许结束任务：

- 只完成代码修改，没有完成测试
- 只完成部分模式测试
- 没有验证原始 HBM + CPU memory 配置
- 没有检查性能关系是否合理
- 没有输出最终说明文档

---

# 7. 最终交付物

Task 1 完成后，必须至少产出以下文档：

## 7.1 `modify/task1_test_report.md`

该报告必须包含：

### 1. 本次修改内容

- 修改了哪些文件
- 每个文件做了什么修改
- 新增了哪些配置项
- 新增了哪些 HBF 相关逻辑
- 如何实现 `bw_mode`

### 2. 测试环境说明

- 当前运行容器
- 使用了哪个官方示例命令做环境验证
- 验证结果如何

### 3. 测试配置列表

列出四组配置及其：

- 配置文件路径
- 运行命令

### 4. 测试结果

至少包含：

- 是否运行成功
- 关键日志摘要
- latency / throughput / HBF traffic 等关键指标
- 三种模式是否符合预期关系

### 5. 结论

- Task 1 是否完成
- 是否可进入下一阶段
- 是否存在遗留问题或后续建议

### 6. 报告开头的额外要求

报告开头必须简短回顾：

- 对 HBF 的理解
- 对 HBM + HBF 架构的理解
- 对模拟器主链路的理解

## 7.2 本文档本身的角色

`modify/task1.md` 必须充当：

- Task 1 的任务说明书
- Task 1 的实现前认知检查文档
- Task 1 的新会话接力文档

后续新会话默认应先读完本文件，再开始改代码。

---

# 8. 新会话防误改要求

## 8.1 可接力性要求

后续新会话必须能只依赖本文件就理解：

- Task 1 的目标边界
- HBF 的概念
- HBM + HBF 的概念
- `bw_mode` 三种模式的含义
- 为什么 `shared_frontend` 是默认模式
- Task 1 的测试完成条件

## 8.2 防误改要求

后续新会话在开始实现之前，必须先完整理解整个模拟器结构，再改代码。

必须明确：

- 哪些修改落在 Python 层
- 哪些修改只是离线工具链新增
- 哪些修改只有扩展 ASTRA/Chakra 输出协议时才应触碰到底层

明确禁止的误改：

- 把 `controller.py` 当成主要 HBF 统计实现点
- 把 `logger.py` 当成业务统计汇总模块
- 把 HBF 简单当成 CPU/CXL 别名
- 在未理解 `Router -> Scheduler -> MemoryModel -> TraceGenerator -> ASTRA-Sim` 闭环前直接改 trace 或 memory 路径

## 8.3 唯一任务入口要求

- 后续新会话默认以 `modify/task1.md` 作为 Task 1 的唯一入口文档
- 如果 `modify/task1.md` 与 `modify/tasks_modified.md` 之间存在冲突，以 `modify/task1.md` 为准
- 原始 `modify/tasks.md` 不应再作为 Task 1 的主要执行依据

