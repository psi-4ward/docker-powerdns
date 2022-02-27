FROM alpine:3.15 as base

ENV REFRESHED_AT="2022-02-24" \
    POWERDNS_VERSION="4.6.0" \
    BUILD_DEPS="g++ make mariadb-dev postgresql-dev sqlite-dev curl boost-dev mariadb-connector-c-dev" \
    RUN_DEPS="bash libpq sqlite-libs libstdc++ libgcc mariadb-client mariadb-connector-c postgresql-client sqlite lua-dev curl-dev boost-libs boost-program_options" \
    POWERDNS_MODULES="bind gmysql gpgsql gsqlite3"

FROM base AS build
RUN apk --update add $BUILD_DEPS $RUN_DEPS
RUN curl -sSL https://downloads.powerdns.com/releases/pdns-$POWERDNS_VERSION.tar.bz2 | tar xj -C /tmp/
WORKDIR /tmp/pdns-$POWERDNS_VERSION
RUN ./configure --prefix="" --exec-prefix=/usr --sysconfdir=/etc/pdns --with-modules="$POWERDNS_MODULES"
RUN make
RUN DESTDIR="/pdnsbuild" make install-strip
RUN mkdir -p /pdnsbuild/etc/pdns/conf.d /pdnsbuild/etc/pdns/sql
RUN cp modules/gmysqlbackend/*.sql modules/gpgsqlbackend/*.sql modules/gsqlite3backend/*.sql /pdnsbuild/etc/pdns/sql/

FROM base
COPY --from=build /pdnsbuild /
RUN apk add $RUN_DEPS && \
    addgroup -S pdns 2>/dev/null && \
    adduser -S -D -H -h /var/empty -s /bin/false -G pdns -g pdns pdns 2>/dev/null && \
    rm /var/cache/apk/*

LABEL \
  MAINTAINER="Oliver Schaal <oliver.schaal@lostsignal.info>" \
  CONTRIBUTORS="Christoph Wiechert <wio@psitrax.de>, Mathias Kaufmann <me@stei.gr>, Cloudesire <cloduesire-dev@eng.it>"

ENV AUTOCONF=mysql \
    AUTO_SCHEMA_MIGRATION="no" \
    MYSQL_HOST="mysql" \
    MYSQL_PORT="3306" \
    MYSQL_USER="root" \
    MYSQL_PASS="root" \
    MYSQL_DB="pdns" \
    MYSQL_DNSSEC="no" \
    MYSQL_VERSION="4.6.0" \
    PGSQL_HOST="postgres" \
    PGSQL_PORT="5432" \
    PGSQL_USER="postgres" \
    PGSQL_PASS="postgres" \
    PGSQL_DB="pdns" \
    PGSQL_VERSION="4.6.0" \
    SQLITE_DB="pdns.sqlite3" \
    SQLITE_VERSION="4.6.0" \
    SCHEMA_VERSION_TABLE="_schema_version"

EXPOSE 53/tcp 53/udp
COPY pdns.conf /etc/pdns/
COPY entrypoint.sh /bin/powerdns
ENTRYPOINT ["powerdns"]
