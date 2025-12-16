#!/bin/sh
# gsuid_core Docker 环境初始化脚本

set -e

# =============================================================================
# 全局变量
# =============================================================================
VERSION="1.3.4"
REMOTE_SCRIPT_URL="https://cnb.cool/gscore-mirror/gscore-docker/-/git/raw/main/setup.sh"

# 配置变量
USE_LOCAL_BUILD=""
REMOTE_IMAGE=""
UPDATE_COMPOSE="true"
PORT=""
MOUNT_PATH=""
CURRENT_DIR="$(pwd)"
DEFAULT_MOUNT="${CURRENT_DIR}/gsuid_core"
AUTO_YES="false"
PLUGIN_ONLY_MODE="false"
PLUGIN_UNINSTALL_MODE="false"

# =============================================================================
# 颜色配置
# =============================================================================
init_colors() {
    if [ -t 1 ]; then
        if command -v tput >/dev/null 2>&1; then
            RED=$(tput setaf 1)
            GREEN=$(tput setaf 2)
            YELLOW=$(tput setaf 3)
            BLUE=$(tput setaf 4)
            NC=$(tput sgr0)
        else
            RED='\033[0;31m'
            GREEN='\033[0;32m'
            YELLOW='\033[1;33m'
            BLUE='\033[0;34m'
            NC='\033[0m'
        fi
    else
        RED='' GREEN='' YELLOW='' BLUE='' NC=''
    fi
}

# =============================================================================
# 显示帮助信息
# =============================================================================
show_help() {
    init_colors
    echo "${BLUE}gsuid_core Docker 环境初始化脚本 v${VERSION}${NC}"
    echo ""
    echo "${YELLOW}用法:${NC}"
    echo "  ./setup.sh          运行交互式配置向导"
    echo "  ./setup.sh -y       使用默认配置快速安装"
    echo "  ./setup.sh -i       交互式安装插件"
    echo "  ./setup.sh -ui      交互式卸载插件"
    echo "  ./setup.sh -h       显示帮助信息"
    echo ""
    echo "${YELLOW}-y 默认配置:${NC}"
    echo "  - Docker镜像源: CNB 加速
  - 端口: 8765
  - 目录: ${PWD}/gsuid_core
  - 源码源: CNB 加速
  - 不安装插件
  - 不配置代理"
    echo ""
    echo "${YELLOW}-i 模式说明:${NC}"
    echo "  - 交互式选择要安装的插件"
    echo ""
    echo "${YELLOW}-ui 模式说明:${NC}"
    echo "  - 交互式选择要卸载的插件"
    echo ""
    echo "${YELLOW}常用 Docker 命令:${NC}"
    echo ""
    echo "  ${GREEN}启动服务:${NC}              docker-compose up -d"
    echo "  ${GREEN}查看日志:${NC}              docker-compose logs -f"
    echo "  ${GREEN}重启服务:${NC}              docker-compose restart"
    echo "  ${GREEN}重新构建并启动:${NC}        docker-compose up -d --build"
    echo "  ${GREEN}停止服务:${NC}              docker-compose down"
    echo "  ${GREEN}停止并删除虚拟环境:${NC}    docker-compose down --volumes"
    echo "  ${GREEN}进入容器 shell:${NC}        docker exec -it gsuid_core sh"
    echo "  ${GREEN}安装 Python 包:${NC}        docker exec -it gsuid_core uv pip install <包名>"
    echo "  ${GREEN}查看状态:${NC}              docker-compose ps"
    echo "  ${GREEN}查看资源使用:${NC}          docker stats gsuid_core"
    echo "  ${GREEN}配置 git 代理:${NC}         docker exec -it gsuid_core git config --global http.proxy http://host.docker.internal:7890"
    echo ""
    echo "${YELLOW}配置文件:${NC}"
    echo "  .env                环境变量配置"
    echo "  docker-compose.yaml Docker Compose 配置"
    echo "  Dockerfile          本地构建镜像配置"
    echo ""
    exit 0
}

