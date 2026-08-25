# 日志栈部署环境变量（v1）

完整文档与 ops 工作区 `DEPLOY-ENV.md` 同步。版本见 `versions.env`。

## 多副本

**logstash / kibana 扩 `replicas: 2` 不需要额外环境变量**，与 1 副本用同一套 env。

## logstash-service

| 变量 | 默认值 | 示例 |
| --- | --- | --- |
| `KAFKA_SERVER` | `kafka:9092` | `10.0.1.11:9092,10.0.1.12:9092` |
| `ES_SERVER` | `http://elasticsearch:9200` | 同左 |

## kibana-service

| 变量 | 默认值 | 示例 |
| --- | --- | --- |
| `ES_SERVER` | `http://elasticsearch:9200` | 同左 |
| `KIBANA_PUBLIC_URL` | （可选） | `http://1.1.1.1/v1/agent/kibana` |

详见 ops 根目录 `DEPLOY-ENV.md`（含 Filebeat、ES、Kafka、Grafana 说明与多副本示例）。
