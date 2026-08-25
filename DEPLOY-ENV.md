# 日志栈部署环境变量（v1）

面向 **容器运行时** 配置，不是镜像编译参数。版本钉死见本仓库 `versions.env`（Elastic **8.19.20**）。

---

## 多副本要不要加环境变量？

| 服务 | 多副本（如 `replicas: 2`） | 说明 |
| --- | --- | --- |
| **logstash-service** | **不需要** 额外变量 | 副本共用同一套 `KAFKA_SERVER`、`ES_SERVER`；`group_id` 固定 `ai-logstash`（写在镜像模板里，不要按 Pod 改） |
| **kibana-service** | **不需要** 额外变量 | 无状态，副本共用 `ES_SERVER`；可选同一个 `KIBANA_PUBLIC_URL` |
| **filebeat-service** | 按业务 Pod 部署 | 每个业务一份 ConfigMap，不是简单调 `replicas` |
| **elasticsearch-service** | 多节点时 **`ES_NODE_NAME` 每 Pod 不同** | 不配 `ES_SEED_HOSTS` = 单节点；配了 = 集群；数据目录每 Pod 一块 **EVS PVC** |
| **kafka-service**（自建） | 多节点时 **`KAFKA_NODE_ID` 每 Pod 不同** | 单 voter = 单节点；多 voter = KRaft 集群；`KAFKA_CLUSTER_ID` 多节点必填；每 Pod 一块 **EVS PVC** |
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

## elasticsearch-service

`runtime/start.sh` 在启动时生成 `elasticsearch.yml`。不配 `ES_SEED_HOSTS` 为**单节点**；配置后为**多节点**（适合 CCE 有状态负载 StatefulSet）。

| 变量 | 单节点 | 多节点 | 默认值 | 示例 | 说明 |
| --- | --- | --- | --- | --- | --- |
| `ES_CLUSTER_NAME` | 必填 | 必填 | `ai-log-cluster` | `ai-log-cluster` | 集群名，所有节点相同 |
| `ES_NODE_NAME` | 可选 | **每 Pod 不同** | `hostname` | `es-0` | 节点名；多节点建议用 `metadata.name` 注入 |
| `ES_SEED_HOSTS` | **不设置** | 必填 | — | `es-0.es-headless:9300,es-1.es-headless:9300,es-2.es-headless:9300` | 发现地址，英文逗号分隔，**无空格** |
| `ES_INITIAL_MASTER_NODES` | 不设置 | 首次建集群必填 | — | `es-0,es-1,es-2` | 与 `ES_NODE_NAME` 一致；集群已形成后可去掉 |
| `ES_PATH_DATA` | 必填 | 必填 | `/usr/share/elasticsearch/data` | 同上 | 数据目录；**每 Pod 独立 EVS PVC**，不要用 SFS |
| `ES_JAVA_OPTS` | 建议 | 建议 | `-Xms2g -Xmx2g` | `-Xms4g -Xmx4g` | JVM 堆；持续 ~1k 条/s 日志建议 4g+ |

**客户端**仍用 `ES_SERVER`（如 `http://elasticsearch:9200`）连 ClusterIP Service，不要直连单个 Pod。

### 存储（EVS PVC）

- CCE **有状态负载** + `volumeClaimTemplates`，`storageClassName: csi-disk`（云硬盘）。
- 每个 Pod 一块盘，挂到 `/usr/share/elasticsearch/data`。
- **不要**用 SFS 共享卷（Grafana 才用 SFS）。

### CCE 服务（单节点与多节点相同）

需要两个 Service：

1. **Headless**（`clusterIP: None`）— 节点间 9300 发现，DNS：`es-0.es-headless`、`es-1.es-headless`…
2. **ClusterIP** `elasticsearch:9200` — Kibana / Logstash / Grafana 的 `ES_SERVER`

### 单节点示例（有状态负载 replicas: 1）

