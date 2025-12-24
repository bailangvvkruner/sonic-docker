# FROM golang:1.19.3-alpine as builder
FROM golang:alpine as builder

# COPY . /go/src/github.com/go-sonic/sonic/
WORKDIR /go/src/github.com/go-sonic/sonic

RUN set -eux \
    && apk add --no-cache --no-scripts --virtual .build-deps \
    git \
    ca-certificates \
    gcc \
    g++ \
    # 包含strip命令
    binutils \
    upx \
    tzdata \
    \
    && git clone -b sqlite3 --recursive --depth 1 https://github.com/bailangvvkruner/sonic . \
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
        -o sonic \
        -ldflags="-s -w -extldflags -static" \
        -trimpath . \
    && echo "Binary size after build:" \
    && du -b sonic \
    && strip --strip-all sonic \
    && echo "Binary size after stripping:" \
    && du -b sonic \
    && upx --best --lzma sonic \
    && echo "Binary size after upx:" \
    && du -b sonic \
    && mkdir -p /app/conf \
    && mkdir /app/resources \
    && cp -r /go/src/github.com/go-sonic/sonic/sonic /app/ \
    && cp -r /go/src/github.com/go-sonic/sonic/conf /app/ \
    && cp -r /go/src/github.com/go-sonic/sonic/resources /app/ \
    && cp /go/src/github.com/go-sonic/sonic/scripts/docker_init.sh /app/


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
