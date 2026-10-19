# syntax=docker/dockerfile:1
# Локальный аналог Yandex Data Proc, образ 2.1 (2.1.4+):
# Hadoop 3.3.2, Spark 3.3.2, Tez 0.10.1, Livy 0.8.0, Python 3.8
ARG HADOOP_VERSION=3.3.2
ARG SPARK_VERSION=3.3.2
ARG TEZ_VERSION=0.10.1
ARG LIVY_VERSION=0.8.0
# Зеркала через пробел, с той же структурой каталогов, что у archive.apache.org.
# archive.apache.org сильно throttle-ится (~70 КБ/с), поэтому он только последний в списке.
ARG APACHE_MIRRORS="https://repo.huaweicloud.com/apache https://archive.apache.org/dist"

# ---------- стадии загрузки: BuildKit гонит их параллельно друг другу и apt/pip основного образа ----------
FROM ubuntu:20.04 AS dl
ARG APACHE_MIRRORS
ENV DEBIAN_FRONTEND=noninteractive APACHE_MIRRORS=${APACHE_MIRRORS}
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean \
 && apt-get update \
 && apt-get install -y --no-install-recommends curl ca-certificates unzip zip
COPY build/fetch.sh /usr/local/bin/fetch

FROM dl AS dl-hadoop
ARG HADOOP_VERSION
RUN --mount=type=cache,target=/dl \
    fetch "hadoop/common/hadoop-${HADOOP_VERSION}/hadoop-${HADOOP_VERSION}.tar.gz" /dl/hadoop.tgz \
 && tar -xzf /dl/hadoop.tgz -C /opt \
 && mv "/opt/hadoop-${HADOOP_VERSION}" /opt/hadoop \
 && rm -rf /opt/hadoop/share/doc

FROM dl AS dl-spark
ARG SPARK_VERSION
# Spark + архив jar-ов для spark.yarn.archive
RUN --mount=type=cache,target=/dl \
    fetch "spark/spark-${SPARK_VERSION}/spark-${SPARK_VERSION}-bin-hadoop3.tgz" /dl/spark.tgz \
 && tar -xzf /dl/spark.tgz -C /opt \
 && mv "/opt/spark-${SPARK_VERSION}-bin-hadoop3" /opt/spark \
 && cd /opt/spark/jars && zip -q -0 -r /opt/spark-jars.zip .

FROM dl AS dl-tez
ARG TEZ_VERSION
# share/tez.tar.gz внутри дистрибутива потом кладётся в HDFS
RUN --mount=type=cache,target=/dl \
    fetch "tez/${TEZ_VERSION}/apache-tez-${TEZ_VERSION}-bin.tar.gz" /dl/tez.tgz \
 && mkdir -p /opt/tez \
 && tar -xzf /dl/tez.tgz -C /opt/tez --strip-components=1

FROM dl AS dl-livy
ARG LIVY_VERSION
# Livy 0.8.0 (сборка под Scala 2.12, т.е. под Spark 3)
RUN --mount=type=cache,target=/dl \
    fetch "incubator/livy/${LIVY_VERSION}-incubating/apache-livy-${LIVY_VERSION}-incubating_2.12-bin.zip" /dl/livy.zip \
 && unzip -q /dl/livy.zip -d /opt \
 && mv /opt/apache-livy-*-bin /opt/livy

# ---------- итоговый образ ----------
FROM ubuntu:20.04

ARG SPARK_VERSION
ARG HADOOP_VERSION

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    TZ=UTC

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      openjdk-8-jdk-headless python3 python3-pip \
      curl ca-certificates unzip zip procps netcat-openbsd tini less bsdmainutils \
 && ln -s "$(dirname "$(dirname "$(readlink -f "$(command -v javac)")")")" /opt/java \
 && ln -sf /usr/bin/python3 /usr/bin/python

# Базовые библиотеки для PySpark (в Data Proc их ставит conda; при желании дополните список)
RUN --mount=type=cache,target=/root/.cache/pip \
    python3 -m pip install --upgrade "pip<24" \
 && python3 -m pip install numpy==1.24.4 pandas==1.5.3 pyarrow==12.0.1

