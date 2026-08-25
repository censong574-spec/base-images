# Logging stack version matrix (v1)

Canonical pins: **`base-images/versions.env`**. Overview: **`../README.md`**.

## Service images

| Repo | Image | Version | Build method |
| --- | --- | --- | --- |
| es-service | `elasticsearch-service` | **8.19.20** | source (`v8.19.20` tag) |
| LogStash | `logstash-service` | **8.19.20** | official linux-x64 binary |
| kibana-service | `kibana-service` | **8.19.20** | source (`v8.19.20` tag) |
| FileBeat | `filebeat-service` | **8.19.20** | official linux-x64 binary |
| kafka-service | `kafka-service` | **3.9.2** | official `kafka_2.13-3.9.2` binary |
| grafana-service | `grafana-service` | **12.4.8** | source (`v12.4.8` tag) |

## Shared bases

| Image | Tag |
| --- | --- |
| `local/ai-ubuntu-runtime` | 22.04 |
| `local/ai-jdk-runtime` | 21.0.12 |
| `local/ai-node-runtime` | 24.18.0 |
| `local/ai-go-toolchain` | 1.26.5 |

## Elastic Stack rule

All of **Elasticsearch**, **Logstash**, **Kibana**, and **Filebeat** must stay on the **same** `ELASTIC_VERSION` (currently `8.19.20`). Kafka and Grafana are independent but tested with this pin.

**Runtime env vars:** see `DEPLOY-ENV.md` in this repo (and `../DEPLOY-ENV.md` in the ops workspace).

## Not in scope for v1

- Elastic **8.15.x** (legacy lab only; do not deploy for v1)
- Elastic **7.17** (`kibana-service/deploy/cutover-official-7.17.sh` is a one-off migration helper, not the v1 target)
