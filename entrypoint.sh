#!/bin/bash
set -e

[[ -z "$TRACE" ]] || set -x

# helper for docker setup env from file ----------------------------------------
# usage: file_env VAR [DEFAULT]
#    ie: file_env 'XYZ_DB_PASSWORD' 'example'
# (will allow for "$XYZ_DB_PASSWORD_FILE" to fill in the value of
#  "$XYZ_DB_PASSWORD" from a file, especially for Docker's secrets feature)
# source: https://github.com/docker-library/mariadb/blob/master/docker-entrypoint.sh
file_env() {
    local var="$1"
    local fileVar="${var}_FILE"
    local def="${2:-}"
    if [ "${!var:-}" ] && [ "${!fileVar:-}" ]; then
        echo "Both $var and $fileVar are set (but are exclusive)"
        exit 1
    fi
    local val="$def"
    if [ "${!var:-}" ]; then
        val="${!var}"
    elif [ "${!fileVar:-}" ]; then
        val="$(< "${!fileVar}")"
    fi
    export "$var"="$val"
    unset "$fileVar"
}

# Loads various settings that are used elsewhere in the script -----------------
docker_setup_env() {
    # Initialize values that might be stored in a file

    file_env 'AUTOCONF' $DEFAULT_AUTOCONF

    file_env 'MYSQL_HOST' $MYSQL_DEFAULT_HOST
    file_env 'MYSQL_DB' $MYSQL_DEFAULT_DB
    file_env 'MYSQL_PASS' $MYSQL_DEFAULT_PASS
    file_env 'MYSQL_USER' $MYSQL_DEFAULT_USER
    file_env 'MYSQL_PORT' $MYSQL_DEFAULT_PORT

    file_env 'PGSQL_HOST' $PGSQL_DEFAULT_HOST
    file_env 'PGSQL_DB' $PGSQL_DEFAULT_DB
    file_env 'PGSQL_PASS' $PGSQL_DEFAULT_PASS
    file_env 'PGSQL_USER' $PGSQL_DEFAULT_USER
    file_env 'PGSQL_PORT' $PGSQL_DEFAULT_PORT

    file_env 'SQLITE_DB' $SQLITE_DEFAULT_DB
    file_env 'SQLITE_PRAGMA_SYNCHRONOUS' $SQLITE_DEFAULT_PRAGMA_SYNCHRONOUS
    file_env 'SQLITE_PRAGMA_FOREIGN_KEYS' $SQLITE_DEFAULT_PRAGMA_FOREIGN_KEYS

    file_env 'DNSSEC' $DEFAULT_DNSSEC

}

# sqlite db --------------------------------------------------------------------
init_sqlite3() {
  if [[ ! -f "$PDNS_GSQLITE3_DATABASE" ]]; then
    echo "Initializing ${PDNS_GSQLITE3_DATABASE}"
    install -D -d -o pdns -g pdns -m 0755 $(dirname $PDNS_GSQLITE3_DATABASE)
    cat /etc/pdns/sql/schema.sqlite3.sql | sqlite3 ${PDNS_GSQLITE3_DATABASE}
    chown pdns:pdns $PDNS_GSQLITE3_DATABASE
    INITIAL_DB_VERSION=$SQLITE_VERSION
  fi
  if [ "$AUTO_SCHEMA_MIGRATION" == "yes" ]; then
    # init version database if necessary
    if [[ "$(echo "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='$SCHEMA_VERSION_TABLE';" | sqlite3 ${PDNS_GSQLITE3_DATABASE})" -eq 0 ]]; then
      [ -z "$INITIAL_DB_VERSION" ] && >&2 echo "Error: INITIAL_DB_VERSION is required when you use AUTO_SCHEMA_MIGRATION for the first time" && exit 1
      echo "CREATE TABLE $SCHEMA_VERSION_TABLE (id INTEGER PRIMARY KEY, version VARCHAR(255) NOT NULL)" | sqlite3 ${PDNS_GSQLITE3_DATABASE}
      echo "INSERT INTO $SCHEMA_VERSION_TABLE (version) VALUES ('$INITIAL_DB_VERSION');" | sqlite3 ${PDNS_GSQLITE3_DATABASE}
      echo "Initialized schema version to $INITIAL_DB_VERSION"
    fi
    # do the database upgrade
    while true; do
      current="$(echo "SELECT version FROM $SCHEMA_VERSION_TABLE ORDER BY id DESC LIMIT 1;" | sqlite3 ${PDNS_GSQLITE3_DATABASE})"
      if [ "$current" != "$SQLITE_VERSION" ]; then
        filename=/etc/pdns/sql/${current}_to_*_schema.sqlite3.sql
        echo "Applying Update $(basename $filename)"
        sqlite3 ${PDNS_GSQLITE3_DATABASE} < $filename
        current=$(basename $filename | sed -n 's/^[0-9.]\+_to_\([0-9.]\+\)_.*$/\1/p')
        echo "INSERT INTO $SCHEMA_VERSION_TABLE (version) VALUES ('$current');" | sqlite3 ${PDNS_GSQLITE3_DATABASE}
      else
        break
      fi
    done
  fi
}