# =============================================================================
# 检查更新
# =============================================================================
check_update() {
    echo "${YELLOW}检查脚本更新...${NC}"
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

# =============================================================================
# 检测现有配置
# =============================================================================
detect_existing_config() {
    if [ "$AUTO_YES" = "true" ]; then
        return
    fi

    if [ ! -f "docker-compose.yaml" ]; then
        return
    fi

    if grep -q "build:" docker-compose.yaml; then
        EXISTING_MODE="local"
        EXISTING_IMAGE_INFO="本地构建 (local build)"
    elif grep -q "image:" docker-compose.yaml; then
        EXISTING_MODE="remote"
        EXISTING_IMAGE=$(grep "image:" docker-compose.yaml | head -1 | awk '{print $2}')
        EXISTING_IMAGE_INFO="远程镜像 ($EXISTING_IMAGE)"
    fi

    if [ -n "$EXISTING_MODE" ]; then
        echo "${YELLOW}检测到当前配置为: $EXISTING_IMAGE_INFO${NC}"
        printf "是否保持当前部署配置? [Y/n]: "
        read -r keep_config

        if [ "$keep_config" != "n" ] && [ "$keep_config" != "N" ]; then
            if [ "$EXISTING_MODE" = "local" ]; then
                USE_LOCAL_BUILD="true"
            else
                USE_LOCAL_BUILD="false"
                REMOTE_IMAGE="$EXISTING_IMAGE"
            fi
            UPDATE_COMPOSE="false"
            echo "${GREEN}✓ 保持当前配置，将跳过重新生成 docker-compose.yaml${NC}"
        else
            echo "${YELLOW}即将重新配置部署方式...${NC}"
        fi
        echo ""
    fi
}

# =============================================================================
# 选择部署方式
# =============================================================================
select_deploy_mode() {
    if [ -n "$USE_LOCAL_BUILD" ]; then
        return
    fi

    if [ "$AUTO_YES" = "true" ]; then
        USE_LOCAL_BUILD="false"
        REMOTE_IMAGE="docker.cnb.cool/gscore-mirror/gscore-docker:latest"
        echo "${GREEN}✓ 使用默认配置: 远程镜像 (CNB 加速)${NC}"
        return
    fi

    echo "${YELLOW}选择部署方式:${NC}"
    echo "  1) 使用远程镜像 (从镜像仓库拉取)"
    echo "  2) 构建本地镜像 (使用本地 Dockerfile)"
    echo ""
    printf "请输入选择 [1-2]: "
    read -r deploy_choice

    case "$deploy_choice" in
        1)
            USE_LOCAL_BUILD="false"
            echo "${GREEN}✓ 将使用远程镜像${NC}"
            select_remote_image
            ;;
        2)
            USE_LOCAL_BUILD="true"
            echo "${GREEN}✓ 将构建本地镜像${NC}"
            ;;
        *)
            echo "${RED}错误: 无效选择${NC}" >&2
            exit 1
            ;;
    esac
}

# =============================================================================
# 选择远程镜像
# =============================================================================
select_remote_image() {
    echo ""
    echo "${YELLOW}选择远程镜像源:${NC}"
    echo "  1) CNB 加速 (docker.cnb.cool/gscore-mirror/gscore-docker:latest)"
    echo "  2) CNB Playwright (docker.cnb.cool/gscore-mirror/gscore-docker/playwright:latest)"
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
            REMOTE_IMAGE="docker.cnb.cool/gscore-mirror/gscore-docker/playwright:latest"
            echo "${GREEN}✓ 使用 CNB Playwright 镜像${NC}"
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
}

# =============================================================================
# 配置端口
# =============================================================================
configure_port() {
    # 尝试从 .env 读取
    if [ -f ".env" ]; then
        ENV_PORT=$(grep "^PORT=" .env | cut -d'=' -f2- | tr -d '"' | tr -d "'")
        if [ -n "$ENV_PORT" ]; then
            if [ "$AUTO_YES" = "true" ]; then
                PORT="$ENV_PORT"
                echo "${GREEN}✓ 使用默认端口: $PORT${NC}"
                return
            fi
            echo "${YELLOW}检测到已配置端口: ${ENV_PORT}${NC}"
            printf "是否修改端口? [y/N]: "
            read -r change_port
            if [ "$change_port" != "y" ] && [ "$change_port" != "Y" ]; then
                PORT="$ENV_PORT"
                echo "${GREEN}✓ 保持使用端口: $PORT${NC}"
                return
            fi
        fi
    fi

    if [ "$AUTO_YES" = "true" ]; then
        PORT="8765"
        echo "${GREEN}✓ 使用默认端口: 8765${NC}"
        return
    fi

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
}

# =============================================================================
# 配置挂载目录
# =============================================================================
configure_mount_path() {
    # 尝试从 .env 读取
    if [ -f ".env" ]; then
        ENV_MOUNT_PATH=$(grep "^MOUNT_PATH=" .env | cut -d'=' -f2- | tr -d '"' | tr -d "'")
        if [ -n "$ENV_MOUNT_PATH" ]; then
            if [ "$AUTO_YES" = "true" ]; then
                MOUNT_PATH="$ENV_MOUNT_PATH"
                echo "${GREEN}✓ 使用默认挂载目录: $MOUNT_PATH${NC}"
                return
            fi
            echo "${YELLOW}检测到已配置挂载目录: ${ENV_MOUNT_PATH}${NC}"
            printf "是否修改挂载目录? [y/N]: "
            read -r change_mount
            if [ "$change_mount" != "y" ] && [ "$change_mount" != "Y" ]; then
                MOUNT_PATH="$ENV_MOUNT_PATH"
                echo "${GREEN}✓ 保持使用: $MOUNT_PATH${NC}"
                return
            fi
        fi
    fi

    if [ "$AUTO_YES" = "true" ]; then
        MOUNT_PATH="$DEFAULT_MOUNT"
        echo "${GREEN}✓ 使用默认挂载目录: $MOUNT_PATH${NC}"
        return
    fi

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
}

