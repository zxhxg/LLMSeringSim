# HBF 与 HBM+HBF 概念理解

## 对 HBF 的理解

在本项目中，HBF 应被建模为一种独立的、位于 GPU 侧的权重存储层，而不是 CPU/CXL 的别名，也不是简单的“另一种远端内存”。

对于模拟器而言，HBF 至少需要具备以下独立属性：

- 独立的 memory location type
- 独立的 bandwidth
- 独立的 latency
- 可配置的 device count
- 对访问请求具有独立的 queueing 与 contention 行为

HBF 最自然的职责，是承载那些无法长期常驻于 HBM、但又需要比主机侧更高吞吐的大容量模型权重。

当后续任务引入 sparse/page/block 级访问时，HBF 的语义应进一步升级为 request-granular weight layer。也就是说，HBF 不应只被视为 dense remote read source，而应被视为一个可以承载按请求粒度、按块粒度、按物理页粒度访问的权重层。

从当前代码现状看，`astra-sim` 与 Chakra 已经存在 `HBF_MEMORY` 相关支持。因此 Task 1 的工作重点不是“底层从零发明 HBF”，而是把 Python 侧的配置解析、placement 接入、统计输出和上层工具链补齐。

## 对 HBM + HBF 架构的理解

HBM 是本地高带宽工作内存，用于承载当前活跃数据。

HBF 是位于 HBM 之外、更深一层的 GPU 侧权重存储层，用于承载容量更大但访问代价更高的权重数据。

HBM + HBF 架构的本质不是两个存储名字的简单并列，而是一种层次化设计：

- 热数据保留在 HBM 中
- 更冷、更大容量的权重数据存放在 HBF 中
- 按层或按块从 HBF 拉取到计算路径中

模拟器应当能够捕捉以下三层语义：

- placement：哪些数据驻留在 HBM，哪些数据驻留在 HBF
- access pattern：访问 HBF 时采用什么模式，例如 dense 或 sparse、按层还是按块访问
- system effect：这些访问行为如何影响 per-layer latency、token latency、throughput 以及 bandwidth contention

对于 Task 1，HBM + HBF 框架的最小闭环是：

- 权重存放在 HBF 中
- 计算发生在 NPU/HBM 路径上
- 按层执行来自 HBF 的 dense 权重读取

对于 Step 5，完整的端到端体系应升级为：

逻辑稀疏访问  
→ layout / page 映射  
→ request materialization  
→ replay into simulator

## HBM 与 HBF 向 GPU die 供数的带宽处理

HBM 和 HBF 应先被视为两个独立 memory tier，但它们向 GPU die / compute path 供数时，不应默认完全独立。

更合理的抽象是两级建模：

- backend bandwidth：HBM 与 HBF 各自的后端带宽、延迟与排队行为
- frontend bandwidth：进入 GPU die 或计算路径时可能共享的前端带宽、fabric、路由或功耗预算

因此 Task 1 需要引入 `bw_mode` 参数，并支持三种模式：

- `shared_frontend`
  - 默认模式
  - HBM 和 HBF 是独立 memory tier，但通往 GPU die / compute path 的前端存在共享约束
  - 这是主实验默认模式，也是当前最接近真实实现的保守建模方式
- `fully_independent`
  - 理论乐观上界
  - HBM 与 HBF 可以并行供数，有效带宽可近似独立叠加
  - 用于评估更强独立并行供数能力下的性能上界
- `fully_serialized`
  - 理论悲观下界
  - HBM 与 HBF 的访问基本串行化处理
  - 用于评估极端共享路径条件下的性能下界

要求如下：

- 三种模式都必须可通过配置切换
- 默认模式必须为 `shared_frontend`
- 所有实验日志中必须记录当前使用的 `bw_mode`
- 主结果使用 `shared_frontend`
- `fully_independent` 和 `fully_serialized` 用于补充的上界/下界敏感性分析

# LLMServingSim 运行逻辑梳理

后续任何新会话在执行 Task 1 之前，必须先理解以下主链路，避免误改模块职责。

## 主执行闭环

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

## 模块职责边界

- `main.py`
  - 程序入口
  - 参数解析
  - 调度主循环
  - 最终汇总输出
