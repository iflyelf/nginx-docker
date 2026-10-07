#############################################################################
#  xiaonuo-nginx (Lua + Coraza WAF + HTTP/3) 多阶段构建
#  - builder(编译阶段) = iflyelf/ubuntu:latest
#      已预装 Go / Node / Python / build-essential 及大部分 -dev 库,
#      仅补装 nginx 专用的少量 -dev 库, 构建更快更稳。
#  - runtime(运行阶段) = iflyelf/ubuntu:lite
#      仅拷贝编译产物 + 安装 nginx 运行所需的共享库, 镜像更小。
#############################################################################

# ========================= 全局版本变量(两个阶段共享) =========================
# nginx  https://github.com/nginx/nginx
ARG NGINX_VERSION=1.31.6
# QuicTLS OpenSSL (带 QUIC 支持, HTTP/3 必需)  https://github.com/quictls/openssl
ARG OPENSSL_QUIC_VERSION=openssl-3.3.0-quic1
# luajit2  https://github.com/openresty/luajit2
ARG LUAJIT_VERSION=2.1-20250826
# ngx_devel_kit  https://github.com/simpl/ngx_devel_kit
ARG NGX_DEVEL_KIT_VERSION=0.3.4
# lua-nginx-module  https://github.com/openresty/lua-nginx-module
ARG LUA_NGINX_MODULE_VERSION=0.10.31
# nginx-sticky-module-ng  https://github.com/Refinitiv/nginx-sticky-module-ng
ARG NGINX_STICKY_MODULE_NG_VERSION=1.2.6
# nginx-http-concat  https://github.com/alibaba/nginx-http-concat
ARG NGINX_HTTP_CONCAT_VERSION=1.2.2
# libcoraza (OWASP Coraza WAF C 库)  https://github.com/corazawaf/libcoraza
ARG LIBCORAZA_VERSION=1.8.0
# coraza-nginx (libcoraza 的 nginx 连接器)  https://github.com/corazawaf/coraza-nginx
ARG CORAZA_NGINX_VERSION=0.22.0
# OWASP Core Rule Set  https://github.com/coreruleset/coreruleset
ARG OWASP_CRS_VERSION=4.30.0
# lua-resty-core  https://github.com/openresty/lua-resty-core
ARG LUA_RESTY_CORE_VERSION=0.1.34rc3
# lua-resty-lrucache  https://github.com/openresty/lua-resty-lrucache
ARG LUA_RESTY_LRUCACHE_VERSION=0.15
# headers-more-nginx-module  https://github.com/openresty/headers-more-nginx-module
ARG OPENRESTY_HEADERS_VERSION=0.40
# lua-resty-cookie  https://github.com/cloudflare/lua-resty-cookie
ARG CLOUDFLARE_COOKIE_VERSION=0.1.0
# lua-resty-dns  https://github.com/openresty/lua-resty-dns
ARG OPENRESTY_DNS_VERSION=0.23
# lua-resty-memcached  https://github.com/openresty/lua-resty-memcached
ARG OPENRESTY_MEMCACHED_VERSION=0.18
# lua-resty-mysql  https://github.com/openresty/lua-resty-mysql
ARG OPENRESTY_MYSQL_VERSION=0.31
# lua-resty-redis  https://github.com/openresty/lua-resty-redis
ARG OPENRESTY_REDIS_VERSION=0.33
# lua-resty-shell  https://github.com/openresty/lua-resty-shell
ARG OPENRESTY_SHELL_VERSION=0.03
# lua-resty-upstream-healthcheck  https://github.com/openresty/lua-resty-upstream-healthcheck
ARG OPENRESTY_HEALTHCHECK_VERSION=0.10
# lua-resty-websocket  https://github.com/openresty/lua-resty-websocket
ARG OPENRESTY_WEBSOCKET_VERSION=0.14
# lua-upstream-nginx-module  https://github.com/openresty/lua-upstream-nginx-module
ARG LUA_UPSTREAM_VERSION=0.08
# nginx-lua-prometheus  https://github.com/knyar/nginx-lua-prometheus
ARG PROMETHEUS_VERSION=0.20240525
# stream-lua-nginx-module  https://github.com/openresty/stream-lua-nginx-module
ARG OPENRESTY_STREAMLUA_VERSION=0.0.19rc4