ENV JAVA_HOME=/opt/java \
    HADOOP_HOME=/opt/hadoop \
    HADOOP_CONF_DIR=/etc/hadoop/conf \
    YARN_CONF_DIR=/etc/hadoop/conf \
    HADOOP_LOG_DIR=/var/log/hadoop \
    SPARK_HOME=/opt/spark \
    SPARK_CONF_DIR=/etc/spark/conf \
    SPARK_LOG_DIR=/var/log/spark \
    TEZ_HOME=/opt/tez \
    TEZ_CONF_DIR=/etc/tez/conf \
    LIVY_HOME=/opt/livy \
    LIVY_CONF_DIR=/etc/livy/conf \
    LIVY_LOG_DIR=/var/log/livy \
    PYSPARK_PYTHON=python3
ENV PATH=${PATH}:${HADOOP_HOME}/bin:${HADOOP_HOME}/sbin:${SPARK_HOME}/bin:${LIVY_HOME}/bin

# Hadoop (HDFS, YARN, MapReduce), Spark, Tez, Livy — скачиваются в стадиях dl-* выше
COPY --from=dl-hadoop /opt/hadoop ${HADOOP_HOME}
COPY --from=dl-spark  /opt/spark ${SPARK_HOME}
COPY --from=dl-spark  /opt/spark-jars.zip /opt/spark-jars.zip
COPY --from=dl-tez    /opt/tez ${TEZ_HOME}
COPY --from=dl-livy   /opt/livy ${LIVY_HOME}
# external shuffle service Spark для NodeManager
RUN cp "${SPARK_HOME}/yarn/spark-${SPARK_VERSION}-yarn-shuffle.jar" "${HADOOP_HOME}/share/hadoop/yarn/lib/"

# Пользователь, каталоги конфигов в стиле Data Proc (/etc/<component>/conf), данные
RUN useradd -m -u 1000 -s /bin/bash hadoop \
 && mkdir -p /etc/hadoop/conf /etc/spark/conf /etc/tez/conf /etc/livy/conf \
             /data/hdfs/namenode /hadoop/dfs/data \
             /var/log/hadoop /var/log/spark /var/log/livy /workspace \
 && cp -r "${HADOOP_HOME}/etc/hadoop/." /etc/hadoop/conf/ \
 && cp "${SPARK_HOME}/conf/log4j2.properties.template" /etc/spark/conf/log4j2.properties \
 && for f in "${LIVY_HOME}"/conf/*.template; do cp "$f" "/etc/livy/conf/$(basename "$f" .template)"; done \
 && echo 'export HADOOP_CLASSPATH="${TEZ_CONF_DIR}:${TEZ_HOME}/*:${TEZ_HOME}/lib/*"' >> /etc/bash.bashrc \
 && chown -R hadoop:hadoop /etc/hadoop /etc/spark /etc/tez /etc/livy /data /hadoop \
                           /var/log/hadoop /var/log/spark /var/log/livy /workspace

COPY conf/hadoop/ /etc/hadoop/conf/
COPY conf/spark/  /etc/spark/conf/
COPY conf/tez/    /etc/tez/conf/
COPY conf/livy/   /etc/livy/conf/
COPY scripts/     /opt/scripts/
# Второй SLF4J-биндинг из Tez (HADOOP_CLASSPATH в интерактивном bash) печатал предупреждение на каждую команду hdfs/yarn
RUN rm -f "${TEZ_HOME}"/lib/slf4j-log4j12-*.jar

# Пути как на Data Proc: streaming jar в /usr/lib/hadoop-mapreduce, sudo-заглушка (права HDFS выключены)
RUN chmod +x /opt/scripts/*.sh \
 && chown -R hadoop:hadoop /etc/hadoop /etc/spark /etc/tez /etc/livy \
 && mkdir -p /usr/lib/hadoop-mapreduce \
 && ln -s "${HADOOP_HOME}/share/hadoop/tools/lib/hadoop-streaming-${HADOOP_VERSION}.jar" /usr/lib/hadoop-mapreduce/hadoop-streaming.jar \
 && ln -s /opt/scripts/sudo.sh /usr/local/bin/sudo

USER hadoop
WORKDIR /workspace

EXPOSE 8020 9870 9864 8088 8042 19888 18080 8998

ENTRYPOINT ["/usr/bin/tini", "-g", "--", "/opt/scripts/entrypoint.sh"]
