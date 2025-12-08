#!/bin/sh
# gsuid_core Docker 环境初始化脚本

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 脚本版本
VERSION="1.0.2"
REMOTE_SCRIPT_URL="https://cnb.cool/gscore-mirror/gscore-docker/-/git/raw/main/setup.sh"

# 检查更新
check_update() {
    echo "${YELLOW}检查脚本更新...${NC}"

    # 获取远程脚本的版本号
    REMOTE_VERSION=$(curl -sL "$REMOTE_SCRIPT_URL" 2>/dev/null | grep '^VERSION=' | head -1 | cut -d'"' -f2)

    if [ -z "$REMOTE_VERSION" ]; then
        echo "${YELLOW}无法获取远程版本信息, 跳过更新检查${NC}"
        return
    fi

    if [ "$REMOTE_VERSION" != "$VERSION" ]; then
        echo "${YELLOW}发现新版本: $REMOTE_VERSION (当前: $VERSION)${NC}"
        printf "是否更新脚本? [Y/n]: "
        read -r update_choice

        if [ "$update_choice" != "n" ] && [ "$update_choice" != "N" ]; then
            echo "${YELLOW}正在更新脚本...${NC}"
            curl -sL "$REMOTE_SCRIPT_URL" -o "$0.tmp" && mv "$0.tmp" "$0" && chmod +x "$0"
            echo "${GREEN}脚本已更新, 请重新运行 ./setup.sh${NC}"
            exit 0
        fi
    else
        echo "${GREEN}当前已是最新版本 ($VERSION)${NC}"
    fi
    echo ""
}

# 检查更新
check_update

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

