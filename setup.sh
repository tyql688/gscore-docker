#!/bin/sh
# gsuid_core Docker 环境初始化脚本

set -e

# 颜色输出配置 (兼容 POSIX sh)
if [ -t 1 ]; then
    # 尝试使用 tput (如果可用)
    if command -v tput >/dev/null 2>&1; then
        RED=$(tput setaf 1)
        GREEN=$(tput setaf 2)
        YELLOW=$(tput setaf 3)
        BLUE=$(tput setaf 4)
        NC=$(tput sgr0)
    else
        # 回退到 ANSI 转义序列
        RED='\033[0;31m'
        GREEN='\033[0;32m'
        YELLOW='\033[1;33m'
        BLUE='\033[0;34m'
        NC='\033[0m'
    fi
else
    # 如果不是终端，禁用颜色
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    NC=''
fi

# 脚本版本
VERSION="1.1.0"
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

# 初始化变量
USE_LOCAL_BUILD=""
REMOTE_IMAGE=""
UPDATE_COMPOSE="true" # 默认生成/更新配置文件

# 检测现有的 docker-compose.yaml 配置
if [ -f "docker-compose.yaml" ]; then
    # 简单的文本匹配来猜测配置
    if grep -q "build:" docker-compose.yaml; then
        EXISTING_MODE="local"
        EXISTING_IMAGE_INFO="本地构建 (local build)"
    elif grep -q "image:" docker-compose.yaml; then
        EXISTING_MODE="remote"
        # 尝试提取镜像名
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
fi

# 选择部署方式 (如果未确定)
if [ -z "$USE_LOCAL_BUILD" ]; then
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
fi

echo ""

# 设置端口
PORT=""

# 尝试从 .env 读取 PORT
if [ -f ".env" ]; then
    ENV_PORT=$(grep "^PORT=" .env | cut -d'=' -f2- | tr -d '"' | tr -d "'")
    if [ -n "$ENV_PORT" ]; then
        echo "${YELLOW}检测到已配置端口: ${ENV_PORT}${NC}"
        printf "是否修改端口? [y/N]: "
        read -r change_port
        if [ "$change_port" != "y" ] && [ "$change_port" != "Y" ]; then
            PORT="$ENV_PORT"
            echo "${GREEN}✓ 保持使用端口: $PORT${NC}"
        fi
    fi
fi

# 如果没有从 .env 获取到 PORT，则进行询问
if [ -z "$PORT" ]; then
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
fi

echo ""

# 设置挂载目录
CURRENT_DIR="$(pwd)"
DEFAULT_MOUNT="${CURRENT_DIR}/gsuid_core"
MOUNT_PATH=""

# 尝试从 .env 读取 MOUNT_PATH
if [ -f ".env" ]; then
    # 读取 .env 中的 MOUNT_PATH，去除可能的引号和空白
    ENV_MOUNT_PATH=$(grep "^MOUNT_PATH=" .env | cut -d'=' -f2- | tr -d '"' | tr -d "'")
    if [ -n "$ENV_MOUNT_PATH" ]; then
        echo "${YELLOW}检测到已配置挂载目录: ${ENV_MOUNT_PATH}${NC}"
        printf "是否修改挂载目录? [y/N]: "
        read -r change_mount
        if [ "$change_mount" != "y" ] && [ "$change_mount" != "Y" ]; then
            MOUNT_PATH="$ENV_MOUNT_PATH"
            echo "${GREEN}✓ 保持使用: $MOUNT_PATH${NC}"
        fi
    fi
fi

# 如果没有从 .env 获取到 MOUNT_PATH，则进行询问
if [ -z "$MOUNT_PATH" ]; then
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
fi

# 配置 git safe.directory，防止 ownership 报错
# 添加挂载目录本身
if ! git config --global --get-all safe.directory | grep -q "^${MOUNT_PATH}$"; then
    echo "${YELLOW}添加 ${MOUNT_PATH} 到 git safe.directory...${NC}"
    git config --global --add safe.directory "${MOUNT_PATH}"
