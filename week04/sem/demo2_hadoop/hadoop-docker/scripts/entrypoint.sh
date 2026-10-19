#!/usr/bin/env bash
# Один образ — разные роли. Можно несколько сразу: entrypoint.sh datanode nodemanager
set -euo pipefail

ROLES="namenode datanode resourcemanager nodemanager historyserver spark-history livy init"

log() { echo "[entrypoint $(date +%H:%M:%S)] $*"; }

wait_for_port() {
  local host="$1" port="$2"
  log "жду ${host}:${port} ..."
  until nc -z "$host" "$port" 2>/dev/null; do sleep 2; done
  log "${host}:${port} доступен"
}

run_role() {
  case "$1" in
    namenode)
      if [[ ! -f /data/hdfs/namenode/current/VERSION ]]; then
        log "первый запуск: форматирую NameNode"
        hdfs namenode -format -clusterid dataproc-local -force -nonInteractive
      fi
      exec hdfs namenode
      ;;
    datanode)
      wait_for_port namenode 8020
      exec hdfs datanode
      ;;
    resourcemanager)
      exec yarn resourcemanager
      ;;
    nodemanager)
      wait_for_port resourcemanager 8031
      exec yarn nodemanager
      ;;
    historyserver)
      wait_for_port namenode 8020
      exec mapred historyserver
      ;;
    spark-history)
      wait_for_port namenode 8020
      exec "${SPARK_HOME}/bin/spark-class" org.apache.spark.deploy.history.HistoryServer
      ;;
    livy)
      wait_for_port resourcemanager 8032
      exec "${LIVY_HOME}/bin/livy-server"
      ;;
    init)
      exec /opt/scripts/init-hdfs.sh
      ;;
    *)
      log "неизвестная роль: $1 (доступны: ${ROLES})"
      exit 64
      ;;
  esac
}

if [[ $# -eq 0 ]]; then
  log "укажите роль(и): ${ROLES}"
  exit 64
fi

# Если первый аргумент не роль — просто выполняем команду (например, bash)
if [[ " ${ROLES} " != *" $1 "* ]]; then
  exec "$@"
fi

if [[ $# -eq 1 ]]; then
  run_role "$1"
fi

for role in "$@"; do
  run_role "$role" &
done

# Если любой из процессов завершился — гасим контейнер, чтобы сработал restart
wait -n || true
log "один из процессов завершился, останавливаю контейнер"
exit 1
