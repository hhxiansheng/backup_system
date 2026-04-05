#!/bin/bash
# OpenClaw 恢复脚本
# Author: DevOps Engineer (AI Assistant)

set -e

# 配置
BACKUP_DIR="$HOME/openclaw-backup/backups"
OPENCLAW_DIR="$HOME/.openclaw"
LOG_FILE="$HOME/openclaw-backup/backup.log"
TEMP_BACKUP="pre-restore-$(date '+%Y-%m-%d-%H%M%S').tar.gz"

# 日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# 检查 OpenClaw 是否在运行
is_openclaw_running() {
    pgrep -f "openclaw" > /dev/null 2>&1
    return $?
}

# 停止 OpenClaw
stop_openclaw() {
    log "正在停止 OpenClaw 服务..."
    openclaw gateway stop 2>/dev/null || pkill -f "openclaw" || true
    sleep 3
    log "OpenClaw 已停止"
}

# 启动 OpenClaw
start_openclaw() {
    log "正在启动 OpenClaw 服务..."
    (openclaw gateway start &) 2>/dev/null || true
    sleep 3
    log "OpenClaw 已启动"
}

# 创建临时备份
create_temp_backup() {
    if [ -d "$OPENCLAW_DIR" ]; then
        log "正在创建恢复前的临时备份: $TEMP_BACKUP"
        tar -czf "$BACKUP_DIR/$TEMP_BACKUP" -C "$HOME" .openclaw 2>/dev/null || {
            log "警告: 无法创建临时备份，继续恢复..."
        }
        log "临时备份创建完成"
    fi
}

# 获取备份文件路径
get_backup_path() {
    local filename="$1"
    
    if [ "$filename" = "latest" ]; then
        # 找到最新的备份
        local latest=$(ls -t "$BACKUP_DIR"/backup-*.tar.gz 2>/dev/null | head -1)
        if [ -z "$latest" ]; then
            echo ""
        else
            echo "$latest"
        fi
    else
        # 指定文件名
        local path="$BACKUP_DIR/$filename"
        if [ -f "$path" ]; then
            echo "$path"
        else
            echo ""
        fi
    fi
}

# 恢复备份
restore_backup() {
    local backup_path="$1"
    local backup_name=$(basename "$backup_path")
    
    log "========== 开始恢复备份 =========="
    log "恢复文件: $backup_name"
    
    # 创建临时备份
    create_temp_backup
    
    # 停止 OpenClaw
    stop_openclaw
    
    # 备份现有数据
    if [ -d "$OPENCLAW_DIR" ]; then
        log "备份现有配置..."
        mv "$OPENCLAW_DIR" "$HOME/.openclaw.bak.$(date +%s)" 2>/dev/null || true
    fi
    
    # 解压恢复
    log "正在解压恢复..."
    mkdir -p "$OPENCLAW_DIR"
    tar -xzf "$backup_path" -C "$HOME" 2>/dev/null || {
        log "错误: 解压失败"
        log "尝试从备份目录恢复..."
        tar -xzf "$backup_path" -C "$BACKUP_DIR" 2>/dev/null || {
            log "错误: 恢复失败，请检查备份文件"
            exit 1
        }
    }
    
    # 重启 OpenClaw
    start_openclaw
    
    log "========== 恢复完成 =========="
    log "恢复的备份: $backup_name"
    log "如果恢复有问题，临时备份在: $BACKUP_DIR/$TEMP_BACKUP"
}

# 显示用法
usage() {
    echo "用法: $0 [latest|backup-YYYY-MM-DD.tar.gz]"
    echo ""
    echo "示例:"
    echo "  $0 latest                     # 恢复最新备份"
    echo "  $0 backup-2026-03-27.tar.gz  # 恢复指定备份"
    echo ""
    echo "可用备份:"
    ls -1 "$BACKUP_DIR"/backup-*.tar.gz 2>/dev/null || echo "  无备份文件"
}

# 主函数
main() {
    local arg="$1"
    
    # 检查参数
    if [ -z "$arg" ]; then
        usage
        exit 1
    fi
    
    # 获取备份路径
    local backup_path=$(get_backup_path "$arg")
    
    if [ -z "$backup_path" ]; then
        log "错误: 找不到备份文件: $arg"
        echo ""
        echo "可用备份:"
        ls -1 "$BACKUP_DIR"/backup-*.tar.gz 2>/dev/null || echo "  无备份文件"
        exit 1
    fi
    
    # 执行恢复
    restore_backup "$backup_path"
}

# 执行
main "$@"