- `config_builder.py`
  - 解析 cluster config
  - 生成 ASTRA-Sim 的 network/system/memory 配置
  - 解析 placement
- `Router`
  - 请求注入与实例路由
  - Prefill/Decode 之间的请求转移
- `Scheduler`
  - continuous batching
  - 请求队列管理
  - inflight batch 生命周期
- `MemoryModel`
  - 权重大小估算
  - NPU/CPU/CXL 内存占用管理
  - KV cache 与 prefix cache 行为
- `trace_generator.py`
  - 将 batch 展开成逐层执行 trace
  - 决定每层 weight/input/output 的 memory location
- `graph_generator.py`
  - 调 Chakra 转 graph
- `Controller`
  - ASTRA-Sim 进程通信
  - 解析 iteration 完成信息
- `ASTRA-Sim`
  - 系统级 timing、memory access、network 执行后端

## 对 Task 1 特别重要的责任划分

- HBF memory tier 的配置接入，主要落在 `config_builder.py`
- HBF 权重占用与统计，主要落在 `memory_model.py`
- HBF 读事件如何进入 trace，主要落在 `trace_generator.py`
- HBF 的最终统计展示，主要落在 `main.py` 或新增汇总逻辑
- `controller.py` 不应被当成主要 HBF 统计实现点，除非需要扩展 ASTRA-Sim 的 stdout 协议
- `logger.py` 不应被当成业务统计汇总模块，它主要负责日志格式

# 原 tasks 问题检查与修改意见

## 对原始文档的判断

- `modify/tasks.md` 文件内容本身是正常 UTF-8 中文，之前的乱码来自查看方式，不是源文件损坏
- 当前工作区不存在可直接使用的 `tasks/` 目录，因此所有新增文档默认落在 `modify/`
- 原始五步任务的总体方向是合理的，但存在“底层已有支持”和“上层仍需新增工具链”混写的问题

## 关键修订原则

- `tasks_modified.md` 必须同时充当任务说明书和接力文档，避免后续新会话只看文件名和局部 TODO 就直接动手
- HBF 不应被写成底层完全从零引入，因为当前 `astra-sim`/Chakra 已存在 `HBF_MEMORY`
- `controller.py` 不应被写成必然要改的核心点，除非需要新增 ASTRA-Sim 输出协议
- `logger.py` 不应被写成统计逻辑中心，统计应由主流程或专门汇总逻辑负责
- `bw_mode` 中的很多语义属于上层时间模型与策略抽象，不应误写成当前所有后端都已原生支持的现成功能
- Step 2 到 Step 4 更适合作为离线工具链，而不是直接塞进现有主循环

## 后续执行者禁止的误改

- 不要把 HBF 简单当成 CPU/CXL 别名
- 不要在未理解主执行闭环前直接改 `trace_generator.py`
- 不要把 `controller.py` 当成主要 HBF 统计实现点
- 不要把 `logger.py` 当成业务统计汇总模块
- 不要在未区分 Python 层、离线工具层、ASTRA/Chakra 底层职责前直接分散修改

# 修订后的五步任务清单

## Step 1：接入最小 HBM + HBF 路径，并支持 `bw_mode`

### 目标

- 在当前模拟器中正确实现 HBM + HBF 双层架构
- 正确引入 `bw_mode` 参数
- 支持三种带宽建模模式：
  - `shared_frontend`
  - `fully_independent`
  - `fully_serialized`
- 支持 HBM + HBF 配置运行
- 保持原有 HBM + CPU memory 路径兼容

### 当前代码落点

- `config_builder.py` 负责 cluster config、placement 与 memory config 生成
- `memory_model.py` 负责权重大小与内存占用
- `trace_generator.py` 负责逐层 trace 生成
- `main.py` 负责参数入口与汇总输出

### 需要修改或新增的内容

- `cluster_config/README.md`
  - 新增 HBF 配置说明
  - 新增 `bw_mode` 说明
- `cluster_config/`
  - 新增 `single_node_hbf_instance.json`
  - 新增至少三组 HBM + HBF 配置，分别对应三种 `bw_mode`