# 公共路径/环境变量
ARG NGINX_DIR=/data/nginx
ARG DOWNLOAD_SRC=/tmp/src
ARG LUAJIT_LIB=/usr/local/lib
ARG LUAJIT_INC=/usr/local/include/luajit-2.1
ARG LUA_LIB_DIR=/usr/local/share/lua/5.1


####################################################################
#                     构建阶段 (builder)                            #
####################################################################
FROM iflyelf/ubuntu:latest AS builder

LABEL org.opencontainers.image.authors="iflyelf" \
      org.opencontainers.image.vendor="iflyelf"

# buildx 自动注入的目标架构
ARG TARGETARCH
ARG TARGETVARIANT

# 继承全局版本变量
ARG NGINX_VERSION
ARG OPENSSL_QUIC_VERSION
ARG LUAJIT_VERSION
ARG NGX_DEVEL_KIT_VERSION
ARG LUA_NGINX_MODULE_VERSION
ARG NGINX_STICKY_MODULE_NG_VERSION
ARG NGINX_HTTP_CONCAT_VERSION
ARG LIBCORAZA_VERSION
ARG CORAZA_NGINX_VERSION
ARG OWASP_CRS_VERSION
ARG LUA_RESTY_CORE_VERSION
ARG LUA_RESTY_LRUCACHE_VERSION
ARG OPENRESTY_HEADERS_VERSION
ARG CLOUDFLARE_COOKIE_VERSION
ARG OPENRESTY_DNS_VERSION
ARG OPENRESTY_MEMCACHED_VERSION
ARG OPENRESTY_MYSQL_VERSION
ARG OPENRESTY_REDIS_VERSION
ARG OPENRESTY_SHELL_VERSION
ARG OPENRESTY_HEALTHCHECK_VERSION
ARG OPENRESTY_WEBSOCKET_VERSION
ARG LUA_UPSTREAM_VERSION
ARG PROMETHEUS_VERSION
ARG OPENRESTY_STREAMLUA_VERSION
ARG NGINX_DIR
ARG DOWNLOAD_SRC
ARG LUAJIT_LIB
ARG LUAJIT_INC
ARG LUA_LIB_DIR

ENV NGINX_DIR=$NGINX_DIR \
    DOWNLOAD_SRC=$DOWNLOAD_SRC \
    LUAJIT_LIB=$LUAJIT_LIB \
    LUAJIT_INC=$LUAJIT_INC \
    LUA_LIB_DIR=$LUA_LIB_DIR \
    LD_LIBRARY_PATH=/usr/local/lib

# nginx 编译参数
ARG NGINX_BUILD_CONFIG="\
    --prefix=${NGINX_DIR} \
    --sbin-path=${NGINX_DIR}/sbin/nginx \
    --modules-path=${NGINX_DIR}/modules \
    --conf-path=${NGINX_DIR}/conf/nginx.conf \
    --error-log-path=${NGINX_DIR}/logs/error.log \
    --http-log-path=${NGINX_DIR}/logs/access.log \
    --pid-path=${NGINX_DIR}/logs/nginx.pid \
    --lock-path=${NGINX_DIR}/logs/nginx.lock \
    --http-client-body-temp-path=${NGINX_DIR}/temp/client_temp \
    --http-proxy-temp-path=${NGINX_DIR}/temp/proxy_temp \
    --http-fastcgi-temp-path=${NGINX_DIR}/temp/fastcgi_temp \
    --http-uwsgi-temp-path=${NGINX_DIR}/temp/uwsgi_temp \
    --http-scgi-temp-path=${NGINX_DIR}/temp/scgi_temp \
    --add-module=${DOWNLOAD_SRC}/ngx_devel_kit-${NGX_DEVEL_KIT_VERSION} \
    --add-module=${DOWNLOAD_SRC}/lua-nginx-module-${LUA_NGINX_MODULE_VERSION} \
    --add-module=${DOWNLOAD_SRC}/nginx-http-concat-${NGINX_HTTP_CONCAT_VERSION} \
    --add-module=${DOWNLOAD_SRC}/lua-upstream-nginx-module-${LUA_UPSTREAM_VERSION} \
    --add-module=${DOWNLOAD_SRC}/coraza-nginx-${CORAZA_NGINX_VERSION} \
    --user=nginx \
    --group=nginx \
    --with-stream \
    --with-stream_ssl_module \
    --with-stream_ssl_preread_module \
    --with-stream_realip_module \
    --with-http_ssl_module \
    --with-http_realip_module \
    --with-http_addition_module \
    --with-http_sub_module \
    --with-http_dav_module \
    --with-http_flv_module \
    --with-http_mp4_module \
    --with-http_gunzip_module \
    --with-http_gzip_static_module \
    --with-http_random_index_module \
    --with-http_secure_link_module \
    --with-http_stub_status_module \
    --with-http_auth_request_module \
    --with-threads \
    --with-http_slice_module \
    --with-mail \
    --with-mail_ssl_module \
    --with-file-aio \
    --with-http_v2_module \
    --with-http_v3_module \
    --with-http_image_filter_module \
    --with-ipv6 \
"
ENV NGINX_BUILD_CONFIG=$NGINX_BUILD_CONFIG

