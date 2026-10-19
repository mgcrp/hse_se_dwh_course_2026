#!/usr/bin/env bash
# Проверка всех компонентов. Запуск:
#   docker compose exec livy /opt/scripts/smoke-test.sh
set -euo pipefail

step() { echo; echo "================ $* ================"; }
json() { python3 -c "import sys,json; print(json.load(sys.stdin)$1)"; }

step "HDFS"
hdfs dfs -mkdir -p /tmp/smoke
printf 'hello dataproc\nhello tez\nhello spark\n' | hdfs dfs -put -f - /tmp/smoke/input.txt
hdfs dfs -ls /tmp/smoke

step "MapReduce on YARN"
yarn jar "${HADOOP_HOME}"/share/hadoop/mapreduce/hadoop-mapreduce-examples-*.jar pi 2 100

step "Tez"
hdfs dfs -rm -r -f -skipTrash /tmp/smoke/tez-out
HADOOP_CLASSPATH="${TEZ_CONF_DIR}:${TEZ_HOME}/*:${TEZ_HOME}/lib/*" \
  yarn jar "${TEZ_HOME}"/tez-examples-*.jar orderedwordcount /tmp/smoke/input.txt /tmp/smoke/tez-out
hdfs dfs -cat '/tmp/smoke/tez-out/part*'

step "Spark (Scala)"
spark-submit --class org.apache.spark.examples.SparkPi \
  "${SPARK_HOME}"/examples/jars/spark-examples_*.jar 10 2>&1 | grep -E "Pi is roughly|ERROR" || true

step "PySpark"
cat > /tmp/smoke.py <<'PY'
import sys
from pyspark.sql import SparkSession
spark = SparkSession.builder.appName("smoke-pyspark").getOrCreate()
print("PYTHON", sys.version.split()[0], "| SPARK", spark.version)
print("SUM", spark.range(0, 100000).selectExpr("sum(id)").first()[0])
spark.stop()
PY
spark-submit --deploy-mode client /tmp/smoke.py 2>&1 | grep -E "^(PYTHON|SUM)|ERROR" || true

step "Livy"
LIVY=http://localhost:8998
SID=$(curl -fsS -X POST -H 'Content-Type: application/json' -d '{"kind":"pyspark"}' "${LIVY}/sessions" | json '["id"]')
echo "сессия ${SID}, жду idle..."
for _ in $(seq 1 120); do
  STATE=$(curl -fsS "${LIVY}/sessions/${SID}" | json '["state"]')
  case "${STATE}" in
    idle) break ;;
    dead|error|killed) echo "сессия упала: ${STATE}"; curl -fsS "${LIVY}/sessions/${SID}/log"; exit 1 ;;
  esac
  sleep 3
done
STID=$(curl -fsS -X POST -H 'Content-Type: application/json' \
  -d '{"code":"spark.range(1000).selectExpr(\"sum(id) as s\").collect()"}' \
  "${LIVY}/sessions/${SID}/statements" | json '["id"]')
for _ in $(seq 1 60); do
  RES=$(curl -fsS "${LIVY}/sessions/${SID}/statements/${STID}")
  [[ "$(echo "${RES}" | json '["state"]')" == "available" ]] && break
  sleep 2
done
echo "${RES}" | json '["output"]'
curl -fsS -X DELETE "${LIVY}/sessions/${SID}" >/dev/null

step "ВСЁ ОК"