# =============================================================================
# 配置 git safe.directory
# =============================================================================
configure_git_safe_directory() {
    if ! git config --global --get-all safe.directory 2>/dev/null | grep -q "^${MOUNT_PATH}$"; then
        echo "${YELLOW}添加 ${MOUNT_PATH} 到 git safe.directory...${NC}"
        git config --global --add safe.directory "${MOUNT_PATH}"
    fi

    SUBDIR_PATTERN="/gsuid_core/*"
    if ! git config --global --get-all safe.directory 2>/dev/null | grep -q "^${SUBDIR_PATTERN}$"; then
        echo "${YELLOW}添加 ${SUBDIR_PATTERN} 到 git safe.directory...${NC}"
        git config --global --add safe.directory "${SUBDIR_PATTERN}"
    fi
}

# =============================================================================
# 克隆源码
# =============================================================================
clone_source() {
    if [ -d "$MOUNT_PATH" ] && [ -n "$(ls -A "$MOUNT_PATH" 2>/dev/null)" ]; then
        return
    fi

    if [ "$AUTO_YES" = "true" ]; then
        SOURCE_URL="https://cnb.cool/gscore-mirror/gsuid_core.git"
        echo "${YELLOW}正在克隆源码到 $MOUNT_PATH (CNB 加速)...${NC}"
        git clone "$SOURCE_URL" "$MOUNT_PATH"
        echo "${GREEN}✓ 源码克隆完成${NC}"
        return
    fi

    echo "${YELLOW}检测到挂载目录为空或不存在${NC}"
    echo "${YELLOW}是否需要克隆 gsuid_core 源码? [Y/n]:${NC}"
    printf "请输入选择: "
    read -r clone_choice

    if [ "$clone_choice" = "n" ] || [ "$clone_choice" = "N" ]; then
        return
    fi

    echo ""
    echo "${YELLOW}选择源码源:${NC}"
    echo "  1) CNB 加速 (https://cnb.cool/gscore-mirror/gsuid_core)"
    echo "  2) GitHub (https://github.com/Genshin-bots/gsuid_core)"
    echo ""
    printf "请输入选择 [1-2]: "
    read -r source_choice

    case "$source_choice" in
        1)
            SOURCE_URL="https://cnb.cool/gscore-mirror/gsuid_core.git"
            echo "${GREEN}✓ 使用 CNB 加速源${NC}"
            ;;
        2)
            SOURCE_URL="https://github.com/Genshin-bots/gsuid_core.git"
            echo "${GREEN}✓ 使用 GitHub 源${NC}"
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
}

# =============================================================================
# 定义插件信息
# =============================================================================
define_plugins() {
    # 插件配置
    PLUGIN_COUNT=16
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

    # 设置插件 URL
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
}

