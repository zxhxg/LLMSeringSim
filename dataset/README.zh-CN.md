# dataset

该目录包含作为 LLMServingSim 输入 workload 的请求数据集。

## 格式

数据集以 `.jsonl` 文件存储（每行一个 JSON 对象）。每一行表示一个请求，包含以下字段：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `input_toks` | Integer | 输入（prompt）token 数量 |
| `output_toks` | Integer | 输出（生成）token 数量 |
| `arrival_time_ns` | Float | 请求到达时间，单位为纳秒 |
| `input_tok_ids` | List[Integer] | 输入序列的 token ID（用于前缀缓存匹配） |

示例：

```json
{"input_toks": 128, "output_toks": 512, "arrival_time_ns": 0.0, "input_tok_ids": [1, 2, 3]}
```

## 已提供的数据集

| 文件 | 说明 |
| --- | --- |
| `example_trace.jsonl` | 用于快速测试的小型示例 trace |
| `sharegpt_req100_rate10_llama.jsonl` | 100 条 ShareGPT 请求，到达率为 10，使用 Llama tokenizer |
| `sharegpt_req100_rate10_mixtral.jsonl` | 100 条 ShareGPT 请求，到达率为 10，使用 Mixtral tokenizer |
| `sharegpt_req100_rate10_phi.jsonl` | 100 条 ShareGPT 请求，到达率为 10，使用 Phi tokenizer |
| `sharegpt_req300_rate10_llama.jsonl` | 300 条 ShareGPT 请求，到达率为 10，使用 Llama tokenizer |
| `sharegpt_req300_rate10_mixtral.jsonl` | 300 条 ShareGPT 请求，到达率为 10，使用 Mixtral tokenizer |
| `sharegpt_req300_rate10_phi.jsonl` | 300 条 ShareGPT 请求，到达率为 10，使用 Phi tokenizer |
| `fixed_in128_out512_req256_rate10.jsonl` | 定长请求：128 输入、512 输出、256 个请求 |
| `fixed_in128_out512_req512_rate10.jsonl` | 定长请求：128 输入、512 输出、512 个请求 |
| `sharegpt_pulse_req10_n3_delay60.jsonl` | 用于前缀缓存评估的突发式 ShareGPT trace |
| `sharegpt_pulse_req50_n6_delay15_pc.jsonl` | 用于前缀缓存评估的突发式 ShareGPT trace |
| `prefix_pool_stress.jsonl` | 用于二级前缀缓存池化的压力测试 trace |

## 生成自定义数据集

使用 `sharegpt_parser.py` 将 ShareGPT 对话数据转换为 `.jsonl` 格式：

```bash
python dataset/sharegpt_parser.py
```

若要手动创建数据集，请按照上述格式将 JSON 对象写入 `.jsonl` 文件，并通过 `main.py` 的 `--dataset` 传入该文件路径。
