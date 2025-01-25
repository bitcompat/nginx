# syntax=docker/dockerfile:1.13

ARG BUILD_VERSION=1.27.1
# renovate: datasource=github-releases depName=maxmind/libmaxminddb
ARG LIBMAXMINDDB_VERSION=1.12.2

FROM bitnami/minideb:bullseye as libmaxminddb_build

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG LIBMAXMINDDB_VERSION

RUN mkdir -p /bitnami/blacksmith-sandbox
RUN install_packages ca-certificates curl git build-essential

WORKDIR /bitnami/blacksmith-sandbox

RUN curl -sSL -olibmaxminddb.tar.gz https://github.com/maxmind/libmaxminddb/releases/download/${LIBMAXMINDDB_VERSION}/libmaxminddb-${LIBMAXMINDDB_VERSION}.tar.gz && \
    tar xf libmaxminddb.tar.gz

RUN cd libmaxminddb-${LIBMAXMINDDB_VERSION} && \
    ./configure --prefix=/opt/bitnami/common && \
    make -j4 && \
    make install

RUN rm -rf /opt/bitnami/common/lib/libmaxminddb.a /opt/bitnami/common/lib/libmaxminddb.la /opt/bitnami/common/share
RUN mkdir -p /opt/bitnami/common/licenses && \
    cp libmaxminddb-${LIBMAXMINDDB_VERSION}/LICENSE /opt/bitnami/common/licenses/libmaxminddb-${LIBMAXMINDDB_VERSION}.txt

FROM docker.io/bitnami/minideb:bullseye as builder

COPY prebuildfs /
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN install_packages build-essential libpcre3 libpcre3-dev zlib1g zlib1g-dev libssl-dev libgd-dev libxml2 libxml2-dev uuid-dev git ca-certificates
RUN mkdir -p /opt/src

ARG BUILD_VERSION
ADD --link http://nginx.org/download/nginx-${BUILD_VERSION}.tar.gz /opt/src/nginx-${BUILD_VERSION}.tar.gz

RUN mkdir -p /bitnami/blacksmith-sandox
RUN git clone -b"v0.2.2" https://github.com/vozlt/nginx-module-vts.git /bitnami/blacksmith-sandox/nginx-module-vts-0.2.0
RUN git clone -b"3.4" https://github.com/leev/ngx_http_geoip2_module.git /bitnami/blacksmith-sandox/nginx-module-geoip2-3.4.0
RUN git clone https://github.com/yaoweibin/ngx_http_substitutions_filter_module.git /bitnami/blacksmith-sandox/nginx-module-substitutions-filter-0.20220124.0 && \
    cd /bitnami/blacksmith-sandox/nginx-module-substitutions-filter-0.20220124.0 && \
    git reset --hard e12e965ac1837ca709709f9a26f572a54d83430e
RUN git clone https://github.com/google/ngx_brotli.git /bitnami/blacksmith-sandox/nginx-module-brotli-0.20220429.0 && \
    cd /bitnami/blacksmith-sandox/nginx-module-brotli-0.20220429.0 && \
    git reset --hard 6e975bcb015f62e1f303054897783355e2a877dc

COPY --link --from=libmaxminddb_build /opt/bitnami/ /opt/bitnami/
RUN install_packages libgeoip-dev

COPY --link --from=ghcr.io/bitcompat/render-template:1.0.3 /opt/bitnami/ /opt/bitnami/
COPY --link --from=ghcr.io/bitcompat/gosu:1.17.0 /opt/bitnami/ /opt/bitnami/