# =============================================================================
# 安装插件
# =============================================================================
install_plugins() {
    PLUGINS_DIR="$MOUNT_PATH/gsuid_core/plugins"

    if [ "$PLUGIN_ONLY_MODE" = "true" ]; then
        # -i 模式：交互式安装插件，跳过"是否需要安装"确认
        echo "${YELLOW}插件安装模式 (仅安装插件，其他配置跳过)${NC}"
    elif [ "$AUTO_YES" = "true" ]; then
        echo "${YELLOW}跳过插件安装 (使用默认配置)${NC}"
        return
    else
        echo "${YELLOW}是否需要安装插件? [y/N]:${NC}"
        printf "请输入选择: "
        read -r install_choice

        if [ "$install_choice" != "y" ] && [ "$install_choice" != "Y" ]; then
            return
        fi
    fi

    echo ""
    echo "${YELLOW}选择插件源:${NC}"
    echo "  1) CNB 加速"
    echo "  2) GitHub"
    echo ""
    printf "请输入选择 [1-2]: "
    read -r plugin_source

    case "$plugin_source" in
        1) USE_CNB="true" ;;
        2) USE_CNB="false" ;;
        *)
            echo "${RED}错误: 无效选择${NC}" >&2
            return
            ;;
    esac

    # 插件配置
    define_plugins

    # 选择状态
    SEL_1=0; SEL_2=0; SEL_3=0; SEL_4=0; SEL_5=0; SEL_6=0; SEL_7=0; SEL_8=0
    SEL_9=0; SEL_10=0; SEL_11=0; SEL_12=0; SEL_13=0; SEL_14=0; SEL_15=0; SEL_16=0

    # 显示菜单
    show_plugin_menu() {
        echo ""
        echo "${YELLOW}选择要安装的插件:${NC}"
        echo "  输入编号切换选择, a=全选, n=取消全选, 回车=确认"
        echo ""
        i=1
        while [ $i -le $PLUGIN_COUNT ]; do
            eval "selected=\$SEL_$i"
            eval "name=\$PLUGIN_NAME_$i"
            eval "desc=\$PLUGIN_DESC_$i"

            if [ -d "$PLUGINS_DIR/$name" ]; then
                status_str="${GREEN}[已安装]${NC}"
            else
                status_str="${YELLOW}[未安装]${NC}"
            fi

            if [ "$selected" = "1" ]; then
                printf "  ${GREEN}[x]${NC} %2d) %-20s %-18s %s\n" "$i" "$name" "$status_str" "$desc"
            else
                printf "  [ ] %2d) %-20s %-18s %s\n" "$i" "$name" "$status_str" "$desc"
            fi
            i=$((i+1))
        done
        echo ""
    }

    # 交互循环
    while true; do
        show_plugin_menu
        printf "请输入: "
        read -r choice

        if [ -z "$choice" ]; then break; fi

        if [ "$choice" = "a" ] || [ "$choice" = "A" ]; then
            i=1; while [ $i -le $PLUGIN_COUNT ]; do eval "SEL_$i=1"; i=$((i+1)); done
            continue
        fi

        if [ "$choice" = "n" ] || [ "$choice" = "N" ]; then
            i=1; while [ $i -le $PLUGIN_COUNT ]; do eval "SEL_$i=0"; i=$((i+1)); done
            continue
        fi

        if [ "$choice" -ge 1 ] 2>/dev/null && [ "$choice" -le 16 ]; then
            eval "current=\$SEL_$choice"
            if [ "$current" = "1" ]; then
                eval "SEL_$choice=0"
            else
                eval "SEL_$choice=1"
            fi
        fi
    done

    mkdir -p "$PLUGINS_DIR"

    # 安装选中的插件
    echo ""
    installed=0
    i=1
    while [ $i -le $PLUGIN_COUNT ]; do
        eval "selected=\$SEL_$i"
        if [ "$selected" = "1" ]; then
            eval "url=\$PLUGIN_$i"
            eval "name=\$PLUGIN_NAME_$i"

            if [ -d "$PLUGINS_DIR/$name" ]; then
                current_remote=$(git -C "$PLUGINS_DIR/$name" remote get-url origin 2>/dev/null || echo "")

                if echo "$current_remote" | grep -q "github.com"; then
                    current_source="GitHub"
                elif echo "$current_remote" | grep -q "cnb.cool"; then
                    current_source="CNB"
                else
                    current_source="未知"
                fi

                if [ "$USE_CNB" = "true" ]; then
                    selected_source="CNB"
                else
                    selected_source="GitHub"
                fi

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