# ***** 仅补装 nginx 专用的 -dev 库 *****
# iflyelf/ubuntu:latest 已含 build-essential/go/libssl-dev/zlib1g-dev/libxml2-dev/libxslt1-dev,
# 这里只补装其缺少的 nginx 构建库, 避免重装庞大依赖列表。
ARG NGINX_EXTRA_BUILD_DEPS="\
    libpcre2-dev \
    libgd-dev \
    libgeoip-dev"
RUN set -eux && \
    DEBIAN_FRONTEND=noninteractive apt update -qqy && \
    DEBIAN_FRONTEND=noninteractive apt install -qqy $NGINX_EXTRA_BUILD_DEPS --option=Dpkg::Options::=--force-confdef && \
    for pkg in $NGINX_EXTRA_BUILD_DEPS; do \
        if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"; then \
            echo "ERROR: 依赖包未成功安装: $pkg" >&2 && exit 1; \
        fi; \
    done && \
    echo "nginx 构建依赖补装完成" && \
    rm -rf /var/lib/apt/lists/*

# ***** 创建相关目录 *****
RUN set -eux && \
    mkdir -pv ${DOWNLOAD_SRC} && \
    mkdir -p ${NGINX_DIR}/temp/client_temp && \
    mkdir -p ${NGINX_DIR}/temp/proxy_cache && \
    mkdir -p ${NGINX_DIR}/temp/proxy_temp && \
    mkdir -p ${NGINX_DIR}/temp/fastcgi_temp && \
    mkdir -p ${NGINX_DIR}/temp/uwsgi_temp && \
    mkdir -p ${NGINX_DIR}/temp/scgi_temp && \
    mkdir -p ${NGINX_DIR}/logs/hack

