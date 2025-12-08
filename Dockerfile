# sonic Static Compilation Docker Build with BusyBox
# 使用 busybox:musl 作为基础镜像，提供基本shell环境

# 构建阶段 - 使用完整的构建环境
# FROM golang:1.21-alpine AS builder
FROM golang:1.21-alpine AS builder
# FROM golang:alpine AS builder

# # 构建参数：指定生成的二进制文件名
# ARG FILENAME=sonic

WORKDIR /app

# 安装构建依赖（包括C++编译器和strip工具）
# 使用--no-scripts禁用触发器执行，避免busybox触发器在arm64架构下的兼容性问题
RUN set -eux \
    && FILENAME=sonic \
    && apk add --no-cache --no-scripts --virtual .build-deps \
    gcc \
    g++ \
    musl-dev \
    git \
    build-base \
    # 包含strip命令
    binutils \
    upx \
    # 直接下载并构建 sonic（无需本地源代码）
    && git clone --depth 1 https://github.com/go-sonic/sonic . \
    # 构建纯静态二进制文件（无CGO）
    # && CGO_ENABLED=1 go build \
    && CGO_ENABLED=0 go build \
    -trimpath \
    -tags netgo,osusergo \
    -ldflags="-s -w" \
    # -gcflags="all=-trimpath=/app" \
    # -asmflags="all=-trimpath=/app" \
    -o $FILENAME \
    # 显示构建后的文件大小
    && echo "Binary size after build:" \
    # && du -h $FILENAME \
    && du -b $FILENAME \
    # 使用strip进一步减小二进制文件大小
    && strip --strip-all $FILENAME \
    && echo "Binary size after stripping:" \
    # && du -h $FILENAME \
    && du -b $FILENAME \
    # 这个压缩方法已经很好了 均衡
    && upx --best --lzma $FILENAME \
    # 极致压榨
    # && upx --ultra-brute $FILENAME \
    && echo "Binary size after upx:" \
    # && du -h $FILENAME \
    && du -b $FILENAME \
    # 注意：这里故意不清理构建依赖，因为是多阶段构建，且清理会触发busybox触发器错误
    # 最终镜像只复制二进制文件，构建阶段的中间层不会影响最终镜像大小
    # # 清理构建依赖
    # && apk del --purge .build-deps \
    # && rm -rf /var/cache/apk/*
    && mkdir -p /app/conf \
    && mkdir -p /app/resources \
    && cp sonic /app/ \
    && cp -r conf /app/ \
    && cp -r resources /app/ \
    && cp scripts/docker_init.sh /app/


# 运行时阶段 - 使用busybox:musl（极小的基础镜像，包含基本shell）
# FROM busybox:musl
FROM scratch AS prod

# # 构建参数：必须与构建阶段相同，使用相同的变量名
# ARG FILENAME

# 复制CA证书（用于HTTPS请求）
# COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

# 复制经过strip优化的sonic二进制文件（无论构建时的文件名是什么，运行时都使用/sonic）
COPY --from=builder /app/ /app/

# 创建非root用户（增强安全性）
# RUN adduser -D -u 1000 sonic

# 设置工作目录
WORKDIR /src

# 切换到非root用户
# USER sonic

# Go 运行时优化：垃圾回收器（GC）调优
# GOGC 环境变量控制GC的频率。默认值是100，表示当堆大小翻倍时触发GC。
# 在内存充足的环境中，增大此值（例如 GOGC=200）可以减少GC的运行频率，
# 从而可能提升程序性能，但代价是消耗更多的内存。
# 您可以在 `docker run` 时通过 `-e GOGC=200` 来覆盖此默认设置。
ENV GOGC=100

# 健康检查
# HEALTHCHECK --interval=60s --timeout=1s --start-period=5s --retries=1 \
#     CMD $FILENAME version > /dev/null || exit 1

VOLUME /sonic
EXPOSE 8080

WORKDIR /sonic
CMD /app/docker_init.sh && /app/sonic -config /sonic/conf/config.yaml
