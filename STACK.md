# Logging stack images (source-compiled, AgentLink layout)

This directory is a **workspace of sibling git repos**, not one git root.

```
base-images/              shared Ubuntu 22.04 + JDK 21 / Go 1.26 / Node 24 (compiled from LTS source)
kafka-service/            Kafka 3.9.2 from kafka-*-src.tgz
es-service/               Elasticsearch 8.19.20 from GitHub tag
LogStash/                 Logstash 8.19.20
kibana-service/           Kibana 8.19.20 (Node 24.18.0 pin)
grafana-service/          Grafana 12.4.8 (last Grafana 12 minor / extended support)
FileBeat/                 Filebeat 8.19.20 from elastic/beats
```

Layout of each service matches AgentLink:

- `Dockerfile` — multi-stage, compile in `*-build`, copy into `*-runtime`
- `build-image.sh` — ensure bases, fetch source, `docker build` (Docker 18.09 compatible)
- `docker/` — AgentLink debug tools + local apt repo installer
- `runtime/{run,start,stop}.sh` — PID1 stays up so you can `docker exec` hotfix
- `deploy/logrotate/` — same cut/compress/quota pattern

Runtime extras on top of AgentLink (`curl` `ss` `vim-tiny` `procps` `tcpdump` `ping` `dig` `logrotate` `tailf`):

- all: `jq` `openssl` `nc`
- JVM: `jcmd` `jstack` `jmap` (kept in the compiled JDK)
- Kafka: `kafka-topics.sh` / `kafka-console-consumer.sh` / `kafka-consumer-groups.sh` / `kafka-dump-log.sh`
- ES: `elasticsearch-plugin` `elasticsearch-keystore`
- Logstash: `logstash-plugin`
- Filebeat: `filebeat test config`

## Versions (LTS / long-support)

| Piece | Why this version |
| --- | --- |
| Ubuntu 22.04 | same as AgentLink |
| OpenJDK 21.0.12 | JDK 21 LTS, Temurin sources 21.0.12+8 |
| Go 1.26.5 | required by Grafana 12.4.8 and Filebeat 8.19.20 |
| Node 24.18.0 | Kibana 8.19 pin; Node 24 is Active LTS |
| Kafka 3.9.2 | last 3.x, matches the running 3.9.0 PoC |
| Elastic 8.19.20 | last 8.x line (host currently 8.15.3) |
| Grafana 12.4.8 | last Grafana 12 minor (15-month patch window) |

## CI cache (`/opt/ai/installers` on `ecs-liusong-ci`)

`base-images/scripts/download-deps.sh` reuses and writes `/opt/ai/installers`. Logging apt debs are `ubuntu-22.04-logging-apt-debs.tar.gz` so they do not clobber AgentLink's pack.

## Build order on 122.9.161.38

Docker Engine is **18.09** — no BuildKit bind-mounts. These files already avoid that.

The host only has 15 GiB RAM and the PoC stack is running. Compile **JDK first**, then Go/Node, then Kafka/Filebeat. Kibana/ES source builds may OOM unless Kibana/ES containers are stopped.

```bash
cd /opt/ops-build/base-images
bash scripts/build-bases.sh jdk
bash scripts/build-bases.sh go
bash scripts/build-bases.sh node
cd ../kafka-service && bash build-image.sh
```