# ***** 下载源码包 *****
RUN set -eux && \
    wget --no-check-certificate http://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz \
    -O ${DOWNLOAD_SRC}/nginx.tar.gz && \
    wget --no-check-certificate https://github.com/quictls/openssl/archive/refs/tags/${OPENSSL_QUIC_VERSION}.tar.gz \
    -O ${DOWNLOAD_SRC}/openssl-quic.tar.gz && \
    wget --no-check-certificate https://github.com/openresty/luajit2/archive/v${LUAJIT_VERSION}.tar.gz \
    -O ${DOWNLOAD_SRC}/luajit2.tar.gz && \
    wget --no-check-certificate https://github.com/simpl/ngx_devel_kit/archive/v${NGX_DEVEL_KIT_VERSION}.tar.gz \
    -O ${DOWNLOAD_SRC}/ngx_devel_kit.tar.gz && \
    wget --no-check-certificate https://github.com/Refinitiv/nginx-sticky-module-ng/archive/${NGINX_STICKY_MODULE_NG_VERSION}.tar.gz \
    -O ${DOWNLOAD_SRC}/nginx-sticky-module-ng.tar.gz && \
    wget --no-check-certificate https://github.com/openresty/lua-nginx-module/archive/v${LUA_NGINX_MODULE_VERSION}.tar.gz \
    -O ${DOWNLOAD_SRC}/lua-nginx-module.tar.gz && \
    wget --no-check-certificate https://github.com/openresty/lua-resty-core/archive/v${LUA_RESTY_CORE_VERSION}.tar.gz \
    -O ${DOWNLOAD_SRC}/lua-resty-core.tar.gz && \
    wget --no-check-certificate https://github.com/openresty/lua-resty-lrucache/archive/v${LUA_RESTY_LRUCACHE_VERSION}.tar.gz \
    -O ${DOWNLOAD_SRC}/ngx_cache_purge.tar.gz && \
    wget --no-check-certificate https://github.com/alibaba/nginx-http-concat/archive/${NGINX_HTTP_CONCAT_VERSION}.tar.gz \
    -O ${DOWNLOAD_SRC}/nginx-http-concat.tar.gz && \
    wget --no-check-certificate https://github.com/corazawaf/libcoraza/archive/refs/tags/v${LIBCORAZA_VERSION}.tar.gz \
    -O ${DOWNLOAD_SRC}/libcoraza.tar.gz && \
    wget --no-check-certificate https://github.com/corazawaf/coraza-nginx/archive/refs/tags/v${CORAZA_NGINX_VERSION}.tar.gz \
    -O ${DOWNLOAD_SRC}/coraza-nginx.tar.gz && \
    wget --no-check-certificate https://github.com/coreruleset/coreruleset/archive/refs/tags/v${OWASP_CRS_VERSION}.tar.gz \
    -O ${DOWNLOAD_SRC}/coreruleset.tar.gz && \
    wget --no-check-certificate https://github.com/openresty/headers-more-nginx-module/archive/v${OPENRESTY_HEADERS_VERSION}.tar.gz \
    -O ${DOWNLOAD_SRC}/headers-more-nginx-module.tar.gz && \
    wget --no-check-certificate https://github.com/cloudflare/lua-resty-cookie/archive/v${CLOUDFLARE_COOKIE_VERSION}.tar.gz \
    -O ${DOWNLOAD_SRC}/lua-resty-cookie.tar.gz && \
    wget --no-check-certificate https://github.com/openresty/lua-resty-dns/archive/v${OPENRESTY_DNS_VERSION}.tar.gz \
    -O ${DOWNLOAD_SRC}/lua-resty-dns.tar.gz && \
    wget --no-check-certificate https://github.com/openresty/lua-resty-memcached/archive/v${OPENRESTY_MEMCACHED_VERSION}.tar.gz \
    -O ${DOWNLOAD_SRC}/lua-resty-memcached.tar.gz && \
    wget --no-check-certificate https://github.com/openresty/lua-resty-mysql/archive/v${OPENRESTY_MYSQL_VERSION}.tar.gz \
    -O ${DOWNLOAD_SRC}/lua-resty-mysql.tar.gz && \
    wget --no-check-certificate https://github.com/openresty/lua-resty-redis/archive/v${OPENRESTY_REDIS_VERSION}.tar.gz \
    -O ${DOWNLOAD_SRC}/lua-resty-redis.tar.gz && \
    wget --no-check-certificate https://github.com/openresty/lua-resty-shell/archive/v${OPENRESTY_SHELL_VERSION}.tar.gz \
    -O ${DOWNLOAD_SRC}/lua-resty-shell.tar.gz && \
    wget --no-check-certificate https://github.com/openresty/lua-resty-upstream-healthcheck/archive/v${OPENRESTY_HEALTHCHECK_VERSION}.tar.gz \
    -O ${DOWNLOAD_SRC}/lua-resty-upstream-healthcheck.tar.gz && \
    wget --no-check-certificate https://github.com/openresty/lua-resty-websocket/archive/v${OPENRESTY_WEBSOCKET_VERSION}.tar.gz \
    -O ${DOWNLOAD_SRC}/lua-resty-websocket.tar.gz && \
    wget --no-check-certificate https://github.com/openresty/lua-upstream-nginx-module/archive/v${LUA_UPSTREAM_VERSION}.tar.gz \
    -O ${DOWNLOAD_SRC}/lua-upstream-nginx-module.tar.gz && \
    wget --no-check-certificate https://github.com/knyar/nginx-lua-prometheus/archive/${PROMETHEUS_VERSION}.tar.gz \
    -O ${DOWNLOAD_SRC}/nginx-lua-prometheus.tar.gz && \
    wget --no-check-certificate https://github.com/openresty/stream-lua-nginx-module/archive/v${OPENRESTY_STREAMLUA_VERSION}.tar.gz \
    -O ${DOWNLOAD_SRC}/stream-lua-nginx-module.tar.gz && \
    cd ${DOWNLOAD_SRC} && for tar in *.tar.gz;  do tar xvf $tar -C ${DOWNLOAD_SRC}/; done