RUN <<EOT bash
    set -ex
    cd /opt/src
    tar xf nginx-${BUILD_VERSION}.tar.gz

    export PKG_CONFIG_PATH=/opt/bitnami/common/lib/pkgconfig:\$PKG_CONFIG_PATH

    pushd nginx-${BUILD_VERSION}
    ./configure --prefix=/opt/bitnami/nginx --with-http_stub_status_module --with-stream --with-http_gzip_static_module --with-mail \
    --with-http_realip_module --with-http_stub_status_module --with-http_v2_module --with-http_ssl_module --with-mail_ssl_module \
    --with-http_gunzip_module --with-threads --with-http_auth_request_module --with-http_sub_module --with-http_geoip_module \
    --with-compat --with-stream_realip_module --with-stream_ssl_module --with-cc-opt=-Wno-stringop-overread --add-module=/bitnami/blacksmith-sandox/nginx-module-vts-0.2.0 \
    --add-dynamic-module=/bitnami/blacksmith-sandox/nginx-module-geoip2-3.4.0 --add-module=/bitnami/blacksmith-sandox/nginx-module-substitutions-filter-0.20220124.0 \
    --add-dynamic-module=/bitnami/blacksmith-sandox/nginx-module-brotli-0.20220429.0 \
    --with-cc-opt="-I /usr/local/include -I /opt/bitnami/common/include" \
    --with-ld-opt="-L /usr/local/lib -L /opt/bitnami/common/lib"

    make -j$(nproc)
    make install
EOT

RUN mkdir -p /opt/bitnami/nginx/licenses
RUN cp /opt/src/nginx-${BUILD_VERSION}/LICENSE /opt/bitnami/nginx/licenses/nginx-${BUILD_VERSION}.txt
RUN cp /bitnami/blacksmith-sandox/nginx-module-vts-0.2.0/LICENSE /opt/bitnami/nginx/licenses/nginx-module-vts-0.2.2.txt
RUN cp /bitnami/blacksmith-sandox/nginx-module-brotli-0.20220429.0/LICENSE /opt/bitnami/nginx/licenses/nginx-module-brotli-0.20220429.0.txt
RUN cp /bitnami/blacksmith-sandox/nginx-module-geoip2-3.4.0/LICENSE /opt/bitnami/nginx/licenses/nginx-module-geoip2-3.4.0.txt
RUN cp /bitnami/blacksmith-sandox/nginx-module-substitutions-filter-0.20220124.0/README /opt/bitnami/nginx/licenses/nginx-module-substitutions-filter-0.20220124.0.txt

RUN install_packages binutils
RUN find /opt/bitnami/ -name "*.so*" -type f | xargs strip --strip-all
RUN find /opt/bitnami/ -executable -type f | xargs strip --strip-all || true
RUN chown 1001:1001 -R /opt/bitnami/nginx
COPY --link rootfs /

FROM docker.io/bitnami/minideb:bullseye as stage-0

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
COPY --link --from=builder /opt/bitnami/ /opt/bitnami/

# Install required system packages and dependencies
RUN <<EOT bash
    set -e
    install_packages acl ca-certificates curl gzip libc6 libcrypt1 libgeoip1 libpcre3 libssl1.1 procps tar zlib1g libgeoip1
    apt-get update && apt-get upgrade -y && rm -r /var/lib/apt/lists /var/cache/apt/archives

    mkdir -p /bitnami/nginx/conf/vhosts
    chown 1001:1001 -R /bitnami/nginx

    chmod g+rwX /opt/bitnami
    ln -sf /dev/stdout /opt/bitnami/nginx/logs/access.log
    ln -sf /dev/stderr /opt/bitnami/nginx/logs/error.log
    /opt/bitnami/scripts/nginx/postunpack.sh
EOT

ARG BUILD_VERSION
ARG TARGETARCH

LABEL org.opencontainers.image.source="https://github.com/bitcompat/nginx" \
      org.opencontainers.image.title="nginx" \
      org.opencontainers.image.version="${BUILD_VERSION}"

ENV HOME="/" \
    OS_ARCH="$TARGETARCH" \
    OS_FLAVOUR="debian-11" \
    OS_NAME="linux" \
    APP_VERSION="${BUILD_VERSION}" \
    BITNAMI_APP_NAME="nginx" \
    NGINX_HTTPS_PORT_NUMBER="" \
    NGINX_HTTP_PORT_NUMBER="" \
    PATH="/opt/bitnami/common/bin:/opt/bitnami/nginx/sbin:$PATH"

EXPOSE 8080 8443

WORKDIR /app
USER 1001
ENTRYPOINT [ "/opt/bitnami/scripts/nginx/entrypoint.sh" ]
CMD [ "/opt/bitnami/scripts/nginx/run.sh" ]
