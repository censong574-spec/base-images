# 日志栈部署环境变量（v1）

面向 **容器运行时** 配置，不是镜像编译参数。版本钉死见本仓库 `versions.env`（Elastic **8.19.20**）。

---

## 多副本要不要加环境变量？

| 服务 | 多副本（如 `replicas: 2`） | 说明 |
| --- | --- | --- |
| **logstash-service** | **不需要** 额外变量 | 副本共用同一套 `KAFKA_SERVER`、`ES_SERVER`；`group_id` 固定 `ai-logstash`（写在镜像模板里，不要按 Pod 改） |
| **kibana-service** | **不需要** 额外变量 | 无状态，副本共用 `ES_SERVER`；可选同一个 `KIBANA_PUBLIC_URL` |
| **filebeat-service** | 按业务 Pod 部署 | 每个业务一份 ConfigMap，不是简单调 `replicas` |
| **elasticsearch-service** | **需要** 集群级配置 | 另见下文 ES 小节 |
| **kafka-service**（自建） | **需要** 每节点不同变量 | 如 `KAFKA_NODE_ID`；用华为云 Kafka 则不用部署此服务 |
| **grafana-service** | **不需要** 额外变量 | 多副本共用 `ES_SERVER`、`SQL_SERVER`、`SQL_PASSWD`；`GF_PATHS_DATA` 挂 SFS PVC |

**结论：** Logstash / Kibana / Grafana 扩到 2 个副本时，**环境变量与 1 副本完全相同**，只改编排里的 `replicas` 即可。

---

## logstash-service

启动时由 `runtime/start.sh` 根据模板生成 pipeline，**只需 2 个变量**：

| 变量 | 必填 | 默认值 | 示例 | 说明 |
| --- | --- | --- | --- | --- |
| `KAFKA_SERVER` | 生产建议必填 | `kafka:9092` | `10.0.1.11:9092,10.0.1.12:9092,10.0.1.13:9092` | Kafka **bootstrap** 地址，集群用英文逗号分隔，**不要空格** |
| `ES_SERVER` | 生产建议必填 | `http://elasticsearch:9200` | `http://elasticsearch:9200` | 写入 Elasticsearch 的 URL，与 kibana-service 同名 |

可选（一般不用改）：

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `LS_JAVA_OPTS` | `-Xms512m -Xmx512m` | JVM 堆 |
| `LOGSTASH_PIPELINE_TEMPLATE` | `/opt/ai/logstash/pipeline/logstash.conf.template` | 模板路径 |
| `LOGSTASH_PIPELINE` | `/opt/ai/logstash/generated/logstash.conf` | 生成后的 pipeline 路径 |

### 多副本示例（2 个 Logstash）

```yaml
replicas: 2
env:
  - name: KAFKA_SERVER
    value: "kafka-0.kafka:9092,kafka-1.kafka:9092,kafka-2.kafka:9092"
  - name: ES_SERVER
    value: "http://elasticsearch:9200"
```

注意：

- **不要**给每个 Pod 不同的 `group_id`（模板里已固定 `ai-logstash`）。
- 副本数 ≤ Kafka 对应 topic 的**分区数**。
- 使用华为云 Kafka 时，把 `KAFKA_SERVER` 换成控制台提供的 bootstrap 地址；若开启 SASL/SSL，当前镜像尚未支持，需后续扩展。

---

## kibana-service

| 变量 | 必填 | 默认值 | 示例 | 说明 |
| --- | --- | --- | --- | --- |
| `ES_SERVER` | 生产建议必填 | `http://elasticsearch:9200` | `http://elasticsearch:9200` | Kibana 连接 Elasticsearch（`start.sh` 转为 `ELASTICSEARCH_HOSTS`） |
| `KIBANA_PUBLIC_URL` | 否 | （不设置） | `http://1.1.1.1/v1/agent/kibana` | 经 API 网关对外访问时的完整 URL；`start.sh` 自动拆成 `basePath` / `publicBaseUrl` |

仅集群内访问、不走网关时：**只配 `ES_SERVER`**，不配 `KIBANA_PUBLIC_URL`。

### 多副本示例（2 个 Kibana）

```yaml
replicas: 2
env:
  - name: ES_SERVER
    value: "http://elasticsearch:9200"
  # 若经 service-router 暴露：
  # - name: KIBANA_PUBLIC_URL
  #   value: "http://1.1.1.1/v1/agent/kibana"
```

---

## filebeat-service（参考）

每个业务单独配置，典型字段：

| 配置项 | 示例 | 说明 |
| --- | --- | --- |
| `output.kafka.hosts` | `["kafka:9092"]` 或华为云 bootstrap | 与 Logstash 的 `KAFKA_SERVER` 指向同一集群 |
| `fields.log_topic` | `agentlink` | 写入的 **topic 名**，须在 Logstash 模板 `topics` 列表中 |
| `fields.cluster_name` | `ai-prod-cce` | 集群标识，便于 Grafana 过滤 |

模板文件：`FileBeat/kubernetes/filebeat-configmap-template.yaml`

---

## elasticsearch-service（自建时参考）

当前镜像默认 **单节点** PoC（`discovery.type=single-node`）。上生产多节点需单独改造，运行时常见变量：

