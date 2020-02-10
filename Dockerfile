FROM alpine:3.9

LABEL \
  MAINTAINER="Christoph Wiechert <wio@psitrax.de>" \
  CONTRIBUTORS="Mathias Kaufmann <me@stei.gr>, Cloudesire <cloduesire-dev@eng.it>"

ENV REFRESHED_AT="2019-10-10" \
    POWERDNS_VERSION=4.3.1 \
    AUTOCONF=mysql \
    MYSQL_HOST="mysql" \
    MYSQL_PORT="3306" \
    MYSQL_USER="root" \
    MYSQL_PASS="root" \
    MYSQL_DB="pdns" \
    MYSQL_DNSSEC="no" \
    PGSQL_HOST="postgres" \
    PGSQL_PORT="5432" \
    PGSQL_USER="postgres" \
    PGSQL_PASS="postgres" \
    PGSQL_DB="pdns" \
    SQLITE_DB="pdns.sqlite3"

RUN apk --update add bash libpq sqlite-libs libstdc++ libgcc mariadb-client postgresql-client sqlite mariadb-connector-c lua-dev curl-dev && \
    apk add --virtual build-deps \
      g++ make mariadb-dev postgresql-dev sqlite-dev curl boost-dev mariadb-connector-c-dev && \
    curl -sSL https://downloads.powerdns.com/releases/pdns-$POWERDNS_VERSION.tar.bz2 | tar xj -C /tmp && \
    cd /tmp/pdns-$POWERDNS_VERSION && \
    ./configure --prefix="" --exec-prefix=/usr --sysconfdir=/etc/pdns \
      --with-modules="bind gmysql gpgsql gsqlite3" && \
    make && make install-strip && cd / && \
    mkdir -p /etc/pdns/conf.d && \
    addgroup -S pdns 2>/dev/null && \
    adduser -S -D -H -h /var/empty -s /bin/false -G pdns -g pdns pdns 2>/dev/null && \
    cp /usr/lib/libboost_program_options-mt.so* /tmp && \
    apk del --purge build-deps && \
    mv /tmp/lib* /usr/lib/ && \
    rm -rf /tmp/pdns-$POWERDNS_VERSION /var/cache/apk/*

EXPOSE 53/tcp 53/udp

ADD sql/* pdns.conf /etc/pdns/

ADD entrypoint.sh /bin/powerdns

ENTRYPOINT ["powerdns"]