- `config_builder.py`
  - 识别 `hbf_mem`
  - 识别 `weights: hbf:x`
  - 将 HBF tier 注入 ASTRA-Sim memory config
  - 将 `bw_mode` 透传到上层时间模型使用位置
- `memory_model.py`
  - 正确区分 HBM 常驻权重与 HBF 权重
  - 新增 HBF 统计字段
  - 重算初始权重占用，避免仍默认把全部权重算进 NPU 常驻内存
- `trace_generator.py`
  - 当层权重位于 HBF 时生成对应读事件
  - 最小版本按 dense full read 建模
  - 支持三种 `bw_mode` 下的时间修正
- `main.py`
  - 增加 HBF 与 `bw_mode` 相关参数
  - 输出 HBF 统计与当前 `bw_mode`

### Step 1 最小闭环

- 权重位于 HBF
- 计算发生在 NPU/HBM 路径
- 每层执行一次 dense HBF read
- 输出 HBF bytes、HBF requests、HBF time、latency、throughput

### 验收标准

- 能读取 `weights: hbf:0`
- 能正确识别 HBF 为独立 memory tier
- 能在三种 `bw_mode` 下成功运行
- 原始 HBM + CPU memory 配置不被破坏
- 输出中包含 HBF 统计字段与当前 `bw_mode`

## Step 2：在真实推理框架中提取逻辑访问 trace

### 目标

不要在模拟器中直接猜 sparse 访问，而是通过真实模型推理提取逻辑 block 访问需求。

### 新增工具目录

`tools/trace_collection/`

### 建议文件

- `collect_logical_trace.py`
- `block_partition.py`
- `sparsity_driver.py`

### 输出要求

- 输出 JSONL
- 每条记录至少包含：`model`、`phase`、`step`、`layer_id`、`layer_type`、`sparsity_ratio`、`block_size`、`selected_blocks`、`selected_block_count`

### 验收标准

- 能稳定输出逻辑 trace
- trace 中不包含 layout、physical page、scheduling

## Step 3：离线做 layout / placement / mapping

### 目标

把逻辑 block 访问转换成物理 page 访问与放置结果。

### 新增工具目录

`tools/layout_mapping/`

### 建议文件

- `build_layout.py`
- `coaccess_stats.py`
- `apply_mapping.py`

### 输出要求

- touched pages
- page ranges
- segment count
- average segment length
- real bytes read
- page amplification

### 验收标准

- 同一 logical trace 在不同 layout 下得到不同 physical trace
- `coaccess_layout` 能有效降低 segment count

## Step 4：离线做 scheduling / request materialization

### 目标

把 physical trace 进一步转成最终 HBF 请求流，并在这一层正式应用 `bw_mode` 的时间模型。

### 新增工具目录

`tools/scheduling/`

### 建议文件

- `materialize_requests.py`
- `request_cost_model.py`
- `summarize_requests.py`

### 需要支持的 policy

- `dense_full`
- `naive_sparse`
- `grouped_sparse`
- `dense_over_sparse`

### 需要支持的 `bw_mode`

- `shared_frontend`
- `fully_independent`
- `fully_serialized`

### 验收标准

- 能从 physical trace 生成 request trace
- 不同 policy 的请求数和时间模型结果可区分
- 三种 `bw_mode` 的结果可区分

## Step 5：将离线结果接回模拟器，完成 end-to-end replay

### 目标

让 LLMServingSim 不再直接猜 sparse 访问，而是吃已经 materialized 的 HBF request stats / request traces。

### 主要修改位置

- `trace_generator.py`
  - 优先读取 request stats
- `main.py`
  - 新增 `--hbf-request-stats`
  - 新增 `--hbf-policy`
  - 新增 `--hbf-bw-mode`
- 汇总输出逻辑
  - 输出 per-request / per-layer HBF 统计
  - 输出不同 policy 与不同 `bw_mode` 的端到端结果

### 验收标准

- 能读 request stats 文件
- 能输出不同 HBF policy 的 end-to-end latency
- 能输出三种 `bw_mode` 下的上下界结果

# Task 1 自动化测试与验收流程

## 总体目标

Task 1 的目标是：

