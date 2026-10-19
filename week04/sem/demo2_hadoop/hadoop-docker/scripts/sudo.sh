#!/bin/sh
# Заглушка sudo: права HDFS выключены, а все демоны работают от hadoop,
# поэтому "sudo [-u user] cmd" (как в инструкциях для Data Proc) просто выполняет cmd.
while [ $# -gt 0 ]; do
  case "$1" in
    -u|-g) shift 2 ;;
    -*) shift ;;
    *) break ;;
  esac
done
exec "$@"