# ***** 安装中间件 (LuaJIT 及各 lua-resty 库) *****
RUN set -eux && \
    cd ${DOWNLOAD_SRC}/luajit2-${LUAJIT_VERSION} && \
    make -j$(($(nproc)+1)) && make -j$(($(nproc)+1)) install && \
    cd ${DOWNLOAD_SRC}/lua-resty-core-${LUA_RESTY_CORE_VERSION} && \
    make -j$(($(nproc)+1)) && make -j$(($(nproc)+1)) install && \
    mv ${DOWNLOAD_SRC}/nginx-lua-prometheus-${PROMETHEUS_VERSION}/*.lua ${LUA_LIB_DIR}/ && \
    cd ${DOWNLOAD_SRC}/lua-resty-lrucache-${LUA_RESTY_LRUCACHE_VERSION} && \
    make -j$(($(nproc)+1)) && make -j$(($(nproc)+1)) install && \
    cd ${DOWNLOAD_SRC}/lua-resty-cookie-${CLOUDFLARE_COOKIE_VERSION} && \
    make -j$(($(nproc)+1)) && make -j$(($(nproc)+1)) install && \
    cd ${DOWNLOAD_SRC}/lua-resty-dns-${OPENRESTY_DNS_VERSION} && \
    make -j$(($(nproc)+1)) && make -j$(($(nproc)+1)) install && \
    cd ${DOWNLOAD_SRC}/lua-resty-memcached-${OPENRESTY_MEMCACHED_VERSION} && \
    make -j$(($(nproc)+1)) && make -j$(($(nproc)+1)) install && \
    cd ${DOWNLOAD_SRC}/lua-resty-mysql-${OPENRESTY_MYSQL_VERSION} && \
    make -j$(($(nproc)+1)) && make -j$(($(nproc)+1)) install && \
    cd ${DOWNLOAD_SRC}/lua-resty-redis-${OPENRESTY_REDIS_VERSION} && \
    make -j$(($(nproc)+1)) && make -j$(($(nproc)+1)) install && \
    cd ${DOWNLOAD_SRC}/lua-resty-shell-${OPENRESTY_SHELL_VERSION} && \
    make -j$(($(nproc)+1)) && make -j$(($(nproc)+1)) install && \
    cd ${DOWNLOAD_SRC}/lua-resty-upstream-healthcheck-${OPENRESTY_HEALTHCHECK_VERSION} && \
    make -j$(($(nproc)+1)) && make -j$(($(nproc)+1)) install && \
    cd ${DOWNLOAD_SRC}/lua-resty-websocket-${OPENRESTY_WEBSOCKET_VERSION} && \
    make -j$(($(nproc)+1)) && make -j$(($(nproc)+1)) install

# ***** 编译安装 libcoraza (Coraza WAF C 库) *****
RUN set -eux && \
    cd ${DOWNLOAD_SRC}/libcoraza-${LIBCORAZA_VERSION} && \
    ./build.sh && \
    ./configure && \
    make -j$(($(nproc)+1)) && \
    # 跳过 make install (它会跑 go test -race, 在 arm64 QEMU 下因 ThreadSanitizer VMA 限制失败)
    # 手动安装库文件和头文件 (等效 install-data-local 但不依赖 check)
    install -d /usr/local/lib /usr/local/include/coraza && \
    install -m 644 libcoraza.a libcoraza.so /usr/local/lib/ && \
    install -m 644 coraza/coraza.h /usr/local/include/coraza/ && \
    ldconfig

# ***** 编译安装 NGINX *****
RUN set -eux && \
    # 修复 nginx-sticky-module-ng 1.2.6 的系统性老化(撞上 nginx 1.23+ 与 OpenSSL 3.x 两代 API 变更)
    sed -i \
        -e 's|ngx_http_parse_multi_header_lines(&r->headers_in\.cookies, \(&iphp->sticky_conf->cookie_name, &route)\) != NGX_DECLINED|ngx_http_parse_multi_header_lines(r, r->headers_in.cookie, \1 != NULL|' \
        ${DOWNLOAD_SRC}/nginx-sticky-module-ng-${NGINX_STICKY_MODULE_NG_VERSION}/ngx_http_sticky_module.c && \
    sed -i \
        -e 's|MD5_DIGEST_LENGTH|16|g' \
        -e 's|MD5_CBLOCK|64|g' \
        ${DOWNLOAD_SRC}/nginx-sticky-module-ng-${NGINX_STICKY_MODULE_NG_VERSION}/ngx_http_sticky_misc.c && \
    cd ${DOWNLOAD_SRC}/nginx-${NGINX_VERSION} && \
    sed -i '14s#nginx#xiaonuo_waf#' src/core/nginx.h && \
    sed -i '1,/NGINX_VAR/{s/.*NGINX_VAR.*/#define NGINX_VAR          "XIAONUO_WAF"/}' src/core/nginx.h && \
    sed -i 's#Server: nginx#Server: xiaonuo#g' src/http/ngx_http_header_filter_module.c && \
    sed -i 's#<hr><center>nginx</center>#<hr><center>xiaonuo</center>#g' src/http/ngx_http_special_response.c && \
    ./configure ${NGINX_BUILD_CONFIG} \
    --add-module=${DOWNLOAD_SRC}/headers-more-nginx-module-${OPENRESTY_HEADERS_VERSION} \
    --add-module=${DOWNLOAD_SRC}/nginx-sticky-module-ng-${NGINX_STICKY_MODULE_NG_VERSION} \
    --add-module=${DOWNLOAD_SRC}/stream-lua-nginx-module-${OPENRESTY_STREAMLUA_VERSION} \
    --with-openssl=${DOWNLOAD_SRC}/openssl-${OPENSSL_QUIC_VERSION} \
    --with-cc-opt='-g -O2 -fstack-protector-strong -Wformat -Werror=format-security -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=2 -fPIC' \
    --with-ld-opt='-Wl,-rpath,$LUAJIT_LIB -Wl,-z,relro -Wl,-z,now -Wl,--as-needed -pie' \
    || ./configure ${NGINX_BUILD_CONFIG} \
    --with-openssl=${DOWNLOAD_SRC}/openssl-${OPENSSL_QUIC_VERSION} \
    --with-cc-opt='-g -O2 -fstack-protector-strong -Wformat -Werror=format-security -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=2 -fPIC' \
    --with-ld-opt='-Wl,-rpath,$LUAJIT_LIB -Wl,-z,relro -Wl,-z,now -Wl,--as-needed -pie' && \
    make -j$(($(nproc)+1)) build && \
    make -j$(($(nproc)+1)) install && \
    # 部署 OWASP CRS 规则集到 waf 目录
    mkdir -p ${NGINX_DIR}/conf/waf/owasp-crs && \
    cp -r ${DOWNLOAD_SRC}/coreruleset-${OWASP_CRS_VERSION}/rules ${NGINX_DIR}/conf/waf/owasp-crs/ && \
    cp -r ${DOWNLOAD_SRC}/coreruleset-${OWASP_CRS_VERSION}/plugins ${NGINX_DIR}/conf/waf/owasp-crs/ && \
    cp ${DOWNLOAD_SRC}/coreruleset-${OWASP_CRS_VERSION}/crs-setup.conf.example ${NGINX_DIR}/conf/waf/crs-setup.conf


