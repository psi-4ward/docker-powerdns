#!/bin/sh
set -e

# --help, --version
[ "$1" = '--help' ] || [ "$1" = '--version' ] && exec pdns_server "$1"
# treat everything except -- as exec cmd
[ "${1:0:2}" != '--' ] && exec "$@"

# Set MySQL Credentials in pdns.conf
if [ "$MYSQL_AUTOCONF" = 'true' ]; then
  MYSQL_PASSWORD="$MYSQL_PASS" MYSQL_DBNAME="$MYSQL_DB"
  SEDPROG='/^[# ]*gmysql-/{';
  for _var in host port user password dbname; do
    _mysqlvar='${MYSQL_'"$(echo "$_var" | tr '[a-z]' '[A-Z]')"'}'
    _mysqlvarvalue="$(eval echo \""$_mysqlvar"\")"

    SEDPROG="${SEDPROG}$(printf 's/gmysql-%s=.*/gmysql-%s=%s/g;' "$_var" "$_var" "$_mysqlvarvalue")"
  done; unset -v _var _mysqlvar _mysqlvarvalue
  SEDPROG="${SEDPROG}"'};'
  unset -v MYSQL_PASSWORD MYSQL_DBNAME
  
  sed -r -i "$SEDPROG" /etc/pdns/pdns.conf
  unset -v SEDPROG
fi

MYSQLCMD="mysql --host='${MYSQL_HOST}' --user='${MYSQL_USER}' --password='${MYSQL_PASS}' -r -N"

# wait for Database come ready
isDBup () {
  echo 'SHOW STATUS' | eval "$MYSQLCMD" 1>/dev/null
}

RETRY=10
until isDBup || [ $(( RETRY-- )) -le 0 ] ; do
  echo "Waiting for database to come up"
  sleep 5
done
if [ $RETRY -le 0 ]; then
  1>&2 echo "Error: Could not connect to Database on ${MYSQL_HOST}:${MYSQL_PORT}"
  exit 1
fi

# init database if necessary
printf 'CREATE DATABASE IF NOT EXISTS "%s";\n' "$MYSQL_DB" | eval "$MYSQLCMD"
MYSQLCMD="${MYSQLCMD} ${MYSQL_DB}"

if [ "$(printf 'SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = "%s";\n' "$MYSQL_DB" | eval "$MYSQLCMD")" -le 1 ]; then
  echo 'Initializing Database'
  < /etc/pdns/schema.sql eval "$MYSQLCMD"
fi

trap "pdns_control quit" SIGHUP SIGINT SIGTERM

pdns_server "$@"
