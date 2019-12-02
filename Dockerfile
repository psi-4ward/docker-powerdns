FROM alpine:3.10
MAINTAINER Christoph Wiechert <wio@psitrax.de>

ENV REFRESHED_AT="2019-12-02" \
    POWERDNS_VERSION=4.2.1 \
    POWERDNS_TARBALL_SHA256="f65019986b8fcbb1c6fffebcded04b2b397b84395830f4c63e8d119bcfa1aa28" \
    MYSQL_AUTOCONF=true \
    MYSQL_HOST="mysql" \
    MYSQL_PORT="3306" \
    MYSQL_USER="root" \
    MYSQL_PASS="root" \
    MYSQL_DB="pdns"

RUN apk --update --no-cache add \
      libgcc \
      libpq \
      libstdc++ \
      mariadb-client \
      mariadb-connector-c \
      sqlite-libs && \
    apk --update --no-cache add --virtual .build-deps \
      boost-dev \
      curl \
      g++ \
      make \
      mariadb-connector-c-dev \
      mariadb-dev \
      postgresql-dev \
      sqlite-dev && \
    curl -sSL -o /tmp/pdns-$POWERDNS_VERSION.tar.bz2 https://downloads.powerdns.com/releases/pdns-$POWERDNS_VERSION.tar.bz2 && \
    echo "${POWERDNS_TARBALL_SHA256}  /tmp/pdns-${POWERDNS_VERSION}.tar.bz2" | sha256sum -c && \
    cd /tmp/ && \
    tar xjf pdns-${POWERDNS_VERSION}.tar.bz2 && \
    cd /tmp/pdns-${POWERDNS_VERSION} && \
    ./configure --prefix="" --exec-prefix=/usr --sysconfdir=/etc/pdns \
      --with-modules="bind gmysql gpgsql gsqlite3" --without-lua --disable-lua-records && \
    make && make install-strip && \
    cd / && \
    mkdir -p /etc/pdns/conf.d && \
    addgroup -S pdns && \
    adduser -S -D -H -h /var/empty -s /bin/false -G pdns -g pdns pdns && \
    cp -d /usr/lib/libboost_program_options.so* /tmp && \
    apk del --purge .build-deps && \
    mv /tmp/libboost_program_options.so* /usr/lib/ && \
    rm -rf /tmp/pdns-$POWERDNS_VERSION.tar.bz2 /tmp/pdns-$POWERDNS_VERSION /var/cache/apk/*

ADD schema.sql pdns.conf /etc/pdns/
ADD entrypoint.sh /

EXPOSE 53/tcp 53/udp

ENTRYPOINT ["/entrypoint.sh"]
