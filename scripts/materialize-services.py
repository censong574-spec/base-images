# -*- coding: utf-8 -*-
"""Copy shared AgentLink-style helper files into each logging service repo."""
from __future__ import annotations

import shutil
from pathlib import Path

OPS = Path(r"D:\code\ops")
BASE = OPS / "base-images"
SKEL = BASE / "skel"

SERVICES = [
    "kafka-service",
    "es-service",
    "LogStash",
    "kibana-service",
    "grafana-service",
    "FileBeat",
]

GITIGNORE = """runtime-images/
.docker-build/
deps/*.tar.gz
deps/*.tgz
deps/*.manifest
"""

DOCKERIGNORE = """.git
runtime-images
.docker-build
*.md
"""

APT_INSTALL = """ca-certificates
logrotate
curl
iproute2
vim-tiny
procps
tcpdump
iputils-ping
bind9-dnsutils
jq
openssl
netcat-openbsd
tzdata
bash
"""


def copy_file(src: Path, dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dest)


def main() -> None:
    for name in SERVICES:
        dest = OPS / name
        dest.mkdir(parents=True, exist_ok=True)
        copy_file(BASE / "docker" / "install-minimal-debug-tools.sh", dest / "docker" / "install-minimal-debug-tools.sh")
        copy_file(BASE / "docker" / "install-runtime-apt-local.sh", dest / "docker" / "install-runtime-apt-local.sh")
        copy_file(BASE / "docker" / "runtime-apt-packages.txt", dest / "docker" / "runtime-apt-packages.txt")
        apt_install = dest / "docker" / "runtime-apt-install.txt"
        if not apt_install.exists():
            apt_install.write_text(APT_INSTALL, encoding="utf-8")
        copy_file(SKEL / "runtime" / "run.sh", dest / "runtime" / "run.sh")
        copy_file(SKEL / "runtime" / "stop.sh", dest / "runtime" / "stop.sh")
        copy_file(SKEL / "deploy" / "logrotate" / "logrotate.conf", dest / "deploy" / "logrotate" / "logrotate.conf")
        copy_file(SKEL / "deploy" / "logrotate" / "run-log-maintenance.sh", dest / "deploy" / "logrotate" / "run-log-maintenance.sh")
        copy_file(SKEL / "deploy" / "logrotate" / "cleanup-log-quota.sh", dest / "deploy" / "logrotate" / "cleanup-log-quota.sh")
        copy_file(SKEL / "deploy" / "lib" / "ops-helpers.sh", dest / "deploy" / "lib" / "ops-helpers.sh")
        copy_file(BASE / "scripts" / "package-runtime-apt-debs.sh", dest / "scripts" / "package-runtime-apt-debs.sh")
        (dest / "deps").mkdir(exist_ok=True)
        (dest / "deps" / ".gitkeep").write_text("", encoding="utf-8")
        (dest / ".gitignore").write_text(GITIGNORE, encoding="utf-8")
        (dest / ".dockerignore").write_text(DOCKERIGNORE, encoding="utf-8")
        (dest / ".gitattributes").write_text("* text=auto eol=lf\n*.sh text eol=lf\nDockerfile text eol=lf\n", encoding="utf-8")
        print("materialized", dest)


if __name__ == "__main__":
    main()