- 在当前模拟器中正确实现 HBM + HBF 双层架构
- 正确引入 `bw_mode` 参数，并支持以下三种带宽建模模式：
  - `shared_frontend`
  - `fully_independent`
  - `fully_serialized`
- 保证新功能在现有环境中可以正常运行
- 保持对原有 HBM + CPU memory 配置的兼容性
- 在完成全部测试后输出修改说明和性能对比文档

## 测试平台要求

- 使用当前正在运行的容器作为唯一实验平台
- 不要新建额外环境
- 不要假设用户会重新配置依赖
- 在任务开始前，必须先验证当前环境是否能够正常运行
- 环境验证必须使用官方文档中的示例命令
- 如果环境验证失败，必须先定位失败原因并尝试修复与当前任务直接相关的问题
- 不允许跳过环境验证直接进入功能开发

## 执行前前置条件

除了 Step 0 的环境验证外，后续执行者在真正实现 Task 1 前，必须先阅读本文件中的以下两节：

- `HBF 与 HBM+HBF 概念理解`
- `LLMServingSim 运行逻辑梳理`

只有在理解 HBF、HBM+HBF 框架以及模拟器主链路之后，才允许进入代码实现。

## 测试执行顺序

### Step 0：环境可用性验证

- 阅读仓库 `README.md` 和官方运行说明
- 找到官方文档中的最小示例命令
- 在当前容器中执行该示例命令
- 验证输出是否正常

验收标准：

- 命令成功执行
- 无依赖错误
- 无路径错误
- 无配置文件缺失错误
- 能生成基础运行输出

只有 Step 0 成功，才允许开始 Task 1 的功能实现。

### Step 1：实现 Task 1 功能

实现范围包括：

- 引入 HBF memory tier
- 引入 `bw_mode` 参数
- 支持三种带宽模式
- 支持 HBM + HBF 配置运行
- 保持原有 HBM + CPU memory 路径不被破坏

### Step 2：为测试生成配置文件与运行命令

至少需要准备以下四组配置：

- 配置 A：HBM + HBF，`bw_mode = shared_frontend`
- 配置 B：HBM + HBF，`bw_mode = fully_independent`
- 配置 C：HBM + HBF，`bw_mode = fully_serialized`
- 配置 D：原始 HBM + CPU memory 配置

要求：

- 每组配置都必须有明确的配置文件
- 每组配置都必须有明确的运行命令
- 配置与命令必须写入最终文档

### Step 3：执行四组配置测试

依次运行配置 A / B / C / D，并对输出进行检查。

每组测试至少需要检查以下内容：

- 程序是否正常结束
- 是否存在报错、异常退出、空输出
- 是否正确加载预期配置
- 日志中是否显示当前 memory tier 配置
- 日志中是否显示当前 `bw_mode`

HBM + HBF 配置额外检查项：

- HBF 是否被正确识别为独立 memory tier
- 权重读取是否走 HBF 路径
- HBF 相关统计是否存在
- 三种 `bw_mode` 下运行结果是否可区分

HBM + CPU memory 配置额外检查项：

- 原有 CPU memory 路径是否仍可正常运行
- 不引入 HBF 时是否没有副作用
- 输出结果是否与原有行为保持一致或至少逻辑一致

## 性能结果的预期关系检查

对 HBM + HBF 三种模式，在其余配置一致的情况下，预期关系如下：

若指标是 latency：

`fully_independent <= shared_frontend <= fully_serialized`

若指标是 throughput：

`fully_independent >= shared_frontend >= fully_serialized`

如果结果不满足这个大致关系：

- 必须检查实现是否正确
- 必须检查日志和配置是否真的生效
- 不允许直接忽略异常结果

HBM + CPU memory 配置的作用不是参与三种 `bw_mode` 上下界比较，而是：

- 验证原有功能没有被破坏
- 作为对照组，观察 HBM + HBF 新架构的行为差异
- 确认引入 HBF 后没有影响原本的 CPU memory 路径

## 自动化测试通过条件

只有满足以下所有条件，Task 1 才能视为完成：

