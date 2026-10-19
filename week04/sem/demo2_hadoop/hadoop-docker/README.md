# Локальный аналог Yandex Data Proc 2.1

Версии как в образе Data Proc 2.1.4+: Hadoop 3.3.2 (HDFS, YARN, MapReduce), Spark 3.3.2, Tez 0.10.1, Livy 0.8.0, Python 3.8, Java 8.
Конфиги лежат там же, где в Data Proc: `/etc/hadoop/conf`, `/etc/spark/conf`, `/etc/tez/conf`, `/etc/livy/conf`.

## Топология

| Контейнер | Что внутри | Аналог в Data Proc |
|---|---|---|
| namenode | HDFS NameNode | мастер |
| resourcemanager | YARN ResourceManager | мастер |
| historyserver | MapReduce JobHistory | мастер |
| spark-history | Spark History Server | мастер |
| livy | Livy Server | мастер |
| worker1, worker2, worker3 | DataNode + NodeManager (+ Spark shuffle service) | подкластер с хранением |
| hdfs-init | одноразово: каталоги в HDFS, Tez и jar-ы Spark в HDFS | — |

## Запуск

Docker должен иметь не меньше ~8 ГБ памяти (3 воркера, каждый объявляет YARN 4 ГБ, но реально занимает меньше; проверено на Docker с 7.6 ГБ, на 10–12 ГБ комфортнее).

```bash
docker compose build          # первая сборка качает ~1 ГБ (по умолчанию с repo.huaweicloud.com, запасное зеркало — archive.apache.org)
docker compose up -d
docker compose logs -f hdfs-init   # дождаться "готово"
docker compose exec livy /opt/scripts/smoke-test.sh
```

Зеркала задаются списком через пробел (пробуются по порядку, медленное — <150 КБ/с — пропускается):
`docker compose build --build-arg APACHE_MIRRORS="https://<зеркало>/apache https://archive.apache.org/dist"`
Недокачанные файлы кэшируются BuildKit-ом, повторная сборка продолжит с места обрыва.

## Интерфейсы

| Сервис | URL |
|---|---|
| HDFS NameNode | http://localhost:9870 |
| YARN ResourceManager | http://localhost:8088 |
| MapReduce JobHistory | http://localhost:19888 |
| Spark History | http://localhost:18080 |
| Livy REST | http://localhost:8998 |
| NodeManager worker1 / worker2 / worker3 | http://localhost:8042 / :8043 / :8044 |

Ссылки в UI ведут на внутренние имена (`worker1`, `historyserver`…). Чтобы они открывались из браузера,
добавьте в `/etc/hosts`: `127.0.0.1 namenode resourcemanager historyserver spark-history livy worker1 worker2 worker3`.

## Работа

Каталог `./workspace` смонтирован в `/workspace` (namenode, resourcemanager, воркеры, livy).

```bash
docker compose exec livy bash      # HADOOP_CLASSPATH для Tez уже выставлен в интерактивном bash

hdfs dfs -ls /
spark-submit --deploy-mode cluster /workspace/job.py
pyspark
yarn jar $HADOOP_HOME/share/hadoop/mapreduce/hadoop-mapreduce-examples-3.3.2.jar wordcount /in /out
# MapReduce на движке Tez
yarn jar $HADOOP_HOME/share/hadoop/mapreduce/hadoop-mapreduce-examples-3.3.2.jar wordcount \
  -Dmapreduce.framework.name=yarn-tez /in /out-tez
yarn logs -applicationId application_...
```

Livy снаружи (например, из Jupyter/sparkmagic или DataSphere-подобного клиента):

```bash
curl -X POST -H 'Content-Type: application/json' -d '{"kind":"pyspark"}' localhost:8998/sessions
curl -X POST -H 'Content-Type: application/json' -d '{"code":"spark.range(10).count()"}' localhost:8998/sessions/0/statements
curl localhost:8998/sessions/0/statements/0
```

## Настройка

- Дефолты как на Data Proc (нужны демо `week04/sem`): `dfs.replication=1`, `dfs.blocksize=256 МБ`, `mapreduce.job.maps=30`, `mapreduce.map.output.compress=true` (`conf/hadoop/`). Каталог блоков DataNode - `/hadoop/dfs/data`.
- Ресурсы воркера: `conf/hadoop/yarn-site.xml` (`yarn.nodemanager.resource.*`).
- Spark по умолчанию: `conf/spark/spark-defaults.conf` (dynamic allocation включён, как в Data Proc).
- Меньше воркеров: удалите лишние сервисы `workerN` из `docker-compose.yml`. Репликация по умолчанию уже 1, как на Data Proc.
- После правки конфигов: `docker compose up -d --build`.
- Полный сброс данных HDFS: `docker compose down -v`.

## Отличия от облачного Data Proc

- Нет Hive, Zeppelin, Oozie, HBase, Zookeeper и коннектора к Object Storage (s3a/MinIO можно добавить отдельно).
- Python системный (3.8.10), без conda и полного набора ML-библиотек — дополните `pip install` в Dockerfile.
- Для совместимости с инструкциями Data Proc: `/usr/lib/hadoop-mapreduce/hadoop-streaming.jar` и заглушка `sudo` (просто выполняет команду).
- Безопасность упрощена: все демоны от пользователя `hadoop`, права HDFS выключены, нет Kerberos.
- Свойства Data Proc вида `spark:spark.executor.memory` здесь задаются напрямую в файлах `conf/`.
