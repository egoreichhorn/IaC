FROM alpine:3.20

RUN apk add --no-cache unbound

EXPOSE 53/udp 53/tcp

CMD ["unbound", "-d", "-c", "/opt/unbound/etc/unbound/unbound.conf"]