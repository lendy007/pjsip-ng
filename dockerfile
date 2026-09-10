# ------------------------------------------------------------
# Stage 1: Build PJSIP
# ------------------------------------------------------------
FROM ubuntu:22.04 AS build

ENV DEBIAN_FRONTEND=noninteractive
ENV PJSIP_VERSION=2.12
ENV CFLAGS="-O2 -DNDEBUG -fPIC"

RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        curl \
        libgsm1-dev \
        libspeex-dev \
        libspeexdsp-dev \
        libsrtp2-dev \
        libssl-dev \
        portaudio19-dev && \
    rm -rf /var/lib/apt/lists/*

# Download config_site.h
RUN curl -L https://raw.githubusercontent.com/lendy007/pjsip-ng/master/config_site.h -o /tmp/config_site.h

# Build PJSIP (using GitHub mirror)
RUN mkdir /usr/src/pjsip && \
    cd /usr/src/pjsip && \
    curl -L -o pjproject.tar.gz https://github.com/pjsip/pjproject/archive/refs/tags/${PJSIP_VERSION}.tar.gz && \
    tar -xzf pjproject.tar.gz --strip-components 1 && \
    mv /tmp/config_site.h pjlib/include/pj/ && \
    ./configure --enable-shared \
                --disable-opencore-amr \
                --disable-resample \
                --disable-sound \
                --disable-video \
                --with-external-gsm \
                --with-external-pa \
                --with-external-speex \
                --with-external-srtp \
                --prefix=/usr && \
    make -j$(nproc) all install && \
    ldconfig

# ------------------------------------------------------------
# Stage 2: Runtime + sip2mqtt
# ------------------------------------------------------------
FROM ubuntu:22.04

ENV MQTT_TOPIC=""
ENV MQTT_DOMAIN=""
ENV MQTT_PORT=""
ENV MQTT_USERNAME=""
ENV MQTT_PASSWORD=""
ENV SIP_DOMAIN=""
ENV SIP_USERNAME=""
ENV SIP_PASSWORD=""

RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
        python3 \
        python3-pip \
        libgsm1 \
        libspeex1 \
        libspeexdsp1 \
        libsrtp2-1 \
        libssl3 \
        portaudio19-dev && \
    rm -rf /var/lib/apt/lists/*

RUN pip3 install paho-mqtt

# Copy PJSIP libs from build stage
COPY --from=build /usr/lib/libpj* /usr/lib/
COPY --from=build /usr/lib/libpjsua* /usr/lib/
COPY --from=build /usr/lib/libpjsip* /usr/lib/
COPY --from=build /usr/lib/libpjmedia* /usr/lib/
COPY --from=build /usr/lib/libpjlib* /usr/lib/
COPY --from=build /usr/bin/pjsua* /usr/bin/

# Download sip2mqtt.py exactly like your original Dockerfile
RUN mkdir -p /opt/sip2mqtt
RUN curl -L https://raw.githubusercontent.com/lendy007/sip2mqtt/master/sip2mqtt.py -o /opt/sip2mqtt/sip2mqtt.py

WORKDIR /opt/sip2mqtt

CMD /bin/sh -c "python3 /opt/sip2mqtt/sip2mqtt.py \
    --mqtt_topic $MQTT_TOPIC \
    --mqtt_domain $MQTT_DOMAIN \
    --mqtt_port $MQTT_PORT \
    --mqtt_username $MQTT_USERNAME \
    --mqtt_password $MQTT_PASSWORD \
    --sip_domain $SIP_DOMAIN \
    --sip_username $SIP_USERNAME \
    --sip_password $SIP_PASSWORD"
