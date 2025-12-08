# gsuid_core Docker 部署

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

### # 运行初始化脚本
```bash
./setup.sh
```

## 生成的文件

| 文件 | 说明 |
|------|------|
| .env | 环境变量配置 (端口, 挂载目录) |
| docker-compose.yaml | Docker Compose 配置文件 |
| Dockerfile | Docker 镜像构建文件 (仅本地构建模式) |

## 常用命令

```bash
# 启动服务
docker-compose up -d

# 查看日志
docker-compose logs -f

# 停止服务
docker-compose down

# 重新构建并启动
docker-compose up -d --build

# 重新配置
./setup.sh
```

## 配置修改

直接编辑 .env 文件即可修改配置:

```env
# 端口映射
PORT=8765

# 挂载目录
MOUNT_PATH=/path/to/gsuid_core
```