```yaml
apiVersion: v1
kind: Service
metadata:
  name: es-headless
spec:
  clusterIP: None
  selector:
    app: elasticsearch
  ports:
    - port: 9300
      name: transport
---
apiVersion: v1
kind: Service
metadata:
  name: elasticsearch
spec:
  selector:
    app: elasticsearch
  ports:
    - port: 9200
      name: http
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: es
spec:
  serviceName: es-headless
  replicas: 1
  selector:
    matchLabels:
      app: elasticsearch
  template:
    metadata:
      labels:
        app: elasticsearch
    spec:
      containers:
        - name: elasticsearch
          image: your-registry/elasticsearch-service:8.19.20
          env:
            - name: ES_CLUSTER_NAME
              value: ai-log-cluster
            - name: ES_NODE_NAME
              valueFrom:
                fieldRef:
                  fieldPath: metadata.name
            - name: ES_JAVA_OPTS
              value: "-Xms4g -Xmx4g"
          volumeMounts:
            - name: es-data
              mountPath: /usr/share/elasticsearch/data
  volumeClaimTemplates:
    - metadata:
        name: es-data
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: csi-disk
        resources:
          requests:
            storage: 200Gi
```

不配 `ES_SEED_HOSTS` → `discovery.type: single-node`。索引副本数请设 `number_of_replicas: 0`。

### 多节点示例（有状态负载 replicas: 3）

在单节点基础上 `replicas: 3`，并增加：

```yaml
env:
  - name: ES_SEED_HOSTS
    value: "es-0.es-headless:9300,es-1.es-headless:9300,es-2.es-headless:9300"
  - name: ES_INITIAL_MASTER_NODES
    value: "es-0,es-1,es-2"
```

StatefulSet 名为 `es` 时 Pod 名为 `es-0`、`es-1`、`es-2`；若名为 `elasticsearch`，则改为 `elasticsearch-0.es-headless:9300` 等。

3 节点时索引 `number_of_replicas: 1` 可达 green。

---

## kafka-service

KRaft 模式（`broker,controller` 合一）。`runtime/start.sh` 根据 `KAFKA_CONTROLLER_QUORUM_VOTERS` 判断单节点 / 多节点。用华为云托管 Kafka 时可跳过本节，只配 `KAFKA_SERVER`。

| 变量 | 单节点 | 多节点 | 默认值 | 示例 | 说明 |
| --- | --- | --- | --- | --- | --- |
| `KAFKA_CONTROLLER_QUORUM_VOTERS` | 1 个 voter | 3 个 voter | `1@localhost:9093` | 见下方示例 | 所有 Pod **相同**；voter 数 >1 即为集群模式 |
| `KAFKA_CLUSTER_ID` | 可自动生成 | **必填且所有 Pod 相同** | 自动生成 | `MkU3OEVBNTcwNTJENDM2Qk` | `kafka-storage.sh random-uuid` 生成一次写入 Secret |
| `KAFKA_NODE_ID` | `1` | **每 Pod 不同** | 从 Pod 名推导 | `1` / `2` / `3` | `kafka-0`→`1`，`kafka-1`→`2`；可显式覆盖 |
| `KAFKA_ADVERTISED_LISTENERS` | 可选 | 可选 | Pod FQDN | `PLAINTEXT://kafka-0.kafka-headless:9092` | 未设置时自动 `PLAINTEXT://<hostname-fqdn>:9092` |
| `KAFKA_LOG_DIRS` | 必填 | 必填 | `/var/lib/kafka/data` | 同上 | 日志目录；**每 Pod 独立 EVS PVC** |
| `KAFKA_LOG_RETENTION_HOURS` | 可选 | 可选 | `24` | `168` | 消息保留时间 |
| `KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR` | 自动 `1` | 自动 = voter 数 | — | `3` | 多节点默认 3，可覆盖 |

**客户端**（Logstash、Filebeat）用 **`KAFKA_SERVER`**（bootstrap，逗号分隔，无空格），不是 `KAFKA_ADVERTISED_LISTENERS`。

### 存储（EVS PVC）

- CCE **有状态负载** + `volumeClaimTemplates`，`storageClassName: csi-disk`。
- 每个 Pod 一块盘，挂到 `/var/lib/kafka/data`。
- **不要**用 SFS 共享卷。

### 生成 KAFKA_CLUSTER_ID（多节点首次部署）

