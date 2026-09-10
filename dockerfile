# ------------------------------------------------------------
# Stage 1: Build PJSIP + Python bindings + sip2mqtt
# ------------------------------------------------------------
FROM ubuntu:22.04 AS build

ENV DEBIAN_FRONTEND=noninteractive
ENV PJSIP_VERSION=2.13
ENV CFLAGS="-O2 -DNDEBUG -fPIC"

RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        curl \
        nano \
        mc \
        libgsm1-dev \
        libspeex-dev \
        libspeexdsp-dev \
        libsrtp2-dev \
        libssl-dev \
        portaudio19-dev \
        python3 \
        python3-dev \
        python3-pip \
        python3-venv \
        python3-setuptools && \
    rm -rf /var/lib/apt/lists/*

RUN pip3 install paho-mqtt

# Download config_site.h
RUN curl -L https://raw.githubusercontent.com/lendy007/pjsip-ng/master/config_site.h -o /tmp/config_site.h

# Build PJSIP
RUN mkdir /usr/src/pjsip && \
    cd /usr/src/pjsip && \
    curl -L -o pjproject.tar.gz https://www.pjsip.org/release/${PJSIP_VERSION}/pjproject-${PJSIP_VERSION}.tar.gz && \
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
    ldconfig && \
    cd pjsip-apps/src/python && \
    python3 setup.py build && python3 setup.py install

# Download sip2mqtt
RUN mkdir -p /opt/sip2mqtt && \
    curl -L https://raw.githubusercontent.com/lendy007/sip2mqtt/master/sip2mqtt.py -o /opt/sip2mqtt/sip2mqtt.py

# ------------------------------------------------------------
# Stage 2: Runtime image
# ------------------------------------------------------------
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

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

# Copy PJSIP runtime libs
COPY --from=build /usr/lib /usr/lib
COPY --from=build /usr/local /usr/local
COPY --from=build /usr/src/pjsip/pjsip-apps/src/python /usr/src/pjsip/pjsip-apps/src/python

# Copy sip2mqtt
COPY --from=build /opt/sip2mqtt /opt/sip2mqtt

WORKDIR /opt/sip2mqtt

# Environment variables (configurable in Portainer)
ENV MQTT_TOPIC=sip2mqtt/softphone
ENV MQTT_DOMAIN=192.168.5.2
ENV MQTT_PORT=1830
ENV MQTT_USERNAME=user
ENV MQTT_PASSWORD=password
ENV SIP_DOMAIN=sipgate.de
ENV SIP_USERNAME=sipuser
ENV SIP_PASSWORD=sippassword

# Use ENV variables in CMD
CMD python3 /opt/sip2mqtt/sip2mqtt.py \
    --mqtt_topic "$MQTT_TOPIC" \
    --mqtt_domain "$MQTT_DOMAIN" \
    --mqtt_port "$MQTT_PORT" \
    --mqtt_username "$MQTT_USERNAME" \
    --mqtt_password "$MQTT_PASSWORD" \
    --sip_domain "$SIP_DOMAIN" \
    --sip_username "$SIP_USERNAME" \
    --sip_password "$SIP_PASSWORD"