fi

# 添加 /gsuid_core/* 模式匹配所有直接子目录
SUBDIR_PATTERN="/gsuid_core/*"
if ! git config --global --get-all safe.directory | grep -q "^${SUBDIR_PATTERN}$"; then
    echo "${YELLOW}添加 ${SUBDIR_PATTERN} 到 git safe.directory...${NC}"
    git config --global --add safe.directory "${SUBDIR_PATTERN}"
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

            # 检查安装状态
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

# 配置代理设置
configure_proxy() {
    # 初始化变量
    DELETE_PROXY="false"

    # 尝试从 .env 读取代理配置
    ENV_http_proxy=$(grep "^http_proxy=" .env 2>/dev/null | cut -d'=' -f2- | tr -d '"' | tr -d "'" || echo "")
    ENV_https_proxy=$(grep "^https_proxy=" .env 2>/dev/null | cut -d'=' -f2- | tr -d '"' | tr -d "'" || echo "")
    ENV_no_proxy=$(grep "^no_proxy=" .env 2>/dev/null | cut -d'=' -f2- | tr -d '"' | tr -d "'" || echo "")

    if [ -n "$ENV_http_proxy" ] || [ -n "$ENV_https_proxy" ]; then
        # 已配置代理
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
                    # 只有在用户明确选择修改代理时，才设置默认 no_proxy
                    if [ -z "$ENV_no_proxy" ]; then
                        ENV_no_proxy="localhost,127.0.0.1,.local,cnb.cool"
                    fi
                    ;;
                2)
                    # 删除代理配置（保留 no_proxy）
                    DELETE_PROXY="true"
                    ;;
                *)
                    echo "${YELLOW}保持当前代理配置${NC}"
                    ;;
            esac
        fi
    else
        # 未配置代理
        echo "${YELLOW}是否需要配置代理? [y/N]:${NC}"
        printf "请输入选择: "
        read -r setup_proxy

        if [ "$setup_proxy" = "y" ] || [ "$setup_proxy" = "Y" ]; then
            printf "请输入代理端口 (默认 7890): "
            read -r proxy_port
            proxy_port=${proxy_port:-7890}
            ENV_http_proxy="http://host.docker.internal:$proxy_port"
            ENV_https_proxy="http://host.docker.internal:$proxy_port"
            # 首次配置代理时，如果 no_proxy 为空才设置默认值
            if [ -z "$ENV_no_proxy" ]; then
                ENV_no_proxy="localhost,127.0.0.1,.local,cnb.cool"
            fi
        fi
    fi

    # 更新 .env 文件中的代理配置
    if [ "$DELETE_PROXY" = "true" ]; then
        # 删除代理配置（保留 no_proxy）
        sed -i.bak '/^http_proxy=/d' .env 2>/dev/null || true
        sed -i.bak '/^https_proxy=/d' .env 2>/dev/null || true
        # 保留 no_proxy 行，不修改
    else
        # 正常更新代理配置
        if [ -n "$ENV_http_proxy" ]; then
            if grep -q "^http_proxy=" .env 2>/dev/null; then
                sed -i.bak "s|^http_proxy=.*|http_proxy=$ENV_http_proxy|" .env 2>/dev/null || true
            else
                echo "http_proxy=$ENV_http_proxy" >> .env 2>/dev/null || true
            fi
        fi

        if [ -n "$ENV_https_proxy" ]; then
            if grep -q "^https_proxy=" .env 2>/dev/null; then
                sed -i.bak "s|^https_proxy=.*|https_proxy=$ENV_https_proxy|" .env 2>/dev/null || true
            else
                echo "https_proxy=$ENV_https_proxy" >> .env 2>/dev/null || true
            fi
        fi

        # 只有在明确设置了 no_proxy 时才更新（保留用户修改）
        if [ -n "$ENV_no_proxy" ]; then
            if grep -q "^no_proxy=" .env 2>/dev/null; then
                sed -i.bak "s|^no_proxy=.*|no_proxy=$ENV_no_proxy|" .env 2>/dev/null || true
            else
                echo "no_proxy=$ENV_no_proxy" >> .env 2>/dev/null || true
            fi
        fi
    fi

    # 清理临时文件
    rm -f .env.bak 2>/dev/null || true

    # 显示当前代理配置
    if [ "$DELETE_PROXY" = "true" ]; then
        echo "${GREEN}✓ 代理配置已删除${NC}"
        [ -n "$ENV_no_proxy" ] && echo "  no_proxy: $ENV_no_proxy (已保留)"
    elif [ -n "$ENV_http_proxy" ] || [ -n "$ENV_https_proxy" ]; then
        echo "${GREEN}✓ 代理配置已更新${NC}"
        [ -n "$ENV_http_proxy" ] && echo "  http_proxy: $ENV_http_proxy"
        [ -n "$ENV_https_proxy" ] && echo "  https_proxy: $ENV_https_proxy"
        [ -n "$ENV_no_proxy" ] && echo "  no_proxy: $ENV_no_proxy"
    else
        echo "${GREEN}✓ 未配置代理${NC}"
        [ -n "$ENV_no_proxy" ] && echo "  no_proxy: $ENV_no_proxy"
    fi
}

