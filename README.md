# nginx-docker

自研 **xiaonuo-nginx** 镜像：基于 nginx mainline，内置 Lua（LuaJIT + lua-resty 全家桶）、
OWASP Coraza WAF、HTTP/3（QuicTLS）及一批常用第三方模块。采用多阶段构建，运行镜像更小。

支持 `linux/amd64` 与 `linux/arm64` 多架构，标签为 `latest`。

## 多阶段构建

| 阶段 | 基础镜像 | 作用 |
| --- | --- | --- |
| builder | `iflyelf/ubuntu:latest` | 已预装 Go / Node / Python / build-essential 及大部分 -dev 库，仅补装 nginx 专用的少量 -dev 库后编译，构建更快更稳 |
| runtime | `iflyelf/ubuntu:lite` | 仅拷贝编译产物 + 安装 nginx 运行所需的共享库，镜像更小 |

运行阶段额外安装的运行库（按编译参数精确选取）：
`libpcre2-8-0`、`zlib1g`、`libgd3`（image_filter）、`libxml2`（Coraza WAF）、`libaio1t64`（file-aio）、`ca-certificates`。
未启用 geoip / xslt 模块，故不装 libgeoip / libxslt。

运行阶段环境变量：`PATH` 追加 `${NGINX_DIR}/sbin`，`LD_LIBRARY_PATH=/usr/local/lib`（加载 LuaJIT / libcoraza 共享库），入口使用 tini。

## 镜像获取

```bash
# Docker Hub（国外）
docker pull iflyelf/nginx:latest

# 华为云 SWR（国内推荐）
docker pull swr.cn-east-3.myhuaweicloud.com/iflyelf/nginx:latest
```

## 运行

```bash
docker run -d --name nginx -p 80:80 -p 443:443 -p 443:443/udp iflyelf/nginx:latest
```

或使用仓库内的 `docker-compose.yml`：

```bash
docker compose up -d
```

## 内置组件

- nginx mainline（`Server` 头伪装为 `xiaonuo`）
- HTTP/3 / QUIC：QuicTLS OpenSSL
- Lua：LuaJIT2 + lua-resty-core / lrucache / cookie / dns / memcached / mysql / redis / shell / upstream-healthcheck / websocket
- WAF：libcoraza + coraza-nginx + OWASP Core Rule Set
- 模块：ngx_devel_kit、lua-nginx-module、stream-lua-nginx-module、headers-more、nginx-http-concat、nginx-sticky-module-ng、lua-upstream、nginx-lua-prometheus
- 编译开启：stream、ssl、v2/v3、realip、sub、dav、flv、mp4、image_filter、secure_link、stub_status、auth_request、mail 等

各组件版本见 [Dockerfile](./Dockerfile) 顶部的 `ARG` 版本变量。

## 自动构建

以下情况会触发 [GitHub Actions](./.github/workflows/docker-publish.yml) 构建并推送到 Docker Hub 与华为云 SWR：

- 推送 `Dockerfile`、`conf/**` 或工作流文件变更
- 手动触发（workflow_dispatch）
- Star 仓库
- 定时构建：**中国时间每天早 5 点**（UTC 21:00）

同一分支仅保留最新一次构建（`concurrency` + `cancel-in-progress`），避免多架构构建并发堆积。

### 版本自动更新

[update-version.yml](./.github/workflows/update-version.yml) 每天中国时间早 4 点检查 nginx 及各依赖的最新**稳定版**
（自动排除 rc / beta / alpha / test / dev / preview 等不稳定版本，且只升不降），有更新则自动提交并触发镜像重建。

出于兼容性考虑，以下依赖不纳入自动更新（需人工评估）：LuaJIT、lua-resty-core、stream-lua-nginx-module
（OpenResty 捆绑组合需彼此配套）、QuicTLS OpenSSL、nginx-sticky-module-ng、nginx-lua-prometheus。

### 所需 Secrets

| Secret | 说明 |
| --- | --- |
| `DOCKER_USERNAME` / `DOCKER_PASSWORD` | Docker Hub 凭据 |
| `SWR_USERNAME` / `SWR_PASSWORD` | 华为云 SWR 登录凭据（`区域@AK` / 登录密钥） |
| `SWR_AK` / `SWR_SK` | 华为云账号 AK/SK，用于将 SWR 仓库设为公开（可选） |
