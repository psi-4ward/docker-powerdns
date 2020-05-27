FROM alpine:3.9

ARG POWERDNS_VERSION=4.3.0
ARG VCS_REF
ARG BUILD_DATE

# Container labels (http://label-schema.org/)
# Container annotations (https://github.com/opencontainers/image-spec)
LABEL maintainer="Christoph Wiechert <wio@psitrax.de>" \
      product="PowerDNS" \
      version=$POWERDNS_VERSION \
      org.label-schema.vcs-ref=$VCS_REF \
      org.label-schema.vcs-url="https://github.com/psi-4ward/docker-powerdns" \
      org.label-schema.build-date=$BUILD_DATE \
      org.label-schema.name="PowerDNS" \
      org.label-schema.description="Open source DNS software." \
      org.label-schema.url="https://www.powerdns.com/" \
      org.label-schema.vendor="PowerDNS.COM BV" \
      org.label-schema.version=$POWERDNS_VERSION \
      org.label-schema.schema-version="1.0" \
      org.opencontainers.image.revision=$VCS_REF \
      org.opencontainers.image.source="https://github.com/psi-4ward/docker-powerdns" \
      org.opencontainers.image.created=$BUILD_DATE \
      org.opencontainers.image.title="PowerDNS" \
      org.opencontainers.image.description="Open source DNS software." \
      org.opencontainers.image.url="https://www.powerdns.com/" \
      org.opencontainers.image.vendor="PowerDNS.COM BV" \
      org.opencontainers.image.version=$POWERDNS_VERSION \
      org.opencontainers.image.authors="Christoph Wiechert <wio@psitrax.de>"

ENV REFRESHED_AT="2020-05-24" \
    MYSQL_DEFAULT_AUTOCONF=true \
    MYSQL_DEFAULT_HOST="mysql" \
    MYSQL_DEFAULT_PORT="3306" \
    MYSQL_DEFAULT_USER="root" \
    MYSQL_DEFAULT_PASS="root" \
    MYSQL_DEFAULT_DB="pdns"

RUN apk --update add bash libpq sqlite-libs libstdc++ libgcc mariadb-client mariadb-connector-c lua-dev curl-dev && \
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

ADD schema.sql pdns.conf /etc/pdns/
ADD entrypoint.sh /

EXPOSE 53/tcp 53/udp

ENTRYPOINT ["/entrypoint.sh"]
