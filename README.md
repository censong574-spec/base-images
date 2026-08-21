# Logging-stack base images (AgentLink style)

Shared **Ubuntu 22.04 LTS** bases plus language runtimes compiled from LTS source so later patches can be rebuilt without waiting on upstream binaries.

| Image | Tag | What is compiled |
| --- | --- | --- |
| `local/ai-ubuntu-build:22.04` | Ubuntu 22.04 | tagged from `m.daocloud.io/docker.io/library/ubuntu:22.04` |
| `local/ai-ubuntu-runtime:22.04` | same | same |
| `local/ai-jdk-build:21.0.12` | OpenJDK 21 LTS | Temurin **sources** `21.0.12+8` (binary JDK is bootstrap only) |
| `local/ai-jdk-runtime:21.0.12` | same | stripped product image, keeps `jcmd`/`jstack`/`jmap` |
| `local/ai-go-toolchain:1.26.5` | Go 1.26.5 | compiled from `go1.26.5.src.tar.gz` |
| `local/ai-node-build:24.18.0` | Node 24 LTS | compiled from `node-v24.18.0.tar.gz` (Kibana 8.19 pin) |
| `local/ai-node-runtime:24.18.0` | same | runtime tree |

Debug tools match AgentLink: `curl`, `ss`, `vim-tiny`, `procps`, `tcpdump`, `ping`, `dig`, `logrotate`, `tailf`, plus logging extras `jq` / `openssl` / `nc`.

## Host constraint

`122.9.161.38` runs **Docker 18.09**. These Dockerfiles avoid BuildKit-only features (`RUN --mount`, `COPY --chmod`, `buildx`). Multi-stage `FROM` / `--target` is enough.

## `/opt/ai/installers` cache (CI)

`download-deps.sh` reads and writes `/opt/ai/installers` so the CI box does not re-fetch LTS sources. Logging apt debs use a **separate** name (`ubuntu-22.04-logging-apt-debs.tar.gz`) so they never overwrite AgentLink's `ubuntu-22.04-runtime-apt-debs.tar.gz`.

Reuse from CI today: `go1.25.9.linux-amd64.tar.gz` (Go bootstrap). Do **not** reuse `node-linux-x64.tar.gz` (that is Node 22.16.0; Kibana 8.19 needs Node 24.18.0 source).

## Build

On a Linux Docker host (this PoC host is fine; 8 vCPU / 15 GiB is tight if ES is also running):

```bash
cd base-images
bash scripts/download-deps.sh          # optional; build-bases.sh fetches what it needs
bash scripts/package-runtime-apt-debs.sh
bash scripts/build-bases.sh jdk        # then: go | node | all
```

JDK compile is 20–40 minutes. Node is similar. Do not compile JDK while Elasticsearch is using ~3 GiB if the host starts swapping (no swap on EulerOS).

## Service images

Each sibling repo (`kafka-service`, `elasticsearch-service`, `LogStash`, `kibana-service`, `grafana-service`, `FileBeat`) `FROM`s these bases and compiles **that** component from the matching LTS source tag.