```bash
/opt/kafka/bin/kafka-storage.sh random-uuid
```

写入 Secret，所有 Pod 引用同一值。

### CCE 服务（单节点与多节点相同）

1. **Headless** `kafka-headless` — `9092`（broker）、`9093`（controller）
2. **ClusterIP** `kafka:9092` — 单节点时可选作 bootstrap

### 单节点示例（有状态负载 replicas: 1）

```yaml
apiVersion: v1
kind: Service
metadata:
  name: kafka-headless
spec:
  clusterIP: None
  selector:
    app: kafka
  ports:
    - port: 9092
      name: broker
    - port: 9093
      name: controller
---
apiVersion: v1
kind: Service
metadata:
  name: kafka
spec:
  selector:
    app: kafka
  ports:
    - port: 9092
      name: broker
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: kafka
spec:
  serviceName: kafka-headless
  replicas: 1
  selector:
    matchLabels:
      app: kafka
  template:
    metadata:
      labels:
        app: kafka
    spec:
      containers:
        - name: kafka
          image: your-registry/kafka-service:3.9.2
          env:
            - name: KAFKA_CONTROLLER_QUORUM_VOTERS
              value: "1@localhost:9093"
            - name: KAFKA_NODE_ID
              value: "1"
          volumeMounts:
            - name: kafka-data
              mountPath: /var/lib/kafka/data
  volumeClaimTemplates:
    - metadata:
        name: kafka-data
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: csi-disk
        resources:
          requests:
            storage: 50Gi
```

Logstash `KAFKA_SERVER`: `kafka:9092`

### 多节点示例（有状态负载 replicas: 3）

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: kafka-cluster-id
type: Opaque
stringData:
  cluster-id: "MkU3OEVBNTcwNTJENDM2Qk"
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: kafka
spec:
  serviceName: kafka-headless
  replicas: 3
  selector:
    matchLabels:
      app: kafka
  template:
    metadata:
      labels:
        app: kafka
    spec:
      containers:
        - name: kafka
          image: your-registry/kafka-service:3.9.2
          env:
            - name: KAFKA_CLUSTER_ID
              valueFrom:
                secretKeyRef:
                  name: kafka-cluster-id
                  key: cluster-id
            - name: KAFKA_CONTROLLER_QUORUM_VOTERS
              value: "1@kafka-0.kafka-headless:9093,2@kafka-1.kafka-headless:9093,3@kafka-2.kafka-headless:9093"
          volumeMounts:
            - name: kafka-data
              mountPath: /var/lib/kafka/data
  volumeClaimTemplates:
    - metadata:
        name: kafka-data
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: csi-disk
        resources:
          requests:
            storage: 100Gi
```

Logstash `KAFKA_SERVER`:

```text
kafka-0.kafka-headless:9092,kafka-1.kafka-headless:9092,kafka-2.kafka-headless:9092
```

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
| `ES_CLUSTER_NAME` / `ES_SEED_HOSTS` / `ES_NODE_NAME` | Elasticsearch 集群（多节点） |
| `KAFKA_CONTROLLER_QUORUM_VOTERS` / `KAFKA_CLUSTER_ID` | Kafka KRaft 集群（多节点） |

---

## 最小联调清单

```text
Filebeat  →  Kafka（KAFKA_SERVER bootstrap）
              ↓
Logstash  →  KAFKA_SERVER + ES_SERVER，replicas≥1
              ↓
ES        ←  ES_PATH_DATA 挂 EVS PVC；多节点配 ES_SEED_HOSTS；客户端用 ES_SERVER
Kibana    →  ES_SERVER（+ 可选 KIBANA_PUBLIC_URL）
Grafana   →  ES_SERVER + SQL_SERVER/SQL_PASSWD（多副本）；PVC 挂 /var/lib/grafana（SFS）
Kafka     →  KAFKA_LOG_DIRS 挂 EVS PVC；多节点配 KAFKA_CLUSTER_ID + quorum voters
```

---

## 相关文档

- `STACK.md` — 版本矩阵
- `kibana-service` / `LogStash` / `grafana-service` / `es-service` / `kafka-service` 各仓库 `README.md`
