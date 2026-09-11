# ------------------------------------------------------------
# Stage 1: Build PJSIP
# ------------------------------------------------------------
FROM ubuntu:22.04 AS build

ENV DEBIAN_FRONTEND=noninteractive
ENV PJSIP_VERSION=2.12
ENV CFLAGS="-O2 -DNDEBUG -fPIC"

ARG CACHEBUSTER=1

# Enable all Ubuntu repositories (Universe, Multiverse)
RUN sed -i 's/^# deb/deb/g' /etc/apt/sources.list && \
    apt-get update -qq && \
    apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        curl \
        pkg-config \
        swig \
        python3-dev \
        python3-distutils \
        libssl-dev \
        libgsm1 \
        libspeex-dev \
        libspeexdsp-dev \
        libsrtp2-dev \
        libasound2-dev \
        portaudio19-dev && \
    rm -rf /var/lib/apt/lists/*

# Download config_site.h
RUN curl -L https://raw.githubusercontent.com/lendy007/pjsip-ng/master/config_site.h -o /tmp/config_site.h

# Build PJSIP
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

# Build Python bindings (pjsua2)
RUN cd /usr/src/pjsip/pjsip-apps/src/swig/python && \
    make && \
    make install

# Copy Python site-packages for runtime stage
RUN mkdir -p /tmp/site-packages && \
    cp -r /root/.local/lib/python3/site-packages /tmp/site-packages

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

RUN sed -i 's/^# deb/deb/g' /etc/apt/sources.list && \
    apt-get update -qq && \
    apt-get install -y --no-install-recommends \
        python3 \
        python3-pip \
        libgsm1 \
        libspeex1 \
        libspeexdsp1 \
        libsrtp2-1 \
        libssl3 \
        portaudio19-dev \
        curl && \
    rm -rf /var/lib/apt/lists/*

RUN pip3 install paho-mqtt
RUN mkdir -p /root/.local/lib/python3/site-packages

# Copy PJSIP libs from build stage
COPY --from=build /usr/lib/libpj* /usr/lib/
COPY --from=build /usr/lib/libpjsua* /usr/lib/
COPY --from=build /usr/lib/libpjsip* /usr/lib/
COPY --from=build /usr/lib/libpjmedia* /usr/lib/
COPY --from=build /usr/lib/libpjlib* /usr/lib/
COPY --from=build /usr/bin/pjsua* /usr/bin/
COPY --from=build /tmp/site-packages/ /root/.local/lib/python3/site-packages/

# Download sip2mqtt.py
RUN mkdir -p /opt/sip2mqtt
RUN curl -L https://raw.githubusercontent.com/lendy007/pjsip-ng/master/sip2mqtt.py -o /opt/sip2mqtt/sip2mqtt.py

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
