#!/bin/bash
# OpenClaw 清理脚本
# 清理旧备份文件

set -e

# 配置
BACKUP_DIR="$HOME/openclaw-backup/backups"
LOG_FILE="$HOME/openclaw-backup/backup.log"
RETENTION_DAYS=3

# 日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# 清理函数
cleanup() {
    log "========== 开始清理任务 =========="
    log "保留最近 $RETENTION_DAYS 天的备份"
    
    # 本地清理
    local deleted_count=0
    while IFS= read -r file; do
        rm -f "$file"
        log "已删除本地备份: $(basename "$file")"
        ((deleted_count++))
    done < <(find "$BACKUP_DIR" -name "backup-*.tar.gz" -mtime +$RETENTION_DAYS 2>/dev/null)
    
    if [ $deleted_count -eq 0 ]; then
        log "没有需要清理的本地备份"
    else
        log "已清理 $deleted_count 个本地旧备份"
    fi
    
    log "========== 清理任务完成 =========="
}

# 执行
cleanup
