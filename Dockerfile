# FROM golang:1.19.3-alpine as builder
FROM golang:alpine as builder

# COPY . /go/src/github.com/go-sonic/sonic/
WORKDIR /go/src/github.com/go-sonic/sonic

RUN set -eux \
    && FILENAME=sonic \
    && apk add --no-cache --no-scripts --virtual .build-deps \
    git \
    ca-certificates \
    build-base \
    # gcc \
    # g++ \
    # 包含strip命令
    binutils \
    # upx \
    tzdata \
    \
    # 尝试安装 upx，如果不可用则继续（某些架构可能不支持）
    && apk add --no-cache --no-scripts --virtual .upx-deps \
        upx 2>/dev/null || echo "upx not available, skipping compression" \
    \
    && git clone -b master --recursive --depth 1 https://github.com/bailangvvkruner/sonic . \
    # # 列出可更新的模块（仅信息显示）
    # && go list -m -u all \
    # 直接更新并获取所有依赖到最新版本
    && go get -u ./... \
    # && go get github.com/golang-jwt/jwt/v5@latest \
    # && go get github.com/disintegration/imaging@latest \
    # Cgo编译优化
    && export CGO_CFLAGS="-flto=auto -pipe" \
    && export CGO_CXXFLAGS="-flto=auto -pipe" \
    && export MAKEFLAGS="-j$(nproc)" \
    && CGO_ENABLED=1 GOOS=linux \
        go build \
        -o $FILENAME \
        -ldflags="-s -w -extldflags -static" \
        -trimpath . \
    && echo "Binary size after build:" \
    && du -b $FILENAME \
    && strip --strip-all $FILENAME \
    && echo "Binary size after stripping:" \
    && du -b $FILENAME \
    # && upx --best --lzma $FILENAME \
    && (upx --best --lzma $FILENAME 2>/dev/null || echo "upx compression skipped") \
    && echo "Binary size after upx:" \
    && du -b $FILENAME \
    && mkdir -p /app/conf \
    && mkdir /app/resources \
    && cp -r /go/src/github.com/go-sonic/sonic/sonic /app/ \
    && cp -r /go/src/github.com/go-sonic/sonic/conf /app/ \
    && cp -r /go/src/github.com/go-sonic/sonic/resources /app/ \
    && cp /go/src/github.com/go-sonic/sonic/scripts/docker_init.sh /app/ \
    # 清理Go缓存和临时文件以释放空间
    && go clean -modcache \
    && go clean -cache \
    && rm -rf /tmp/go-build* \
    && rm -rf /root/.cache/go-build

FROM alpine:latest as prod
# FROM busybox:musl as prod

COPY --from=builder /app/ /app/

RUN set -eux \
    && apk add --no-cache --no-scripts --virtual .build-deps \
    ca-certificates

# RUN set -eux \
#     && apk add --no-cache --no-scripts --virtual .build-deps \
#     tzdata \
#     && cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime \
#     && echo "Asia/Shanghai" > /etc/timezone

# Copy timezone files from builder stage
COPY --from=builder /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
COPY --from=builder /usr/share/zoneinfo/Asia/Shanghai /usr/share/zoneinfo/Asia/Shanghai

RUN set -eux \
    && echo "Asia/Shanghai" > /etc/timezone

VOLUME /sonic
EXPOSE 8080

WORKDIR /sonic
CMD /app/docker_init.sh && /app/sonic -config /sonic/conf/config.yaml