# mysql db ---------------------------------------------------------------------
# MYSQLCMD="mysql -h $MYSQL_HOST -u $MYSQL_USER -p$MYSQL_PASS -r -N"
mysql_connect_db() {
  mysql -h ${PDNS_GMYSQL_HOST} -u ${PDNS_GMYSQL_USER} -p${PDNS_GMYSQL_PASSWORD}
  if [ $? -eq 0 ]; then
    echo "Connection attempt successful"
    MYSQL_CONNECTION_SUCCESS=1
  else
    echo "waiting 5 seconds before next attempt"
    sleep 5
  fi
}

mysql_query() {
  local MYSQL_QUERY=${1}
  mysql -r -N -h ${PDNS_GMYSQL_HOST} -u ${PDNS_GMYSQL_USER} -p${PDNS_GMYSQL_PASSWORD} \
    -e "${MYSQL_QUERY}" ${PDNS_GMYSQL_DBNAME}
}

mysql_import_schema() {
  pdns_tables=$(mysql_query "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = '${PDNS_GMYSQL_DBNAME}';")
  if [ ${pdns_tables} -lt 1 ]; then
    echo "Initializing Mysql database schema"
    mysql -r -N -h ${PDNS_GMYSQL_HOST} -u ${PDNS_GMYSQL_USER} -p${PDNS_GMYSQL_PASSWORD} \
      ${PDNS_GMYSQL_DBNAME} < /etc/pdns/schemas/schema.mysql.sql
  fi
}