# 安装插件
install_plugins() {
    PLUGINS_DIR="$MOUNT_PATH/gsuid_core/plugins"

    echo "${YELLOW}是否需要安装插件? [y/N]:${NC}"
    printf "请输入选择: "
    read -r install_choice

    if [ "$install_choice" != "y" ] && [ "$install_choice" != "Y" ]; then
        return
    fi

    echo ""
    echo "${YELLOW}选择插件源:${NC}"
    echo "  1) GitHub"
    echo "  2) CNB 加速"
    echo ""
    printf "请输入选择 [1-2]: "
    read -r plugin_source

    case "$plugin_source" in
        1) USE_CNB="false" ;;
        2) USE_CNB="true" ;;
        *)
            echo "${RED}错误: 无效选择${NC}" >&2
            return
            ;;
    esac

    # 插件数量
    PLUGIN_COUNT=16

    # 插件名称和描述
    PLUGIN_NAME_1="GenshinUID";      PLUGIN_DESC_1="原神"
    PLUGIN_NAME_2="StarRailUID";     PLUGIN_DESC_2="星穹铁道"
    PLUGIN_NAME_3="ZZZeroUID";       PLUGIN_DESC_3="绝区零"
    PLUGIN_NAME_4="XutheringWavesUID"; PLUGIN_DESC_4="鸣潮"
    PLUGIN_NAME_5="WzryUID";         PLUGIN_DESC_5="王者荣耀"
    PLUGIN_NAME_6="LOLegendsUID";    PLUGIN_DESC_6="英雄联盟"
    PLUGIN_NAME_7="MajsoulUID";      PLUGIN_DESC_7="雀魂"
    PLUGIN_NAME_8="CS2UID";          PLUGIN_DESC_8="CS2"
    PLUGIN_NAME_9="BlueArchiveUID";  PLUGIN_DESC_9="蔚蓝档案"
    PLUGIN_NAME_10="VAUID";          PLUGIN_DESC_10="无畏契约"
    PLUGIN_NAME_11="DeltaUID";       PLUGIN_DESC_11="三角洲"
    PLUGIN_NAME_12="DNAUID";         PLUGIN_DESC_12="二重螺旋"
    PLUGIN_NAME_13="SayuStock";      PLUGIN_DESC_13="早柚股票"
    PLUGIN_NAME_14="RoverSign";      PLUGIN_DESC_14="鸣潮签到"
    PLUGIN_NAME_15="ScoreEcho";      PLUGIN_DESC_15="小维OCR识别声骸并评分"
    PLUGIN_NAME_16="TodayEcho";      PLUGIN_DESC_16="小维声骸强化模拟插件"

    # CNB 镜像 URL 映射 (用于替换源)
    CNB_URL_1="https://cnb.cool/gscore-mirror/GenshinUID.git"
    CNB_URL_2="https://cnb.cool/gscore-mirror/StarRailUID.git"
    CNB_URL_3="https://cnb.cool/gscore-mirror/ZZZeroUID.git"
    CNB_URL_4="https://cnb.cool/gscore-mirror/XutheringWavesUID.git"
    CNB_URL_5="https://cnb.cool/gscore-mirror/WzryUID.git"
    CNB_URL_6="https://cnb.cool/gscore-mirror/LOLegendsUID.git"
    CNB_URL_7="https://cnb.cool/gscore-mirror/MajsoulUID.git"
    CNB_URL_8="https://cnb.cool/gscore-mirror/CS2UID.git"
    CNB_URL_9="https://cnb.cool/gscore-mirror/BlueArchiveUID.git"
    CNB_URL_10="https://cnb.cool/gscore-mirror/VAUID.git"
    CNB_URL_11="https://cnb.cool/gscore-mirror/DeltaUID.git"
    CNB_URL_12="https://cnb.cool/gscore-mirror/DNAUID.git"
    CNB_URL_13="https://cnb.cool/gscore-mirror/SayuStock.git"
    CNB_URL_14="https://cnb.cool/gscore-mirror/RoverSign.git"
    CNB_URL_15="https://cnb.cool/gscore-mirror/ScoreEcho.git"
    CNB_URL_16="https://cnb.cool/gscore-mirror/TodayEcho.git"

    # 选择状态
    SEL_1=0; SEL_2=0; SEL_3=0; SEL_4=0; SEL_5=0; SEL_6=0; SEL_7=0; SEL_8=0
    SEL_9=0; SEL_10=0; SEL_11=0; SEL_12=0; SEL_13=0; SEL_14=0; SEL_15=0; SEL_16=0

    # 显示菜单
    show_menu() {
        echo ""
        echo "${YELLOW}选择要安装的插件:${NC}"
        echo "  输入编号切换选择, a=全选, n=取消全选, 回车=确认"
        echo ""
        i=1
        while [ $i -le $PLUGIN_COUNT ]; do
            eval "selected=\$SEL_$i"
            eval "name=\$PLUGIN_NAME_$i"
            eval "desc=\$PLUGIN_DESC_$i"
            if [ "$selected" = "1" ]; then
                printf "  ${GREEN}[x]${NC} %2d) %-20s %s\n" "$i" "$name" "$desc"
            else
                printf "  [ ] %2d) %-20s %s\n" "$i" "$name" "$desc"
            fi
            i=$((i+1))
        done
        echo ""
    }

    # 交互循环
    while true; do
        show_menu
        printf "请输入: "
        read -r choice

        # 回车确认
        if [ -z "$choice" ]; then
            break
        fi

        # 全选
        if [ "$choice" = "a" ] || [ "$choice" = "A" ]; then
            i=1; while [ $i -le $PLUGIN_COUNT ]; do eval "SEL_$i=1"; i=$((i+1)); done
            continue
        fi

        # 取消全选
        if [ "$choice" = "n" ] || [ "$choice" = "N" ]; then
            i=1; while [ $i -le $PLUGIN_COUNT ]; do eval "SEL_$i=0"; i=$((i+1)); done
            continue
        fi

        # 切换选择状态
        if [ "$choice" -ge 1 ] 2>/dev/null && [ "$choice" -le 16 ]; then
            eval "current=\$SEL_$choice"
            if [ "$current" = "1" ]; then
                eval "SEL_$choice=0"
            else
                eval "SEL_$choice=1"
            fi
        fi
    done

    # 插件 URL 映射
    if [ "$USE_CNB" = "true" ]; then
        PLUGIN_1="https://cnb.cool/gscore-mirror/GenshinUID.git"
        PLUGIN_2="https://cnb.cool/gscore-mirror/StarRailUID.git"
        PLUGIN_3="https://cnb.cool/gscore-mirror/ZZZeroUID.git"
        PLUGIN_4="https://cnb.cool/gscore-mirror/XutheringWavesUID.git"
        PLUGIN_5="https://cnb.cool/gscore-mirror/WzryUID.git"
        PLUGIN_6="https://cnb.cool/gscore-mirror/LOLegendsUID.git"
        PLUGIN_7="https://cnb.cool/gscore-mirror/MajsoulUID.git"
        PLUGIN_8="https://cnb.cool/gscore-mirror/CS2UID.git"
        PLUGIN_9="https://cnb.cool/gscore-mirror/BlueArchiveUID.git"
        PLUGIN_10="https://cnb.cool/gscore-mirror/VAUID.git"
        PLUGIN_11="https://cnb.cool/gscore-mirror/DeltaUID.git"
        PLUGIN_12="https://cnb.cool/gscore-mirror/DNAUID.git"
        PLUGIN_13="https://cnb.cool/gscore-mirror/SayuStock.git"
        PLUGIN_14="https://cnb.cool/gscore-mirror/RoverSign.git"
        PLUGIN_15="https://cnb.cool/gscore-mirror/ScoreEcho.git"
        PLUGIN_16="https://cnb.cool/gscore-mirror/TodayEcho.git"
    else
        PLUGIN_1="https://github.com/KimigaiiWuyi/GenshinUID.git"
        PLUGIN_2="https://github.com/baiqwerdvd/StarRailUID.git"
        PLUGIN_3="https://github.com/ZZZure/ZZZeroUID.git"
        PLUGIN_4="https://github.com/Loping151/XutheringWavesUID.git"
        PLUGIN_5="https://github.com/KimigaiiWuyi/WzryUID.git"
        PLUGIN_6="https://github.com/KimigaiiWuyi/LOLegendsUID.git"
        PLUGIN_7="https://github.com/KimigaiiWuyi/MajsoulUID.git"
        PLUGIN_8="https://github.com/Agnes4m/CS2UID.git"
        PLUGIN_9="https://github.com/KimigaiiWuyi/BlueArchiveUID.git"
        PLUGIN_10="https://github.com/Agnes4m/VAUID.git"
        PLUGIN_11="https://github.com/Agnes4m/DeltaUID.git"
        PLUGIN_12="https://github.com/tyql688/DNAUID.git"
        PLUGIN_13="https://github.com/KimigaiiWuyi/SayuStock.git"
        PLUGIN_14="https://github.com/Loping151/RoverSign.git"
        PLUGIN_15="https://github.com/Loping151/ScoreEcho.git"
        PLUGIN_16="https://github.com/Loping151/TodayEcho.git"
    fi

    # 创建插件目录
    mkdir -p "$PLUGINS_DIR"

    # 安装已选插件
    echo ""
    installed=0
    i=1
    while [ $i -le $PLUGIN_COUNT ]; do
        eval "selected=\$SEL_$i"
        if [ "$selected" = "1" ]; then
            eval "url=\$PLUGIN_$i"
            eval "name=\$PLUGIN_NAME_$i"

            if [ -d "$PLUGINS_DIR/$name" ]; then
                # 检查当前远程源
                current_remote=$(git -C "$PLUGINS_DIR/$name" remote get-url origin 2>/dev/null || echo "")

                # 判断当前源类型
                if echo "$current_remote" | grep -q "github.com"; then
                    current_source="GitHub"
                elif echo "$current_remote" | grep -q "cnb.cool"; then
                    current_source="CNB"
                else
                    current_source="未知"
                fi

                # 判断用户选择的源类型
                if [ "$USE_CNB" = "true" ]; then
                    selected_source="CNB"
                else
                    selected_source="GitHub"
                fi

                # 检查是否一致
                if [ "$current_source" != "$selected_source" ]; then
                    echo "${YELLOW}插件 $name 已存在 (当前源: $current_source, 选择源: $selected_source)${NC}"
                    printf "  是否替换为 $selected_source 源? [y/N]: "
                    read -r switch_choice
                    if [ "$switch_choice" = "y" ] || [ "$switch_choice" = "Y" ]; then
                        git -C "$PLUGINS_DIR/$name" remote set-url origin "$url"
                        echo "${GREEN}  [OK] 已替换为 $selected_source 源${NC}"
                    else
                        echo "${YELLOW}  跳过${NC}"
                    fi
                else
                    echo "${YELLOW}插件 $name 已存在 (源: $current_source), 跳过${NC}"
                fi
            else
                echo "${YELLOW}正在安装 $name ...${NC}"
                if git clone --progress "$url" "$PLUGINS_DIR/$name"; then
                    echo "${GREEN}[OK] $name 安装完成${NC}"
                else
                    echo "${RED}[FAIL] $name 安装失败${NC}"
                fi
            fi
            installed=1
        fi
        i=$((i+1))
    done

    if [ "$installed" = "1" ]; then
        echo "${GREEN}插件安装完成${NC}"
    else
        echo "${YELLOW}未选择任何插件${NC}"
    fi
}

# 调用插件安装
install_plugins

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

# 在镜像层创建 venv（/venv 不会被挂载覆盖）
RUN uv venv --seed /venv

# 告诉 uv 永远用它
ENV UV_PROJECT_ENVIRONMENT=/venv

# 启动命令
CMD ["uv", "run", "--python", "/venv/bin/python", "core", "--host", "0.0.0.0"]
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