- 官方示例命令验证通过
- HBM + HBF 的三种 `bw_mode` 都能成功运行
- 原始 HBM + CPU memory 配置能成功运行
- 四组配置都能生成有效输出
- HBF 相关统计项能在输出中体现
- 三种 `bw_mode` 的性能关系总体符合预期
- 没有明显的运行时错误、配置错误或逻辑错误
- 最终文档已写入 `modify/` 目录

## 停止条件

只有在以下条件全部满足时，才可以停止：

- 所有功能测试都已完成
- 所有关键输出都已核验
- 没有未解决的严重问题
- 最终文档已经生成并写入 `modify/`

以下情况不允许直接结束任务：

- 只完成代码修改，没有完成测试
- 只完成部分模式测试
- 没有验证原始 HBM + CPU memory 配置
- 没有检查性能关系是否合理
- 没有输出最终说明文档

## 最终文档要求

在所有测试完成后，必须在 `modify/` 目录下生成总结文档：

`modify/task1_test_report.md`

文档必须包含以下内容：

### 1. 本次修改内容

- 修改了哪些文件
- 每个文件做了什么修改
- 新增了哪些配置项
- 新增了哪些 HBF 相关逻辑
- 如何实现 `bw_mode`

### 2. 测试环境说明

- 使用的是当前运行容器
- 执行了哪个官方示例命令作为环境验证
- 环境验证结果如何

### 3. 测试配置列表

列出四组配置：

- HBM + HBF + `shared_frontend`
- HBM + HBF + `fully_independent`
- HBM + HBF + `fully_serialized`
- HBM + CPU memory

并给出：

- 配置文件路径
- 运行命令

### 4. 测试结果

至少包含：

- 是否运行成功
- 关键日志或输出摘要
- latency / throughput / HBF traffic 等关键指标
- 三种模式结果是否符合预期关系

### 5. 结论

- Task 1 是否完成
- 当前实现是否可进入下一阶段
- 是否还有遗留问题或后续建议

### 6. 报告开头的额外要求

报告开头必须简短回顾以下理解，证明实现者不是在黑箱改代码：

- 对 HBF 的理解
- 对 HBM + HBF 架构的理解
- 对模拟器主链路的理解

# 修改文档要求

这部分要求面向接手 Task 1 的后续 Codex 新会话，而不是面向普通读者。

## 1. 面向新会话的可接力性要求

- 文档必须写到让 Codex 新会话在不依赖当前对话上下文的情况下，也能完整理解 Task 1 要做什么
- 文档必须明确解释：
  - Task 1 的目标边界
  - HBF 的概念
  - HBM + HBF 架构的概念
  - `bw_mode` 三种模式的含义与用途
  - 为什么 `shared_frontend` 是主实验默认模式
  - Task 1 的测试完成条件
- 文档不能只写“改哪些文件”，还必须写“为什么这样改、这些改动在 HBM+HBF 语义里分别承担什么职责”

## 2. 面向新会话的防误改要求

- 任何新会话在执行 Task 1 之前，必须先完整理解整个模拟器的运行结构，再开始改代码
- 必须把以下主链写清楚，让后续执行者知道哪些模块是控制面、哪些模块是执行面：
  - `main.py`
  - `config_builder.py`
  - `Router`
  - `Scheduler`
  - `MemoryModel`
  - `trace_generator.py`
  - `graph_generator.py`
  - `Controller`
  - `ASTRA-Sim`
- 文档必须明确指出：
  - 哪些修改应落在 Python 层
  - 哪些修改只是离线工具链新增
  - 哪些修改只有在扩展 ASTRA/Chakra 输出协议时才应触碰到底层
- 文档必须显式警告后续执行者不要做这些误改：
  - 把 `controller.py` 当成主要 HBF 统计实现点
  - 把 `logger.py` 当成业务统计汇总模块
  - 把 HBF 简单当成 CPU/CXL 别名
  - 在未理解 `Router -> Scheduler -> MemoryModel -> TraceGenerator -> ASTRA-Sim` 闭环前直接改 trace 或 memory 路径

## 3. 唯一任务入口要求

- 后续新会话默认以 `modify/tasks_modified.md` 作为唯一任务入口文档
- 不应回头混用原 `modify/tasks.md` 作为主要执行依据
- 如果原始任务与本文件冲突，以本文件为准

