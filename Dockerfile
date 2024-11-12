FROM alpine:latest

RUN apk upgrade && apk update

RUN apk add --no-cache bash openvpn openssl libstdc++ libgcc

RUN mkdir -p /etc/openvpn/config /root/.config/gpkih/logs /root/.config/gpkih/db

COPY gpkih_config /root/.config/gpkih/config
COPY gpkih_x86-64_alpine /usr/local/bin/gpkih

WORKDIR /

COPY entrypoint.sh entrypoint.sh

RUN chmod +x entrypoint.sh

ENV MAX_VPN_INSTANCES=2 CREATE_TEST_PKI=true

ENTRYPOINT ["./entrypoint.sh"]