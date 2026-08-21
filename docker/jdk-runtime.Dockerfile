ARG BUILD_BASE_IMAGE=local/ai-ubuntu-build:22.04
ARG RUNTIME_BASE_IMAGE=local/ai-ubuntu-runtime:22.04
ARG UBUNTU_APT_MIRROR=repo.huaweicloud.com

# Compile OpenJDK 21 LTS from Temurin sources. The Temurin *binary* is only a
# bootstrap JDK and is discarded; the runtime image contains the compiled tree.
FROM ${BUILD_BASE_IMAGE} AS jdk-build
ARG JDK_VERSION=21.0.12
ARG JDK_BUILD=8
ARG BOOT_JDK_ARCHIVE=deps/OpenJDK21U-jdk_x64_linux_hotspot_21.0.12_8.tar.gz
ARG JDK_SOURCE_ARCHIVE=deps/OpenJDK21U-jdk-sources_21.0.12_8.tar.gz
ARG UBUNTU_APT_MIRROR
ARG MAKE_JOBS=4
ENV DEBIAN_FRONTEND=noninteractive \
    PATH=/opt/boot-jdk/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

RUN rm -f /etc/apt/apt.conf.d/docker-clean \
    && printf '%s\n' \
      "deb http://${UBUNTU_APT_MIRROR}/ubuntu/ jammy main" \
      "deb http://${UBUNTU_APT_MIRROR}/ubuntu/ jammy-updates main" \
      "deb http://${UBUNTU_APT_MIRROR}/ubuntu/ jammy-security main" \
      "deb http://${UBUNTU_APT_MIRROR}/ubuntu/ jammy universe" \
      > /etc/apt/sources.list \
    && apt-get -o Acquire::ForceIPv4=true -o Acquire::Retries=5 update \
    && apt-get install -y --no-install-recommends \
        autoconf bash binutils build-essential ca-certificates curl file \
        libasound2-dev libcups2-dev libfontconfig1-dev libfreetype6-dev \
        libx11-dev libxext-dev libxrender-dev libxtst-dev libxt-dev \
        unzip zip zlib1g-dev

COPY ${BOOT_JDK_ARCHIVE} /tmp/boot-jdk.tar.gz
COPY ${JDK_SOURCE_ARCHIVE} /tmp/jdk-source.tar.gz
RUN mkdir -p /opt/boot-jdk /tmp/jdk-src \
    && tar -xzf /tmp/boot-jdk.tar.gz -C /opt/boot-jdk --strip-components=1 \
    && tar -xzf /tmp/jdk-source.tar.gz -C /tmp/jdk-src --strip-components=1 \
    && rm -f /tmp/boot-jdk.tar.gz /tmp/jdk-source.tar.gz \
    && cd /tmp/jdk-src \
    && bash configure \
         --with-boot-jdk=/opt/boot-jdk \
         --with-native-debug-symbols=none \
         --disable-warnings-as-errors \
         --enable-headless-only \
         --with-version-string="${JDK_VERSION}" \
         --with-version-build="${JDK_BUILD}" \
         --with-vendor-name="ai-logging" \
         --with-vendor-url="https://github.com/censong574-spec" \
         --with-zlib=system \
         --prefix=/opt/jdk \
    && make JOBS="${MAKE_JOBS}" product-images \
    && mkdir -p /opt/jdk \
    && cp -a build/*/images/jdk/. /opt/jdk/ \
    && rm -rf \
         /opt/jdk/demo \
         /opt/jdk/man \
         /opt/jdk/include \
         /opt/jdk/jmods \
         /opt/jdk/lib/src.zip \
         /tmp/jdk-src \
         /opt/boot-jdk \
    && /opt/jdk/bin/java -version

FROM jdk-build AS jdk-runtime-files
# Keep jcmd/jstack/jmap/jstat for in-container JVM ops; drop headers/src.

FROM ${RUNTIME_BASE_IMAGE} AS jdk-runtime
ARG UBUNTU_APT_MIRROR
ENV DEBIAN_FRONTEND=noninteractive \
    JAVA_HOME=/opt/jdk \
    PATH=/opt/jdk/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
RUN rm -f /etc/apt/apt.conf.d/docker-clean \
    && printf '%s\n' \
      "deb http://${UBUNTU_APT_MIRROR}/ubuntu/ jammy main" \
      "deb http://${UBUNTU_APT_MIRROR}/ubuntu/ jammy-updates main" \
      "deb http://${UBUNTU_APT_MIRROR}/ubuntu/ jammy-security main" \
      > /etc/apt/sources.list \
    && apt-get -o Acquire::ForceIPv4=true -o Acquire::Retries=5 update \
    && apt-get install -y --no-install-recommends \
        ca-certificates fontconfig libasound2 libfreetype6 libfontconfig1 \
        zlib1g \
    && rm -rf /var/lib/apt/lists/*
COPY --from=jdk-runtime-files /opt/jdk /opt/jdk
RUN /opt/jdk/bin/java -version
ENTRYPOINT []
CMD ["java", "-version"]
