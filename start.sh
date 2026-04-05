#!/bin/bash
# OpenClaw 备份系统启动脚本

LOG_FILE="/home/hhxs/backups/backup.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log "启动 OpenClaw 备份系统..."

# 启动 API 服务 (Flask)
if pgrep -f "python3.*server/app.py" > /dev/null; then
    log "API 服务已在运行"
else
    cd /home/hhxs/backup-system/server
    nohup python3 app.py > /dev/null 2>&1 &
    log "API 服务已启动 (PID: $!)"
fi

sleep 2

# 启动 Web 服务 (静态HTML)
if pgrep -f "python3.*http.server.*3000" > /dev/null; then
    log "Web 服务已在运行"
else
    cd /home/hhxs/backup-system/web
    nohup python3 -m http.server 3000 > /dev/null 2>&1 &
    log "Web 服务已启动 (端口 3000)"
fi

log "启动完成"
log "API: http://localhost:5000"
log "Web: http://localhost:3000"
