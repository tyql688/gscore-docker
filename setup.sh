#!/bin/sh
# gsuid_core Docker 环境初始化脚本

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "${BLUE}================================================${NC}"
echo "${BLUE}gsuid_core Docker 环境初始化${NC}"
echo "${BLUE}================================================${NC}"
echo ""

# 选择部署方式
echo "${YELLOW}选择部署方式:${NC}"
echo "  1) 构建本地镜像 (使用本地 Dockerfile)"
echo "  2) 使用远程镜像 (从镜像仓库拉取)"
echo ""
printf "请输入选择 [1-2]: "
read -r deploy_choice

case "$deploy_choice" in
    1)
        USE_LOCAL_BUILD="true"
        echo "${GREEN}✓ 将构建本地镜像${NC}"
        ;;
    2)
        USE_LOCAL_BUILD="false"
        echo "${GREEN}✓ 将使用远程镜像${NC}"
        # 选择远程镜像
        echo ""
        echo "${YELLOW}选择远程镜像源:${NC}"
        echo "  1) CNB 加速 (docker.cnb.cool/gscore-mirror/gscore-docker:latest)"
        echo "  2) Docker Hub (tyql688/gscore:latest)"
        echo "  3) 自定义镜像地址"
        echo ""
        printf "请输入选择 [1-3]: "
        read -r image_choice

        case "$image_choice" in
            1)
                REMOTE_IMAGE="docker.cnb.cool/gscore-mirror/gscore-docker:latest"
                echo "${GREEN}✓ 使用 CNB 加速镜像${NC}"
                ;;
            2)
                REMOTE_IMAGE="tyql688/gscore:latest"
                echo "${GREEN}✓ 使用 Docker Hub 镜像${NC}"
                ;;
            3)
                printf "请输入镜像地址: "
                read -r image_input
                if [ -z "$image_input" ]; then
                    echo "${RED}错误: 镜像地址不能为空${NC}" >&2
                    exit 1
                fi
                REMOTE_IMAGE="$image_input"
                echo "${GREEN}✓ 使用自定义镜像: $REMOTE_IMAGE${NC}"
                ;;
            *)
                echo "${RED}错误: 无效选择${NC}" >&2
                exit 1
                ;;
        esac
        ;;
    *)
        echo "${RED}错误: 无效选择${NC}" >&2
        exit 1
        ;;
esac

echo ""

# 设置端口
echo "${YELLOW}设置端口号 (默认: 8765):${NC}"
printf "请输入端口号或直接回车使用默认值: "
read -r port_input

if [ -z "$port_input" ]; then
    PORT="8765"
    echo "${GREEN}✓ 使用默认端口: 8765${NC}"
else
    PORT="$port_input"
    echo "${GREEN}✓ 使用端口: $PORT${NC}"
fi

echo ""

# 设置挂载目录
DEFAULT_MOUNT="$(pwd)/gsuid_core"
echo "${YELLOW}设置挂载目录 (默认: $DEFAULT_MOUNT):${NC}"
printf "请输入路径或直接回车使用默认值: "
read -r mount_input

if [ -z "$mount_input" ]; then
    MOUNT_PATH="$DEFAULT_MOUNT"
    echo "${GREEN}✓ 使用默认挂载目录: $MOUNT_PATH${NC}"
else
    MOUNT_PATH="$mount_input"
    echo "${GREEN}✓ 使用挂载目录: $MOUNT_PATH${NC}"
fi

echo ""

# 检测挂载目录是否有数据
if [ ! -d "$MOUNT_PATH" ] || [ -z "$(ls -A "$MOUNT_PATH" 2>/dev/null)" ]; then
    echo "${YELLOW}检测到挂载目录为空或不存在${NC}"
    echo "${YELLOW}是否需要克隆 gsuid_core 源码? [Y/n]:${NC}"
    printf "请输入选择: "
    read -r clone_choice

    if [ "$clone_choice" != "n" ] && [ "$clone_choice" != "N" ]; then
        echo ""
        echo "${YELLOW}选择源码源:${NC}"
        echo "  1) GitHub (https://github.com/Genshin-bots/gsuid_core)"
        echo "  2) CNB 加速 (https://cnb.cool/gscore-mirror/gsuid_core)"
        echo ""
        printf "请输入选择 [1-2]: "
        read -r source_choice

        case "$source_choice" in
            1)
                SOURCE_URL="https://github.com/Genshin-bots/gsuid_core.git"
                echo "${GREEN}✓ 使用 GitHub 源${NC}"
                ;;
            2)
                SOURCE_URL="https://cnb.cool/gscore-mirror/gsuid_core.git"
                echo "${GREEN}✓ 使用 CNB 加速源${NC}"
                ;;
            *)
                echo "${RED}错误: 无效选择${NC}" >&2
                exit 1
                ;;
        esac

        echo ""
        echo "${YELLOW}正在克隆源码到 $MOUNT_PATH ...${NC}"
        git clone "$SOURCE_URL" "$MOUNT_PATH"
        echo "${GREEN}✓ 源码克隆完成${NC}"
    fi
