FROM alpine:3.9

COPY docker_test.sh /docker_test.sh

RUN set -ex; \
    chmod 755 /docker_test.sh;

CMD ["/docker_test.sh"]