####################################################################
#                     运行阶段 (runtime)                            #
####################################################################
FROM iflyelf/ubuntu:lite

LABEL org.opencontainers.image.authors="iflyelf" \
      org.opencontainers.image.vendor="iflyelf" \
      org.opencontainers.image.description="xiaonuo-nginx (Lua + Coraza WAF + HTTP/3), runtime on ubuntu:lite"

# 时区/语言(继承 lite 默认, 显式声明便于覆盖)
ARG TZ=Asia/Shanghai
ENV TZ=$TZ
ARG LANG=zh_CN.UTF-8
ENV LANG=$LANG

# 镜像变量
ARG DOCKER_IMAGE=iflyelf/nginx
ENV DOCKER_IMAGE=$DOCKER_IMAGE

# 继承路径变量
ARG NGINX_DIR=/data/nginx
ENV NGINX_DIR=$NGINX_DIR
# nginx 运行时环境变量: sbin 进 PATH, LuaJIT/coraza 共享库进库路径
ENV PATH=${NGINX_DIR}/sbin:/usr/local/bin:$PATH \
    LD_LIBRARY_PATH=/usr/local/lib

# ***** 安装 nginx 运行所需的共享库(非 -dev 运行库) *****
# 依据编译参数精确选取运行库(避免多装):
#   libpcre2-8-0 -> 正则(核心, 必需)
#   zlib1g       -> gzip / gzip_static
#   libgd3       -> --with-http_image_filter_module
#   libxml2      -> libcoraza WAF (解析 xml 规则)
#   libaio1t64   -> --with-file-aio
#   ca-certificates -> TLS 根证书
# 说明: 未启用 http_geoip_module / http_xslt_module, 故不装 libgeoip / libxslt。
ARG NGINX_RUNTIME_DEPS="\
    libpcre2-8-0 \
    zlib1g \
    libgd3 \
    libxml2-16 \
    libaio1t64 \
    ca-certificates"