fi

echo ""

# 生成配置文件
if [ "$USE_LOCAL_BUILD" = "true" ]; then
    echo "${YELLOW}生成 Dockerfile...${NC}"
    cat > Dockerfile << 'EOF'
# 基于 astral/uv 的 Python 3.12 Alpine 镜像
FROM astral/uv:python3.12-alpine

# 设置工作目录
WORKDIR /gsuid_core

# 暴露 8765 端口
EXPOSE 8765

# 安装系统依赖（包括编译工具和时区数据）
RUN apk add --no-cache \
    git \
    curl \
    gcc \
    python3-dev \
    musl-dev \
    linux-headers \
    tzdata && \
    ln -snf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && echo Asia/Shanghai > /etc/timezone

# 启动命令
CMD ["uv", "run", "core", "--host", "0.0.0.0"]
EOF
    echo "${GREEN}✓ Dockerfile 已生成${NC}"
fi

# 生成 .env 文件
echo "${YELLOW}生成 .env 文件...${NC}"
cat > .env << EOF
# gsuid_core 环境配置

# 端口映射
PORT=${PORT}

# 挂载目录
MOUNT_PATH=${MOUNT_PATH}
EOF
echo "${GREEN}✓ .env 文件已生成${NC}"

echo "${YELLOW}生成 docker-compose.yaml 文件...${NC}"

# 生成 docker-compose.yaml 文件
if [ "$USE_LOCAL_BUILD" = "true" ]; then
    cat > docker-compose.yaml << 'EOF'
# gsuid_core Docker Compose 配置
# 部署方式: 本地构建

services:
  gsuid_core:
    build:
      context: .
      dockerfile: Dockerfile
    image: gscore:local
    container_name: gsuid_core
    ports:
      - "${PORT:-8765}:8765"
    volumes:
      - ${MOUNT_PATH:-./gsuid_core}:/gsuid_core
    restart: unless-stopped
    environment:
      - PYTHONUNBUFFERED=1
EOF
else
    cat > docker-compose.yaml << EOF
# gsuid_core Docker Compose 配置
# 部署方式: 远程镜像

services:
  gsuid_core:
    image: ${REMOTE_IMAGE}
    container_name: gsuid_core
    ports:
      - "\${PORT:-8765}:8765"
    volumes:
      - \${MOUNT_PATH:-./gsuid_core}:/gsuid_core
    restart: unless-stopped
    environment:
      - PYTHONUNBUFFERED=1
EOF
fi

echo "${GREEN}✓ docker-compose.yaml 文件已生成${NC}"
echo ""

# 询问是否立即构建/拉取镜像
echo "${YELLOW}是否立即构建镜像? [Y/n]:${NC}"
printf "请输入选择: "
read -r build_now

if [ "$build_now" != "n" ] && [ "$build_now" != "N" ]; then
    echo ""
    echo "${YELLOW}正在构建镜像...${NC}"
    if [ "$USE_LOCAL_BUILD" = "true" ]; then
        docker-compose build
    else
        docker-compose pull
    fi
    echo "${GREEN}✓ 镜像准备完成${NC}"
fi

echo ""
echo "${GREEN}================================================${NC}"
echo "${GREEN}初始化完成！${NC}"
echo "${GREEN}================================================${NC}"
echo ""
echo "配置文件: ${GREEN}docker-compose.yaml${NC}"
echo ""
echo "运行方式:"
echo "  ${YELLOW}启动服务:${NC}"
echo "    docker-compose up -d"
echo ""
echo "  ${YELLOW}查看日志:${NC}"
echo "    docker-compose logs -f"
echo ""
echo "  ${YELLOW}停止服务:${NC}"
echo "    docker-compose down"
echo ""
echo "  ${YELLOW}重新配置:${NC}"
echo "    ./setup.sh"
echo ""