init_mysql() {
  if [ -z "${PDNS_GMYSQL_HOST}" ] || [ -z "${PDNS_GMYSQL_USER}" ] || [ -z "${PDNS_GMYSQL_PASSWORD}" ] || [ -z "${PDNS_GMYSQL_DBNAME}" ]; then
    echo '!! Initializing of mysql backend cannot complete without all the required env variables set: '
    echo '   MYSQL_HOST, MYSQL_USER, MYSQL_PASSWORD, MYSQL_DB'
  else
    MYSQLCMD="mysql -h $PDNS_GMYSQL_HOST -u $PDNS_GMYSQL_USER -p$PDNS_GMYSQL_PASSWORD -r -N"
    echo "Attempt connection to mysql server: ${PDNS_GMYSQL_HOST} ..."
    ATTEMPTS_REMAINING=12
    MYSQL_CONNECTION_SUCCESS=0
    until [ ${MYSQL_CONNECTION_SUCCESS} -gt 0 ] || [ ${ATTEMPTS_REMAINING} -le 0 ]; do
      echo "Connection attempts remaining: ${ATTEMPTS_REMAINING}"
      mysql_connect_db
      ATTEMPTS_REMAINING=$(expr ${ATTEMPTS_REMAINING} - 1)
    done
    if [ ${ATTEMPTS_REMAINING} -le 0 ]; then
      echo "!! Exiting: Exhausted attempts to connect to mysql server. (${PDNS_GMYSQL_HOST}:${PDNS_GMYSQL_PORT})"
      exit 1
    fi
    echo "Creating database (if it does not already exist)"
    mysql_query "CREATE DATABASE IF NOT EXISTS ${PDNS_GMYSQL_DBNAME};"
    mysql_import_schema
    INITIAL_DB_VERSION=$MYSQL_VERSION
  fi

  MYSQLCMD="$MYSQLCMD $PDNS_GMYSQL_DBNAME"
  if [ "$AUTO_SCHEMA_MIGRATION" == "yes" ]; then
    # init version database if necessary
    if [ "$(echo "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = \"${PDNS_GMYSQL_DBNAME}\" and table_name = \"$SCHEMA_VERSION_TABLE\";" | $MYSQLCMD)" -eq 0 ]; then
      [ -z "$INITIAL_DB_VERSION" ] && >&2 echo "Error: INITIAL_DB_VERSION is required when you use AUTO_SCHEMA_MIGRATION for the first time" && exit 1
      echo "CREATE TABLE $SCHEMA_VERSION_TABLE (id INT AUTO_INCREMENT primary key NOT NULL, version VARCHAR(255) NOT NULL) Engine=InnoDB CHARACTER SET 'latin1';" | $MYSQLCMD
      echo "INSERT INTO $SCHEMA_VERSION_TABLE (version) VALUES ('$INITIAL_DB_VERSION');" | $MYSQLCMD
      echo "Initialized schema version to $INITIAL_DB_VERSION"
    fi
    # do the database upgrade
    while true; do
      current="$(echo "SELECT version FROM $SCHEMA_VERSION_TABLE ORDER BY id DESC LIMIT 1;" | $MYSQLCMD)"
      if [ "$current" != "$MYSQL_VERSION" ]; then
        filename=/etc/pdns/sql/${current}_to_*_schema.mysql.sql
        echo "Applying Update $(basename $filename)"
        $MYSQLCMD < $filename
        current=$(basename $filename | sed -n 's/^[0-9.]\+_to_\([0-9.]\+\)_.*$/\1/p')
        echo "INSERT INTO $SCHEMA_VERSION_TABLE (version) VALUES ('$current');" | $MYSQLCMD
      else
        break
      fi
    done
  fi
  # Run custom mysql post-init sql scripts
  if [ -d "/etc/pdns/mysql-postinit" ]; then
    for SQLFILE in $(ls -1 /etc/pdns/mysql-postinit/*.sql | sort) ; do
      echo Source $SQLFILE
      cat $SQLFILE | $MYSQLCMD
    done
  fi
}

# postgresql db ----------------------------------------------------------------
# PGSQLCMD="psql --host=$PGSQL_HOST --username=$PGSQL_USER"
pgsql_connect_db() {
  psql --host=$PDNS_GPGSQL_HOST --username=$PDNS_GPGSQL_USER
  if [ $? -eq 0 ]; then
    echo "Connection attempt successful"
    PGSQL_CONNECTION_SUCCESS=1
  else
    echo "waiting 5 seconds before next attempt"
    sleep 5
  fi
}

init_pgsql () {
  if [ -z "${PDNS_GPGSQL_HOST}" ] || [ -z "${PDNS_GPGSQL_USER}" ] || [ -z "${PDNS_GPGSQL_PASSWORD}" ] || [ -z "${PDNS_GPGSQL_DBNAME}" ]; then
    echo '!! Initializing of mysql backend cannot complete without all the required env variables set: '
    echo '   PGSQL_HOST, PGSQL_USER, PGSQL_PASSWORD, PGSQL_DB'
  else
    PGSQLCMD="psql --host=$PDNS_GPGSQL_HOST --username=$PDNS_GPGSQL_USER"
    echo "Attempt connection to pgsql server: ${PDNS_GPGSQL_HOST} ..."
    ATTEMPTS_REMAINING=12
    PGSQL_CONNECTION_SUCCESS=0
    until [ ${PGSQL_CONNECTION_SUCCESS} -gt 0 ] || [ ${ATTEMPTS_REMAINING} -le 0 ]; do
      echo "Connection attempts remaining: ${ATTEMPTS_REMAINING}"
      pgsql_connect_db
      ATTEMPTS_REMAINING=$(expr ${ATTEMPTS_REMAINING} - 1)
    done
    if [ ${ATTEMPTS_REMAINING} -le 0 ]; then
      echo "!! Exiting: Exhausted attempts to connect to pgsql server. (${PDNS_GPGSQL_HOST})"
      exit 1
    fi
    echo "Creating database (if it does not already exist)"
    if [[ -z "$(echo "SELECT 1 FROM pg_database WHERE datname = '$PGSQL_DB'" | $PGSQLCMD -t)" ]]; then
      echo "CREATE DATABASE $PGSQL_DB;" | $PGSQLCMD
    fi
    PGSQLCMD="$PGSQLCMD $PGSQL_DB"
    if [[ -z "$(printf '\dt' | $PGSQLCMD -qAt)" ]]; then
      echo Initializing Database
      cat /etc/pdns/sql/schema.pgsql.sql | $PGSQLCMD
      INITIAL_DB_VERSION=$PGSQL_VERSION
    fi
    if [ "$AUTO_SCHEMA_MIGRATION" == "yes" ]; then
      # init version database if necessary
      if [[ -z "$(echo "SELECT to_regclass('public.$SCHEMA_VERSION_TABLE');" | $PGSQLCMD -qAt)" ]]; then
        [ -z "$INITIAL_DB_VERSION" ] && >&2 echo "Error: INITIAL_DB_VERSION is required when you use AUTO_SCHEMA_MIGRATION for the first time" && exit 1
        echo "CREATE TABLE $SCHEMA_VERSION_TABLE (id SERIAL PRIMARY KEY, version VARCHAR(255) DEFAULT NULL)" | $PGSQLCMD
        echo "INSERT INTO $SCHEMA_VERSION_TABLE (version) VALUES ('$INITIAL_DB_VERSION');" | $PGSQLCMD
        echo "Initialized schema version to $INITIAL_DB_VERSION"
      fi
      # do the database upgrade
      while true; do
        current="$(echo "SELECT version FROM $SCHEMA_VERSION_TABLE ORDER BY id DESC LIMIT 1;" | $PGSQLCMD -qAt)"
        if [ "$current" != "$PGSQL_VERSION" ]; then
          filename=/etc/pdns/sql/${current}_to_*_schema.pgsql.sql
          echo "Applying Update $(basename $filename)"
          $PGSQLCMD < $filename
          current=$(basename $filename | sed -n 's/^[0-9.]\+_to_\([0-9.]\+\)_.*$/\1/p')
          echo "INSERT INTO $SCHEMA_VERSION_TABLE (version) VALUES ('$current');" | $PGSQLCMD
        else
          break
        fi
      done
    fi
  fi

}

# --help, --version
[ "$1" = "--help" ] || [ "$1" = "--version" ] && exec pdns_server $1
# treat everything except -- as exec cmd
[ "${1:0:2}" != "--" ] && exec "$@"

# Initialize values that might be stored in a file -----------------------------
docker_setup_env

# print pdns image info --------------------------------------------------------
echo "> PowerDNS started on: $(date)"

# Add backward compatibility ---------------------------------------------------
[[ "$MYSQL_AUTOCONF" == false ]] && AUTOCONF=false

# Set credentials to be imported into pdns.conf --------------------------------
case "$AUTOCONF" in
  mysql)
    export PDNS_LOAD_MODULES=$PDNS_LOAD_MODULES,libgmysqlbackend.so
    export PDNS_LAUNCH=gmysql
    export PDNS_GMYSQL_HOST=${PDNS_GMYSQL_HOST:-$MYSQL_HOST}
    export PDNS_GMYSQL_PORT=${PDNS_GMYSQL_PORT:-$MYSQL_PORT}
    export PDNS_GMYSQL_USER=${PDNS_GMYSQL_USER:-$MYSQL_USER}
    export PDNS_GMYSQL_PASSWORD=${PDNS_GMYSQL_PASSWORD:-$MYSQL_PASS}
    export PDNS_GMYSQL_DBNAME=${PDNS_GMYSQL_DBNAME:-$MYSQL_DB}
    export PDNS_GMYSQL_DNSSEC=${PDNS_GMYSQL_DNSSEC:-$DNSSEC}
  ;;
  postgres)
    export PDNS_LOAD_MODULES=$PDNS_LOAD_MODULES,libgpgsqlbackend.so
    export PDNS_LAUNCH=gpgsql
    export PDNS_GPGSQL_HOST=${PDNS_GPGSQL_HOST:-$PGSQL_HOST}
    export PDNS_GPGSQL_PORT=${PDNS_GPGSQL_PORT:-$PGSQL_PORT}
    export PDNS_GPGSQL_USER=${PDNS_GPGSQL_USER:-$PGSQL_USER}
    export PDNS_GPGSQL_PASSWORD=${PDNS_GPGSQL_PASSWORD:-$PGSQL_PASS}
    export PDNS_GPGSQL_DBNAME=${PDNS_GPGSQL_DBNAME:-$PGSQL_DB}
    export PDNS_GPGSQL_DNSSEC=${PDNS_GPGSQL_DNSSEC:-$DNSSEC}
    export PGPASSWORD=$PDNS_GPGSQL_PASSWORD
  ;;
  sqlite)
    export PDNS_LOAD_MODULES=$PDNS_LOAD_MODULES,libgsqlite3backend.so
    export PDNS_LAUNCH=gsqlite3
    export PDNS_GSQLITE3_DATABASE=${PDNS_GSQLITE3_DATABASE:-$SQLITE_DB}
    export PDNS_GSQLITE3_PRAGMA_SYNCHRONOUS=${PDNS_GSQLITE3_PRAGMA_SYNCHRONOUS:-$SQLITE_PRAGMA_SYNCHRONOUS}
    export PDNS_GSQLITE3_PRAGMA_FOREIGN_KEYS=${PDNS_GSQLITE3_PRAGMA_FOREIGN_KEYS:-$SQLITE_PRAGMA_FOREIGN_KEYS}
    export PDNS_GSQLITE3_DNSSEC=${PDNS_GSQLITE3_DNSSEC:-$DNSSEC}
  ;;
esac

# print pdns image info --------------------------------------------------------
echo "> PowerDNS environment variables:"
env | grep PDNS_ | grep -v PASS

# init database and migrate database if necessary ------------------------------
case "$PDNS_LAUNCH" in
  gmysql)
    echo "> MySQL. Preparing mysql backend ..."
    init_mysql
  ;;
  gpgsql)
    echo "> PGSQL. Preparing pgsql backend ..."
    init_pgsql
  ;;
  gsqlite3)
    echo "> SQLITE. Preparing sqlite backend ..."
    init_sqlite3
  ;;
esac

# convert all environment variables prefixed with PDNS_ into pdns config directives
PDNS_LOAD_MODULES="$(echo $PDNS_LOAD_MODULES | sed 's/^,//')"
printenv | grep ^PDNS_ | cut -f2- -d_ | while read var; do
  val="${var#*=}"
  var="${var%%=*}"
  var="$(echo $var | sed -e 's/_/-/g' | tr '[:upper:]' '[:lower:]')"
  [[ -z "$TRACE" ]] || echo "$var=$val"
  (grep -qE "^[# ]*$var=.*" /etc/pdns/pdns.conf && sed -r -i "s#^[# ]*$var=.*#$var=$val#g" /etc/pdns/pdns.conf) || echo "$var=$val" >> /etc/pdns/pdns.conf
done

# environment hygiene ----------------------------------------------------------
for var in $(printenv | cut -f1 -d= | grep -v -e HOME -e USER -e PATH ); do unset $var; done
export TZ=UTC LANG=C LC_ALL=C

# START PDNS -------------------------------------------------------------------
echo "> Starting pdns ..."
if [ $# -eq 0 ]; then
  echo "> Executing as uid [$(/usr/bin/id -u)]: pdns_server --daemon=no --write-pid=yes"
  pdns_server --daemon=no --write-pid=yes &
else
  echo "> Executing as uid [$(/usr/bin/id -u)]: pdns_server --daemon=no --write-pid=yes ${@}"
  pdns_server --daemon=no --write-pid=yes "$@" &
fi

# SIGNAL HANDLING --------------------------------------------------------------
PDNS_PID_FILE=/tmp/pdns.pid

shutdown_pdns() {
  echo "!! Recieved signal to gracefully shutdown pdns"
  local pid=$(cat ${PDNS_PID_FILE})
  pdns_control quit
  # wait
  wait_for_pid_to_exit ${pid}
  exit 0
}

reload_pdns() {
  echo "!! Recieved signal to reload pdns"
  pdns_control cycle
  wait $(cat ${PDNS_PID_FILE})
}

wait_for_pid_to_exit() {
  local pid=${1}
  echo "waiting for pid [${pid}] to exit ..."
  while [ -d /proc/${pid} ]; do
    echo "pid [${pid}] still exists. waiting ..."
    sleep 1
  done
}

trap "reload_pdns" SIGHUP
trap "shutdown_pdns" SIGINT SIGTERM

wait
