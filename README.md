# gsuid_core Docker 快速部署

## 快速开始

### 下载脚本 wget

```bash
wget https://cnb.cool/gscore-mirror/gscore-docker/-/git/raw/main/setup.sh
```

### 下载脚本 curl

```bash
curl -LsSf https://cnb.cool/gscore-mirror/gscore-docker/-/git/raw/main/setup.sh -o setup.sh
```

### 赋予执行权限

```bash
chmod +x setup.sh
```

### 运行初始化脚本

```bash
# 交互式配置向导
./setup.sh

# 使用默认配置快速安装（推荐）
./setup.sh -y

# 仅交互式安装插件
./setup.sh -i

# 仅交互式卸载插件
./setup.sh -ui

# 显示帮助信息
./setup.sh -h
```

## 默认配置 (-y 模式)

- **Docker 镜像源**: CNB 加速
- **端口**: 8765
- **挂载目录**: `./gsuid_core`
- **源码源**: CNB 加速
- **插件**: 不安装
- **代理**: 不配置

## 生成的文件

| 文件                | 说明                                    |
| ------------------- | --------------------------------------- |
| .env                | 环境变量配置 (端口, 挂载目录, 代理配置) |
| docker-compose.yaml | Docker Compose 配置文件                 |
| Dockerfile          | Docker 镜像构建文件 (仅本地构建模式)    |