| 变量 | 说明 |
| --- | --- |
| `ES_JAVA_OPTS` | 堆内存，如 `-Xms2g -Xmx2g` |
| `ES_PATH_DATA` | 数据目录，需挂 PVC |

集群发现（`seed_hosts`、`initial_master_nodes` 等）尚未 env 化，多节点部署前需改镜像或挂 `elasticsearch.yml`。

---

## kafka-service（自建时参考；用华为云可跳过）

| 变量 | 单节点默认 | 多节点说明 |
| --- | --- | --- |
| `KAFKA_NODE_ID` | `1` | 每 broker **唯一** |
| `KAFKA_CONTROLLER_QUORUM_VOTERS` | `1@localhost:9093` | 固定 3 个 controller 地址 |
| `KAFKA_ADVERTISED_LISTENERS` | `PLAINTEXT://localhost:9092` | 每 broker 自己的地址 |
| `KAFKA_CLUSTER_ID` | 自动生成 | 首次建集群时全集群一致 |

---

## grafana-service

启动时由 `runtime/start.sh` 渲染 ES 数据源模板；配置 PostgreSQL 后多副本共享用户、仪表盘等元数据。

| 变量 | 必填 | 默认值 | 示例 | 说明 |
| --- | --- | --- | --- | --- |
| `ES_SERVER` | 生产建议必填 | `http://elasticsearch:9200` | `http://elasticsearch:9200` | 写入 provisioning 的 Elasticsearch 数据源 URL |
| `SQL_SERVER` | 多副本必填 | （不设置则用 SQLite） | `postgres:5432` | PostgreSQL 地址，格式 `host:port`；库名与用户固定为 **grafana** / **grafana** |
| `SQL_PASSWD` | 配了 `SQL_SERVER` 时必填 | — | `your-secret` | `grafana` 用户的密码 |
| `SQL_SSL_MODE` | 否 | `disable` | `require` | 对应 `GF_DATABASE_SSL_MODE` |
| `GRAFANA_PUBLIC_URL` | 否 | （不设置） | `http://1.1.1.1/v1/agent/grafana` | 经网关对外访问时的完整 URL（`GF_SERVER_ROOT_URL` / 子路径） |

### PostgreSQL 预置（用户与库均为 grafana）

多副本前在 PostgreSQL 执行（密码与 Secret 中 `SQL_PASSWD` 一致）：

```sql
CREATE USER grafana WITH PASSWORD 'your-secret';
CREATE DATABASE grafana OWNER grafana;
```

`start.sh` 固定 `GF_DATABASE_USER=grafana`、`GF_DATABASE_NAME=grafana`，**不可通过环境变量覆盖**。

### 存储（SFS PVC）

- 将 **华为云 SFS** 的 PVC 挂到容器 **`/var/lib/grafana`**（`GF_PATHS_DATA`）。
- 多副本时：**元数据在 PostgreSQL**，PVC 主要用于插件、缓存等本地路径；各 Pod 可共享同一 SFS 卷。
- 单副本且未配 `SQL_SERVER` 时仍可用 SQLite（数据在 PVC 内），生产多副本请务必使用 PostgreSQL。

### 多副本示例（2 个 Grafana）

```yaml
replicas: 2
volumeMounts:
  - name: grafana-data
    mountPath: /var/lib/grafana
volumes:
  - name: grafana-data
    persistentVolumeClaim:
      claimName: grafana-sfs-pvc   # SFS StorageClass
env:
  - name: ES_SERVER
    value: "http://elasticsearch:9200"
  - name: SQL_SERVER
    value: "postgres.default.svc:5432"
  - name: SQL_PASSWD
    valueFrom:
      secretKeyRef:
        name: grafana-db
        key: password
  # 若经 service-router 暴露：
  # - name: GRAFANA_PUBLIC_URL
  #   value: "http://1.1.1.1/v1/agent/grafana"
```

---

## 变量命名约定（v1）

| 变量 | 用途 |
| --- | --- |
| `ES_SERVER` | **所有**连 Elasticsearch 的服务统一使用（Kibana、Logstash、Grafana） |
| `KAFKA_SERVER` | Logstash（及 Filebeat）连 Kafka bootstrap |
| `KIBANA_PUBLIC_URL` | 仅 Kibana 网关对外 URL |
| `GRAFANA_PUBLIC_URL` | 仅 Grafana 网关对外 URL |
| `SQL_SERVER` / `SQL_PASSWD` | Grafana 连 PostgreSQL（多副本） |

---

## 最小联调清单

```text
Filebeat  →  Kafka（与 KAFKA_SERVER 同集群）
              ↓
Logstash  →  KAFKA_SERVER + ES_SERVER，replicas≥1
              ↓
ES        ←  ES_SERVER
Kibana    →  ES_SERVER（+ 可选 KIBANA_PUBLIC_URL）
Grafana   →  ES_SERVER + SQL_SERVER/SQL_PASSWD（多副本）；PVC 挂 /var/lib/grafana（SFS）
```

---

## 相关文档

- `STACK.md` — 版本矩阵
- `kibana-service` / `LogStash` / `grafana-service` 各仓库 `README.md`