# 生成或更新 .env 文件（保留现有代理配置）
echo "${YELLOW}生成 .env 文件...${NC}"

# 如果 .env 存在，先读取现有代理配置
if [ -f ".env" ]; then
    # 保留现有的代理配置
    EXISTING_HTTP_PROXY=$(grep "^http_proxy=" .env 2>/dev/null | cut -d'=' -f2- | tr -d '"' | tr -d "'" || echo "")
    EXISTING_HTTPS_PROXY=$(grep "^https_proxy=" .env 2>/dev/null | cut -d'=' -f2- | tr -d '"' | tr -d "'" || echo "")
    EXISTING_NO_PROXY=$(grep "^no_proxy=" .env 2>/dev/null | cut -d'=' -f2- | tr -d '"' | tr -d "'" || echo "")
else
    # 新文件，使用默认值
    EXISTING_HTTP_PROXY=""
    EXISTING_HTTPS_PROXY=""
    EXISTING_NO_PROXY=""
fi

# 只有在 no_proxy 为空时才设置为默认值（保留用户修改）
FINAL_NO_PROXY="${EXISTING_NO_PROXY:-localhost,127.0.0.1,.local,cnb.cool}"

# 生成 .env 文件（保留代理配置）
cat > .env << EOF
# gsuid_core 环境配置

# 端口映射
PORT=${PORT}

# 挂载目录
MOUNT_PATH=${MOUNT_PATH}

# 代理配置（可选）
http_proxy=${EXISTING_HTTP_PROXY}
https_proxy=${EXISTING_HTTPS_PROXY}
no_proxy=${FINAL_NO_PROXY}
EOF
echo "${GREEN}✓ .env 文件已生成${NC}"

# 调用代理配置
configure_proxy

echo ""

# 生成配置文件
if [ "$USE_LOCAL_BUILD" = "true" ]; then
    echo "${YELLOW}生成 Dockerfile...${NC}"
    cat > Dockerfile << 'EOF'
# 基于 astral/uv 的 Python 3.12 Bookworm-slim 镜像
FROM astral/uv:python3.12-bookworm-slim

# 设置工作目录
WORKDIR /gsuid_core

# 暴露 8765 端口
EXPOSE 8765

