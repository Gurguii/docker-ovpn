FROM alpine:latest

# Update system
RUN apk upgrade && apk update

# Install necessary packages
RUN apk add --no-cache bash openvpn

# Create config dir where server configs will be placed
RUN mkdir /etc/openvpn/config

WORKDIR /

COPY entrypoint.sh entrypoint.sh

RUN chmod +x entrypoint.sh

ENTRYPOINT ["./entrypoint.sh"]