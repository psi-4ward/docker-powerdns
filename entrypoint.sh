#!/bin/sh
set -e

# --help, --version
[ "$1" = "--help" ] || [ "$1" = "--version" ] && exec pdns_server $1
# treat everything except -- as exec cmd
[ "${1:0:2}" != "--" ] && exec "$@"

if grep -hr '^launch=' /etc/pdns/pdns.conf /etc/pdns/conf.d/ 2>/dev/null | grep -q -F gmysql >/dev/null 2>&1; then

  # Set MySQL Credentials in pdns.conf
  if $MYSQL_AUTOCONF ; then
    sed -r -i "s/^[# ]*gmysql-host=.*/gmysql-host=${MYSQL_HOST}/g" /etc/pdns/pdns.conf
    sed -r -i "s/^[# ]*gmysql-port=.*/gmysql-port=${MYSQL_PORT}/g" /etc/pdns/pdns.conf
    sed -r -i "s/^[# ]*gmysql-user=.*/gmysql-user=${MYSQL_USER}/g" /etc/pdns/pdns.conf
    sed -r -i "s/^[# ]*gmysql-password=.*/gmysql-password=${MYSQL_PASS}/g" /etc/pdns/pdns.conf
    sed -r -i "s/^[# ]*gmysql-dbname=.*/gmysql-dbname=${MYSQL_DB}/g" /etc/pdns/pdns.conf
  fi

  MYSQLCMD="mysql -h $MYSQL_HOST -u $MYSQL_USER -p$MYSQL_PASS -r -N"

  # wait for Database come ready
  isDBup () {
    echo "SHOW STATUS" | $MYSQLCMD 1>/dev/null
    echo $?
  }

  RETRY=10
  until [ `isDBup` -eq 0 ] || [ $RETRY -le 0 ] ; do
    echo "Waiting for database to come up"
    sleep 5
    RETRY=$(expr $RETRY - 1)
  done
  if [ $RETRY -le 0 ]; then
    >&2 echo Error: Could not connect to Database on $MYSQL_HOST:$MYSQL_PORT
    exit 1
  fi

  # init database if necessary
  echo "CREATE DATABASE IF NOT EXISTS $MYSQL_DB;" | $MYSQLCMD
  MYSQLCMD="$MYSQLCMD $MYSQL_DB"

  if [ "$(echo "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = \"$MYSQL_DB\";" | $MYSQLCMD)" -le 1 ]; then
    echo Initializing Database
    cat /etc/pdns/schema.sql | $MYSQLCMD
  fi
fi

trap "pdns_control quit" SIGHUP SIGINT SIGTERM

pdns_server "$@" &

wait