# =============================================================================
# 配置代理
# =============================================================================
configure_proxy() {
    if [ "$AUTO_YES" = "true" ]; then
        echo "${YELLOW}跳过代理配置 (使用默认配置)${NC}"
        return
    fi

    DELETE_PROXY="false"

    ENV_http_proxy=$(grep "^GSCORE_HTTP_PROXY=" .env 2>/dev/null | cut -d'=' -f2- | tr -d '"' | tr -d "'" || echo "")
    ENV_https_proxy=$(grep "^GSCORE_HTTPS_PROXY=" .env 2>/dev/null | cut -d'=' -f2- | tr -d '"' | tr -d "'" || echo "")
    ENV_no_proxy=$(grep "^GSCORE_NO_PROXY=" .env 2>/dev/null | cut -d'=' -f2- | tr -d '"' | tr -d "'" || echo "")

    if [ -n "$ENV_http_proxy" ] || [ -n "$ENV_https_proxy" ]; then
        echo "${YELLOW}检测到已配置代理:${NC}"
        [ -n "$ENV_http_proxy" ] && echo "  http_proxy: $ENV_http_proxy"
        [ -n "$ENV_https_proxy" ] && echo "  https_proxy: $ENV_https_proxy"
        [ -n "$ENV_no_proxy" ] && echo "  no_proxy: $ENV_no_proxy"
        echo ""
        printf "是否更改或删除代理配置? [y/N]: "
        read -r change_proxy

        if [ "$change_proxy" = "y" ] || [ "$change_proxy" = "Y" ]; then
            printf "请选择: 1)更改代理地址  2)删除代理配置 [1-2]: "
            read -r proxy_choice
            case "$proxy_choice" in
                1)
                    printf "请输入代理端口 (默认 7890): "
                    read -r proxy_port
                    proxy_port=${proxy_port:-7890}
                    ENV_http_proxy="http://host.docker.internal:$proxy_port"
                    ENV_https_proxy="http://host.docker.internal:$proxy_port"
                    [ -z "$ENV_no_proxy" ] && ENV_no_proxy="localhost,127.0.0.1,.local,cnb.cool"
                    ;;
                2)
                    DELETE_PROXY="true"
                    ;;
                *)
                    echo "${YELLOW}保持当前代理配置${NC}"
                    ;;
            esac
        fi
    else
        echo "${YELLOW}是否需要配置代理? [y/N]:${NC}"
        printf "请输入选择: "
        read -r setup_proxy

        if [ "$setup_proxy" = "y" ] || [ "$setup_proxy" = "Y" ]; then
            printf "请输入代理端口 (默认 7890): "
            read -r proxy_port
            proxy_port=${proxy_port:-7890}
            ENV_http_proxy="http://host.docker.internal:$proxy_port"
            ENV_https_proxy="http://host.docker.internal:$proxy_port"
            [ -z "$ENV_no_proxy" ] && ENV_no_proxy="localhost,127.0.0.1,.local,cnb.cool"
        fi
    fi

    # 更新 .env 文件
    if [ "$DELETE_PROXY" = "true" ]; then
        sed -i.bak '/^GSCORE_HTTP_PROXY=/d' .env 2>/dev/null || true
        sed -i.bak '/^GSCORE_HTTPS_PROXY=/d' .env 2>/dev/null || true
    else
        if [ -n "$ENV_http_proxy" ]; then
            if grep -q "^GSCORE_HTTP_PROXY=" .env 2>/dev/null; then
                sed -i.bak "s|^GSCORE_HTTP_PROXY=.*|GSCORE_HTTP_PROXY=$ENV_http_proxy|" .env 2>/dev/null || true
            else
                echo "GSCORE_HTTP_PROXY=$ENV_http_proxy" >> .env 2>/dev/null || true
            fi
        fi
        if [ -n "$ENV_https_proxy" ]; then
            if grep -q "^GSCORE_HTTPS_PROXY=" .env 2>/dev/null; then
                sed -i.bak "s|^GSCORE_HTTPS_PROXY=.*|GSCORE_HTTPS_PROXY=$ENV_https_proxy|" .env 2>/dev/null || true
            else
                echo "GSCORE_HTTPS_PROXY=$ENV_https_proxy" >> .env 2>/dev/null || true
            fi
        fi
        if [ -n "$ENV_no_proxy" ]; then
            if grep -q "^GSCORE_NO_PROXY=" .env 2>/dev/null; then
                sed -i.bak "s|^GSCORE_NO_PROXY=.*|GSCORE_NO_PROXY=$ENV_no_proxy|" .env 2>/dev/null || true
            else
                echo "GSCORE_NO_PROXY=$ENV_no_proxy" >> .env 2>/dev/null || true
            fi
        fi
    fi

    rm -f .env.bak 2>/dev/null || true

    # 显示结果
    if [ "$DELETE_PROXY" = "true" ]; then
        echo "${GREEN}✓ 代理配置已删除${NC}"
    elif [ -n "$ENV_http_proxy" ] || [ -n "$ENV_https_proxy" ]; then
        echo "${GREEN}✓ 代理配置已更新${NC}"
        [ -n "$ENV_http_proxy" ] && echo "  http_proxy: $ENV_http_proxy"
        [ -n "$ENV_https_proxy" ] && echo "  https_proxy: $ENV_https_proxy"
        [ -n "$ENV_no_proxy" ] && echo "  no_proxy: $ENV_no_proxy"
    else
        echo "${GREEN}✓ 未配置代理${NC}"
    fi
}