# 安装系统依赖（包括编译工具和时区数据）
RUN apt-get update && apt-get install -y \
    git \
    curl \
    gcc \
    python3-dev \
    build-essential \
    tzdata && \
    rm -rf /var/lib/apt/lists/* && \
    ln -snf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && echo Asia/Shanghai > /etc/timezone

# 配置 git safe.directory，防止容器内 ownership 报错
# 添加 /gsuid_core 根目录及其所有直接子目录
RUN git config --global --add safe.directory '/gsuid_core' && \
    git config --global --add safe.directory '/gsuid_core/*' && \
    git config --global --add safe.directory '/venv'

# 在镜像层创建 venv（/venv 不会被挂载覆盖）
RUN uv venv --seed /venv

# 告诉 uv 永远用它
ENV UV_PROJECT_ENVIRONMENT=/venv

# 设置 PATH，优先从 /venv/bin 查找可执行文件
ENV PATH="/venv/bin:$PATH"

# 启用绑定挂载缓存
ENV UV_LINK_MODE=copy

# 启动命令
CMD ["uv", "run", "--python", "/venv/bin/python", "core", "--host", "0.0.0.0"]
EOF
    echo "${GREEN}✓ Dockerfile 已生成${NC}"
fi

echo "${YELLOW}生成 docker-compose.yaml 文件...${NC}"

# 生成 docker-compose.yaml 文件 (如果需要更新)
if [ "$UPDATE_COMPOSE" = "true" ]; then
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
      - ${MOUNT_PATH}:/gsuid_core
      - venv-data:/venv
    restart: unless-stopped
    extra_hosts:
      - "host.docker.internal:host-gateway"
    environment:
      - PYTHONUNBUFFERED=1
      - http_proxy=${http_proxy:-}
      - https_proxy=${https_proxy:-}
      - no_proxy=${no_proxy:-localhost,127.0.0.1,.local,cnb.cool}

volumes:
  venv-data:
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
      - \${MOUNT_PATH}:/gsuid_core
      - venv-data:/venv
    restart: unless-stopped
    extra_hosts:
      - "host.docker.internal:host-gateway"
    environment:
      - PYTHONUNBUFFERED=1
      - http_proxy=\${http_proxy:-}
      - https_proxy=\${https_proxy:-}
      - no_proxy=\${no_proxy:-localhost,127.0.0.1,.local,cnb.cool}

volumes:
  venv-data:
EOF
    fi
    echo "${GREEN}✓ docker-compose.yaml 文件已生成${NC}"
else
    echo "${GREEN}✓ 跳过 docker-compose.yaml 生成 (保持现有配置)${NC}"
fi
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
echo "${YELLOW}常用命令:${NC}"
echo ""
echo "  ${GREEN}启动服务:${NC}"
echo "    docker-compose up -d"
echo ""
echo "  ${GREEN}查看日志:${NC}"
echo "    docker-compose logs -f"
echo ""
echo "  ${GREEN}重启服务:${NC}"
echo "    docker-compose restart"
echo ""
echo "  ${GREEN}重新构建并启动:${NC}"
echo "    docker-compose up -d --build"
echo ""
echo "  ${GREEN}停止服务:${NC}"
echo "    docker-compose down"
echo ""
echo "  ${GREEN}停止并删除虚拟环境数据:${NC}"
echo "    docker-compose down --volumes"
echo ""
echo "  ${GREEN}进入容器 shell:${NC}"
echo "    docker exec -it gsuid_core sh"
echo ""
echo "  ${GREEN}安装 Python 包 (示例: tqdm):${NC}"
echo "    docker exec -it gsuid_core sh -c 'uv pip install tqdm'"
echo ""
echo "  ${GREEN}测试代理连接:${NC}"
echo "    docker exec -it gsuid_core sh -c 'curl https://api.ipify.org?format=json'"
echo ""
echo "  ${GREEN}查看状态:${NC}"
echo "    docker-compose ps"
echo ""
echo "  ${GREEN}查看资源使用:${NC}"
echo "    docker stats gsuid_core"
echo ""
echo "  ${GREEN}重新配置:${NC}"
echo "    ./setup.sh"
echo ""
