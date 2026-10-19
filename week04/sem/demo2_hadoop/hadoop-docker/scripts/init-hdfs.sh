#!/usr/bin/env bash
# Готовит HDFS: служебные каталоги, библиотеки Tez и Spark. Идемпотентен.
set -euo pipefail

log() { echo "[hdfs-init $(date +%H:%M:%S)] $*"; }

log "жду выхода NameNode из safemode..."
until hdfs dfsadmin -safemode get 2>/dev/null | grep -q "OFF"; do sleep 3; done

log "жду хотя бы одну живую DataNode..."
until [[ "$(hdfs dfsadmin -report -live 2>/dev/null | grep -c '^Name:' || true)" -ge 1 ]]; do sleep 3; done

log "создаю каталоги"
hdfs dfs -mkdir -p /tmp /tmp/logs /tmp/hadoop-yarn/staging \
                   /user/hadoop /user/hive/warehouse \
                   /apps/tez /apps/spark /var/log/spark/apps
hdfs dfs -chmod 1777 /tmp /tmp/logs /tmp/hadoop-yarn/staging /var/log/spark/apps /user/hive/warehouse

TEZ_TARBALL="${TEZ_HOME}/share/tez.tar.gz"
if [[ ! -f "${TEZ_TARBALL}" ]]; then
  log "ОШИБКА: не найден ${TEZ_TARBALL}"
  exit 1
fi
if ! hdfs dfs -test -e /apps/tez/tez.tar.gz; then
  log "загружаю Tez в HDFS"
  hdfs dfs -put -f "${TEZ_TARBALL}" /apps/tez/tez.tar.gz
fi

if ! hdfs dfs -test -e /apps/spark/spark-jars.zip; then
  log "загружаю jar-ы Spark в HDFS"
  hdfs dfs -put -f /opt/spark-jars.zip /apps/spark/spark-jars.zip
fi

log "готово"