# =============================================================================
# 卸载插件 (-ui 标志)
# =============================================================================
uninstall_plugins() {
    PLUGINS_DIR="$MOUNT_PATH/gsuid_core/plugins"

    if [ ! -d "$PLUGINS_DIR" ]; then
        echo "${YELLOW}插件目录不存在: $PLUGINS_DIR${NC}"
        echo "${YELLOW}无需卸载任何插件${NC}"
        return
    fi

    # 获取已安装的插件列表
    INSTALLED_PLUGINS=""
    plugin_count=0
    for plugin_dir in "$PLUGINS_DIR"/*; do
        if [ -d "$plugin_dir" ]; then
            plugin_name=$(basename "$plugin_dir")
            INSTALLED_PLUGINS="$INSTALLED_PLUGINS $plugin_name"
            plugin_count=$((plugin_count + 1))
        fi
    done

    if [ "$plugin_count" -eq 0 ]; then
        echo "${YELLOW}未找到任何已安装的插件${NC}"
        return
    fi

    echo "${YELLOW}检测到 $plugin_count 个已安装的插件:${NC}"
    echo ""

    # 显示菜单
    show_uninstall_menu() {
        echo "${YELLOW}选择要卸载的插件:${NC}"
        echo "  输入编号切换选择, a=全选, n=取消全选, 回车=确认"
        echo ""
        i=1
        for plugin_name in $INSTALLED_PLUGINS; do
            eval "selected=\$UNSEL_$i"
            if [ "$selected" = "1" ]; then
                printf "  ${GREEN}[x]${NC} %2d) %s\n" "$i" "$plugin_name"
            else
                printf "  [ ] %2d) %s\n" "$i" "$plugin_name"
            fi
            i=$((i+1))
        done
        echo ""
    }

    # 初始化选择状态
    i=1
    for plugin_name in $INSTALLED_PLUGINS; do
        eval "UNSEL_$i=0"
        i=$((i+1))
    done

    # 交互循环
    while true; do
        show_uninstall_menu
        printf "请输入: "
        read -r choice

        if [ -z "$choice" ]; then break; fi

        if [ "$choice" = "a" ] || [ "$choice" = "A" ]; then
            i=1
            for plugin_name in $INSTALLED_PLUGINS; do
                eval "UNSEL_$i=1"
                i=$((i+1))
            done
            continue
        fi

        if [ "$choice" = "n" ] || [ "$choice" = "N" ]; then
            i=1
            for plugin_name in $INSTALLED_PLUGINS; do
                eval "UNSEL_$i=0"
                i=$((i+1))
            done
            continue
        fi

        if [ "$choice" -ge 1 ] 2>/dev/null && [ "$choice" -le $plugin_count ]; then
            eval "current=\$UNSEL_$choice"
            if [ "$current" = "1" ]; then
                eval "UNSEL_$choice=0"
            else
                eval "UNSEL_$choice=1"
            fi
        fi
    done

    # 卸载选中的插件
    echo ""
    uninstalled=0
    i=1
    for plugin_name in $INSTALLED_PLUGINS; do
        eval "selected=\$UNSEL_$i"
        if [ "$selected" = "1" ]; then
            plugin_path="$PLUGINS_DIR/$plugin_name"
            echo "${YELLOW}正在卸载 $plugin_name ...${NC}"
            if rm -rf "$plugin_path"; then
                echo "${GREEN}[OK] $plugin_name 卸载完成${NC}"
            else
                echo "${RED}[FAIL] $plugin_name 卸载失败${NC}"
            fi
            uninstalled=1
        fi
        i=$((i+1))
    done

    if [ "$uninstalled" = "1" ]; then
        echo ""
        echo "${GREEN}插件卸载完成${NC}"
    else
        echo "${YELLOW}未选择任何插件${NC}"
    fi
}

# =============================================================================
# 生成 .env 文件
# =============================================================================
generate_env_file() {
    echo "${YELLOW}生成 .env 文件...${NC}"

    if [ -f ".env" ]; then
        EXISTING_HTTP_PROXY=$(grep "^GSCORE_HTTP_PROXY=" .env 2>/dev/null | cut -d'=' -f2- | tr -d '"' | tr -d "'" || echo "")
        EXISTING_HTTPS_PROXY=$(grep "^GSCORE_HTTPS_PROXY=" .env 2>/dev/null | cut -d'=' -f2- | tr -d '"' | tr -d "'" || echo "")
        EXISTING_NO_PROXY=$(grep "^GSCORE_NO_PROXY=" .env 2>/dev/null | cut -d'=' -f2- | tr -d '"' | tr -d "'" || echo "")
    else
        EXISTING_HTTP_PROXY=""
        EXISTING_HTTPS_PROXY=""
        EXISTING_NO_PROXY=""
    fi

    FINAL_NO_PROXY="${EXISTING_NO_PROXY:-localhost,127.0.0.1,.local,cnb.cool,mirrors.aliyun.com,pypi.tuna.tsinghua.edu.cn,mirrors.volces.com}"

    cat > .env << EOF
# gsuid_core 环境配置

# 镜像配置（远程镜像模式使用）
GSCORE_IMAGE=${REMOTE_IMAGE:-docker.cnb.cool/gscore-mirror/gscore-docker:latest}

# 端口映射
PORT=${PORT}

# 挂载目录（默认: $(pwd)/gsuid_core）
MOUNT_PATH=${MOUNT_PATH}

# 代理配置（可选）
GSCORE_HTTP_PROXY=${EXISTING_HTTP_PROXY}
GSCORE_HTTPS_PROXY=${EXISTING_HTTPS_PROXY}
# 不走代理的域名列表（默认已配置常用镜像源）
GSCORE_NO_PROXY=${FINAL_NO_PROXY}
EOF
    echo "${GREEN}✓ .env 文件已生成${NC}"
}

# =============================================================================
# 生成 Dockerfile
# =============================================================================
generate_dockerfile() {
    if [ "$USE_LOCAL_BUILD" != "true" ]; then
        return
    fi

    echo "${YELLOW}生成 Dockerfile...${NC}"
    cat > Dockerfile << 'EOF'
# ========================================== 
# Stage 1: Base (最基础的系统环境)
# 包含：Python, 时区, 编译工具, Git, 空虚拟环境
# ========================================== 
FROM docker.cnb.cool/gscore-mirror/docker-sync/astral-uv:python3.12-bookworm-slim AS base

# 暴露端口
EXPOSE 8765

WORKDIR /gsuid_core

# 环境变量
ENV UV_PROJECT_ENVIRONMENT=/venv
ENV PATH="/venv/bin:$PATH"
ENV UV_LINK_MODE=copy

# 安装最基础的系统依赖 + 创建虚拟环境
RUN apt-get update && apt-get install -y \
    git \
    curl \
    gcc \
    python3-dev \
    build-essential \
    tzdata \
    && rm -rf /var/lib/apt/lists/* \
    && ln -snf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime \
    && echo Asia/Shanghai > /etc/timezone \
    && uv venv /venv --seed

# 配置 git safe.directory
RUN git config --global --add safe.directory '*'

# ========================================== 
# Stage 2: Lite (纯 Python 环境)
# Target: lite
# ========================================== 
FROM base AS lite

# 启动命令
CMD ["uv", "run", "--python", "/venv/bin/python", "core", "--host", "0.0.0.0"]

# ========================================== 
# Stage 3: Playwright (浏览器环境 - 默认)
# Target: playwright
# ========================================== 
FROM base AS playwright

# 设置浏览器全局路径
ENV PLAYWRIGHT_BROWSERS_PATH=/ms-playwright

# 安装 Playwright 运行所需的额外依赖 (中文字体 + 浏览器依赖)
RUN apt-get update && apt-get install -y \
    fonts-noto-cjk \
    libffi-dev \
    && rm -rf /var/lib/apt/lists/*

# 1. 安装 Playwright 库到 venv (venv 已在 base 阶段创建)
# 2. 下载 Chromium 及其依赖
RUN --mount=type=cache,target=/root/.cache/uv \
    uv pip install playwright && \
    playwright install --with-deps chromium && \
    rm -rf /var/lib/apt/lists/*

# 启动命令
CMD ["uv", "run", "--python", "/venv/bin/python", "core", "--host", "0.0.0.0"]
EOF
    echo "${GREEN}✓ Dockerfile 已生成${NC}"
}

# =============================================================================
# 生成 docker-compose.yaml
# =============================================================================
generate_compose_file() {
    echo "${YELLOW}生成 docker-compose.yaml 文件...${NC}"

    if [ "$UPDATE_COMPOSE" != "true" ]; then
        echo "${GREEN}✓ 跳过 docker-compose.yaml 生成 (保持现有配置)${NC}"
        return
    fi

    if [ "$USE_LOCAL_BUILD" = "true" ]; then
        cat > docker-compose.yaml << 'EOF'
# gsuid_core Docker Compose 配置
# 部署方式: 本地构建

services:
  gsuid_core:
    build:
      context: .
      dockerfile: Dockerfile
      target: playwright
    image: gscore:local
    container_name: gsuid_core
    ports:
      - "${PORT:-8765}:8765"
    volumes:
      - ${MOUNT_PATH:-./gsuid_core}:/gsuid_core
      - venv-data:/venv
    restart: unless-stopped
    extra_hosts:
      - "host.docker.internal:host-gateway"
    environment:
      - PYTHONUNBUFFERED=1
      - http_proxy=${GSCORE_HTTP_PROXY:-}
      - https_proxy=${GSCORE_HTTPS_PROXY:-}
      - no_proxy=${GSCORE_NO_PROXY:-localhost,127.0.0.1,.local,cnb.cool,mirrors.aliyun.com,pypi.tuna.tsinghua.edu.cn,mirrors.volces.com}

volumes:
  venv-data:
EOF
    else
        cat > docker-compose.yaml << 'EOF'
# gsuid_core Docker Compose 配置
# 部署方式: 远程镜像

services:
  gsuid_core:
    image: ${GSCORE_IMAGE:-docker.cnb.cool/gscore-mirror/gscore-docker:latest}
    container_name: gsuid_core
    ports:
      - "${PORT:-8765}:8765"
    volumes:
      - ${MOUNT_PATH:-./gsuid_core}:/gsuid_core
      - venv-data:/venv
    restart: unless-stopped
    extra_hosts:
      - "host.docker.internal:host-gateway"
    environment:
      - PYTHONUNBUFFERED=1
      - http_proxy=${GSCORE_HTTP_PROXY:-}
      - https_proxy=${GSCORE_HTTPS_PROXY:-}
      - no_proxy=${GSCORE_NO_PROXY:-localhost,127.0.0.1,.local,cnb.cool,mirrors.aliyun.com,pypi.tuna.tsinghua.edu.cn,mirrors.volces.com}

volumes:
  venv-data:
EOF
    fi
    echo "${GREEN}✓ docker-compose.yaml 文件已生成${NC}"
}

# =============================================================================
# 构建/拉取镜像
# =============================================================================
build_or_pull_image() {
    if [ "$AUTO_YES" = "true" ]; then
        echo "${YELLOW}正在拉取镜像...${NC}"
        if [ "$USE_LOCAL_BUILD" = "true" ]; then
            docker-compose build
        else
            docker-compose pull
        fi
        echo "${GREEN}✓ 镜像准备完成${NC}"
        return
    fi

    echo "${YELLOW}是否立即构建镜像? [Y/n]:${NC}"
    printf "请输入选择: "
    read -r build_now

    if [ "$build_now" = "n" ] || [ "$build_now" = "N" ]; then
        return
    fi

    echo ""
    echo "${YELLOW}正在构建镜像...${NC}"
    if [ "$USE_LOCAL_BUILD" = "true" ]; then
        docker-compose build
    else
        docker-compose pull
    fi
    echo "${GREEN}✓ 镜像准备完成${NC}"
}

# =============================================================================
# 显示完成信息
# =============================================================================
show_completion_info() {
    echo ""
    echo "${GREEN}================================================${NC}"
    echo "${GREEN}初始化完成！${NC}"
    echo "${GREEN}================================================${NC}"
    echo ""
    echo "配置文件: ${GREEN}docker-compose.yaml${NC}"
    echo ""
    echo "运行 ${GREEN}./setup.sh -h${NC} 查看常用命令"
    echo "运行 ${GREEN}docker-compose up -d${NC} 启动服务"
    echo ""
}

# =============================================================================
# 主流程
# =============================================================================
main() {
    # 解析参数
    case "${1:-}" in
        -h|--help)
            show_help
            ;;
        -y)
            AUTO_YES="true"
            ;;
        -i)
            # -i 模式：只安装插件，跳过其他配置
            PLUGIN_ONLY_MODE="true"
            init_colors
            echo "${BLUE}================================================${NC}"
            echo "${BLUE}gsuid_core 插件安装模式${NC}"
            echo "${BLUE}================================================${NC}"
            echo ""

            # 在插件模式下直接检测默认目录，不允许修改
            if [ -f ".env" ]; then
                ENV_MOUNT_PATH=$(grep "^MOUNT_PATH=" .env | cut -d'=' -f2- | tr -d '"' | tr -d "'")
                if [ -n "$ENV_MOUNT_PATH" ]; then
                    MOUNT_PATH="$ENV_MOUNT_PATH"
                else
                    MOUNT_PATH="$DEFAULT_MOUNT"
                fi
            else
                MOUNT_PATH="$DEFAULT_MOUNT"
            fi

            echo "${YELLOW}检测到挂载目录: $MOUNT_PATH${NC}"
            if [ ! -d "$MOUNT_PATH" ] || [ -z "$(ls -A "$MOUNT_PATH" 2>/dev/null)" ]; then
                echo "${RED}错误: 挂载目录不存在或为空: $MOUNT_PATH${NC}"
                echo ""
                echo "${YELLOW}请先运行完整安装:${NC}"
                echo "  ${GREEN}交互式安装:${NC}  ./setup.sh"
                echo "  ${GREEN}快速安装:${NC}    ./setup.sh -y"
                echo ""
                exit 1
            fi

            echo "${GREEN}✓ 目录验证通过${NC}"
            echo ""

            configure_git_safe_directory
            install_plugins
            echo ""
            echo "${GREEN}================================================${NC}"
            echo "${GREEN}插件安装完成！${NC}"
            echo "${GREEN}================================================${NC}"
            exit 0
            ;;
        -ui)
            # -ui 模式：只卸载插件，跳过其他配置
            PLUGIN_UNINSTALL_MODE="true"
            init_colors
            echo "${BLUE}================================================${NC}"
            echo "${BLUE}gsuid_core 插件卸载模式${NC}"
            echo "${BLUE}================================================${NC}"
            echo ""

            # 检测挂载目录
            if [ -f ".env" ]; then
                ENV_MOUNT_PATH=$(grep "^MOUNT_PATH=" .env | cut -d'=' -f2- | tr -d '"' | tr -d "'")
                if [ -n "$ENV_MOUNT_PATH" ]; then
                    MOUNT_PATH="$ENV_MOUNT_PATH"
                else
                    MOUNT_PATH="$DEFAULT_MOUNT"
                fi
            else
                MOUNT_PATH="$DEFAULT_MOUNT"
            fi

            echo "${YELLOW}检测到挂载目录: $MOUNT_PATH${NC}"
            if [ ! -d "$MOUNT_PATH" ] || [ -z "$(ls -A "$MOUNT_PATH" 2>/dev/null)" ]; then
                echo "${RED}错误: 挂载目录不存在或为空: $MOUNT_PATH${NC}"
                echo ""
                echo "${YELLOW}请先运行完整安装:${NC}"
                echo "  ${GREEN}交互式安装:${NC}  ./setup.sh"
                echo "  ${GREEN}快速安装:${NC}    ./setup.sh -y"
                echo ""
                exit 1
            fi

            echo "${GREEN}✓ 目录验证通过${NC}"
            echo ""

            configure_git_safe_directory
            uninstall_plugins
            echo ""
            echo "${GREEN}================================================${NC}"
            echo "${GREEN}插件卸载完成！${NC}"
            echo "${GREEN}================================================${NC}"
            exit 0
            ;;
    esac

    init_colors
    check_update

    echo "${BLUE}================================================${NC}"
    echo "${BLUE}gsuid_core Docker 环境初始化${NC}"
    echo "${BLUE}================================================${NC}"
    echo ""

    detect_existing_config
    select_deploy_mode
    echo ""
    configure_port
    echo ""
    configure_mount_path
    configure_git_safe_directory
    echo ""
    clone_source
    echo ""
    install_plugins
    echo ""
    generate_env_file
    configure_proxy
    echo ""
    generate_dockerfile
    generate_compose_file
    echo ""
    build_or_pull_image
    show_completion_info
}

# 执行主流程
main "$@"