RUN set -eux && \
    DEBIAN_FRONTEND=noninteractive apt update -qqy && \
    DEBIAN_FRONTEND=noninteractive apt install -qqy --no-install-recommends $NGINX_RUNTIME_DEPS --option=Dpkg::Options::=--force-confdef && \
    for pkg in $NGINX_RUNTIME_DEPS; do \
        if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"; then \
            echo "ERROR: 运行依赖未成功安装: $pkg" >&2 && exit 1; \
        fi; \
    done && \
    echo "nginx 运行依赖验证通过" && \
    DEBIAN_FRONTEND=noninteractive apt -qqy autoremove --purge && \
    DEBIAN_FRONTEND=noninteractive apt -qqy autoclean && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/* /tmp/*

# ***** 拷贝编译产物 *****
# LuaJIT / libcoraza 共享库 + lua 库 + nginx 安装目录
COPY --from=builder /usr/local/lib /usr/local/lib
COPY --from=builder /usr/local/share/lua /usr/local/share/lua
COPY --from=builder /data /data

# ***** 拷贝配置文件 *****
COPY conf/nginx/nginx.conf /data/nginx/conf/nginx.conf
COPY conf/nginx/gzip.conf /data/nginx/conf/gzip.conf
COPY conf/nginx/cache.conf /data/nginx/conf/cache.conf
COPY conf/nginx/proxy.conf /data/nginx/conf/proxy.conf
COPY conf/nginx/php.conf /data/nginx/conf/php.conf
COPY conf/nginx/websocket.conf /data/nginx/conf/websocket.conf
COPY conf/nginx/waf.conf /data/nginx/conf/waf.conf
COPY conf/nginx/waf /data/nginx/conf/waf
COPY conf/nginx/ssl /ssl
COPY conf/nginx/vhost /data/nginx/conf/vhost
COPY www /www

# ***** 初始化: 用户/日志/动态库/自检 *****
RUN set -eux && \
    # 注册 libcoraza.so / libluajit 到动态链接库缓存
    ldconfig && \
    # 将请求和错误日志转发到 docker 日志收集器
    ln -sf /dev/stdout /data/nginx/logs/access.log && \
    ln -sf /dev/stderr /data/nginx/logs/error.log && \
    # 创建 nginx 用户和用户组
    addgroup --system --quiet nginx && \
    adduser --quiet --system --disabled-login --ingroup nginx --home /data/nginx --no-create-home nginx && \
    # 软链 nginx 到系统 PATH
    ln -sf ${NGINX_DIR}/sbin/* /usr/sbin/ && \
    # smoke test: 打印编译参数并校验配置
    nginx -V && \
    nginx -t

# 自动检测服务是否可用
HEALTHCHECK --interval=30s --timeout=3s CMD curl --fail http://localhost/ || exit 1

# ***** 监听端口 *****
EXPOSE 80 443 443/udp

# ***** 工作目录 *****
WORKDIR /data/nginx

# ***** 容器信号处理 *****
STOPSIGNAL SIGQUIT

# ***** 启动命令(tini 作为 init, 优雅处理信号) *****
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["nginx", "-g", "daemon off;"]
