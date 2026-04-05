#!/bin/bash
# OpenClaw 自动备份脚本 (重构版)
# 
# 备份结构：
# 1. OpenClaw 数据 → openclaw-backup 仓库
# 2. 备份系统代码 → backup_system 仓库

DATA_REPO="$HOME/openclaw-backup-data"
SYSTEM_REPO="$HOME/backup-system"
SHARED_BACKUP_DIR="$HOME/backups"
LOG_FILE="$HOME/backups/backup.log"
MAX_RETRIES=3
RETRY_DELAY=10

mkdir -p "$SHARED_BACKUP_DIR"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# 带重试的 git push
git_push_with_retry() {
    local repo_path="$1"
    local remote="$2"
    local branch="$3"
    local retries=0
    
    cd "$repo_path"
    while [ $retries -lt $MAX_RETRIES ]; do
        git push "$remote" "$branch" 2>&1 | tee -a "$LOG_FILE"
        local exit_code=${PIPESTATUS[0]}
        if [ $exit_code -eq 0 ]; then
            return 0
        fi
        retries=$((retries + 1))
        if [ $retries -lt $MAX_RETRIES ]; then
            log "推送失败，${RETRY_DELAY}秒后重试（第${retries}次）..."
            sleep $RETRY_DELAY
            RETRY_DELAY=$((RETRY_DELAY * 2))  # 指数退避
        fi
    done
    log "推送失败，已重试${MAX_RETRIES}次"
    return 1
}

# 备份 OpenClaw 数据
backup_openclaw_data() {
    local backup_filename="backup-$(date '+%Y-%m-%d').tar.gz"
    local backup_path="$SHARED_BACKUP_DIR/$backup_filename"
    local temp_backup_dir="$SHARED_BACKUP_DIR/.backup_temp_$$"
    
    log "========== 备份 OpenClaw 数据 =========="
    log "开始创建备份: $backup_filename"
    
    # 创建临时目录用于构建脱敏后的备份
    mkdir -p "$temp_backup_dir"
    
    # 复制 openclaw 目录（排除敏感缓存）
    cp -r "$HOME/.openclaw" "$temp_backup_dir/.openclaw" 2>/dev/null || {
        log "错误: OpenClaw 数据复制失败"
        rm -rf "$temp_backup_dir"
        return 1
    }
    
    # 脱敏 openclaw.json 及其同级备份文件
    log "脱敏 openclaw.json 及备份文件..."
    python3 -c "
import json, os, glob

openclaw_dir = '$temp_backup_dir/.openclaw'

def redact_value(v):
    if isinstance(v, str) and len(v) > 8:
        return 'REDACTED_' + v[:8] + '...'
    return v

def redact_json_obj(obj):
    if isinstance(obj, dict):
        for k, v in obj.items():
            if k in ('apiKey', 'token', 'secret', 'password') and isinstance(v, str) and len(v) > 4:
                obj[k] = redact_value(v)
            elif k == 'credentials' and isinstance(v, dict):
                for ck in v:
                    if ck not in ('provider', 'mode', 'type'):
                        v[ck] = 'REDACTED'
            elif isinstance(v, (dict, list)):
                redact_json_obj(v)
    elif isinstance(obj, list):
        for item in obj:
            if isinstance(item, (dict, list)):
                redact_json_obj(item)

# 精确匹配 openclaw.json 和它的备份/bak 文件（仅限顶层目录）
target_patterns = ['openclaw.json', 'openclaw.json.backup*', 'openclaw.json.bak*']
for pattern in target_patterns:
    for json_file in glob.glob(os.path.join(openclaw_dir, pattern)):
        if os.path.isfile(json_file):
            try:
                with open(json_file, 'r', encoding='utf-8') as f:
                    data = json.load(f)
                redact_json_obj(data)
                with open(json_file, 'w', encoding='utf-8') as f:
                    json.dump(data, f, ensure_ascii=False, indent=2)
                print(f'Redacted: {os.path.basename(json_file)}')
            except Exception as e:
                print(f'Skip {json_file}: {e}')

print('Redaction done')
" 2>&1 | tee -a "$LOG_FILE"
    
    # 打包
    tar -czf "$backup_path" -C "$temp_backup_dir" \
        --exclude='.openclaw/workspace/node_modules' \
        --exclude='.openclaw/workspace/.git' \
        --exclude='.openclaw/workspace/venv' \
        --exclude='.openclaw/workspace/.next' \
        --exclude='.openclaw/workspace/custom_memory/.git' \
        .openclaw 2>/dev/null
    
    # 清理临时目录
    rm -rf "$temp_backup_dir"
    
    if [ ! -f "$backup_path" ]; then
        log "错误: OpenClaw 数据备份创建失败"
        return 1
    fi
    
    local size=$(du -h "$backup_path" | cut -f1)
    log "OpenClaw 数据备份成功: $backup_filename (大小: $size)，已脱敏敏感信息"
}

# 备份系统代码
backup_system_code() {
    local backup_filename="backup_system-$(date '+%Y-%m-%d').tar.gz"
    local backup_path="$SHARED_BACKUP_DIR/$backup_filename"
    
    log "========== 备份系统代码 =========="
    log "开始创建备份: $backup_filename"
    
    tar -czf "$backup_path" -C "$HOME" \
        --exclude='backup-system/*.tar.gz' \
        --exclude='backup-system/.git' \
        --exclude='backup-system/web/node_modules' \
        --exclude='backup-system/web/.next' \
        --exclude='backup-system/venv' \
        backup-system 2>/dev/null || {
        log "错误: 系统代码备份创建失败"
        return 1
    }
    
    local size=$(du -h "$backup_path" | cut -f1)
    log "系统代码备份成功: $backup_filename (大小: $size)"
}

# 推送数据备份到 openclaw-backup 仓库
push_data_backup() {
    log "========== 推送数据备份到 GitHub =========="
    
    local backup_filename="backup-$(date '+%Y-%m-%d').tar.gz"
    local backup_path="$SHARED_BACKUP_DIR/$backup_filename"
    
    if [ ! -f "$backup_path" ]; then
        log "错误: 备份文件不存在 $backup_path"
        return 1
    fi
    
    # 复制到 data repo
    cp "$backup_path" "$DATA_REPO/"
    
    cd "$DATA_REPO"
    git add "$backup_filename"
    
    if git diff --cached --quiet; then
        log "OpenClaw 数据没有新的备份文件需要推送"
    else
        git commit -m "Backup $(date '+%Y-%m-%d %H:%M:%S')" 2>/dev/null
        if git_push_with_retry "$DATA_REPO" "origin" "master"; then
            log "OpenClaw 数据 GitHub 推送成功"
            # 更新 API 的 last_push.json（供 Web UI 显示）
            echo "{\"last_push\": \"$(date '+%Y-%m-%d %H:%M:%S')\", \"timestamp\": $(date +%s)}" > "$SYSTEM_REPO/last_push.json"
        else
            log "错误: OpenClaw 数据 GitHub 推送失败"
            return 1
        fi
    fi
}

# 推送系统代码备份到 backup_system 仓库
push_system_backup() {
    log "========== 推送系统代码备份到 GitHub =========="
    
    local backup_filename="backup_system-$(date '+%Y-%m-%d').tar.gz"
    local backup_path="$SHARED_BACKUP_DIR/$backup_filename"
    
    if [ ! -f "$backup_path" ]; then
        log "错误: 备份文件不存在 $backup_path"
        return 1
    fi
    
    # 复制到 system repo
    cp "$backup_path" "$SYSTEM_REPO/"
    
    cd "$SYSTEM_REPO"
    git add "$backup_filename"
    
    if git diff --cached --quiet; then
        log "系统代码没有新的备份文件需要推送"
    else
        git commit -m "System Backup $(date '+%Y-%m-%d %H:%M:%S')" 2>/dev/null
        if git_push_with_retry "$SYSTEM_REPO" "origin" "master"; then
            log "系统代码 GitHub 推送成功"
            # 更新 last_push.json（供 Web UI 显示）
            echo "{\"last_push\": \"$(date '+%Y-%m-%d %H:%M:%S')\", \"timestamp\": $(date +%s)}" > "$SYSTEM_REPO/last_push.json"
        else
            log "错误: 系统代码 GitHub 推送失败"
            return 1
        fi
    fi
}

# 清理旧备份
cleanup_old() {
    log "========== 清理旧备份 =========="
    log "正在清理超过 3 天的本地备份..."
    find "$SHARED_BACKUP_DIR" -name "backup-*.tar.gz" -mtime +3 -delete 2>/dev/null || true
    find "$SHARED_BACKUP_DIR" -name "backup_system-*.tar.gz" -mtime +3 -delete 2>/dev/null || true
    log "本地清理完成"
}

# 清理 GitHub 仓库中超过 7 天的备份文件
cleanup_github_old() {
    log "========== 清理 GitHub 仓库中超过 7 天的备份 =========="
    
    # 清理 openclaw-backup-data 仓库
    if [ -d "$DATA_REPO" ]; then
        cd "$DATA_REPO"
        # 找出 7 天前的备份文件并从 git 删除
        for old_file in $(find . -name "backup-*.tar.gz" -mtime +7 2>/dev/null); do
            git rm -f "$old_file" 2>/dev/null && log "已从 GitHub 删除: $old_file"
        done
        if git diff --cached --quiet; then
            log "openclaw-backup-data 没有需要清理的旧备份"
        else
            git commit -m "Cleanup old backups $(date '+%Y-%m-%d')" 2>/dev/null
            git_push_with_retry "$DATA_REPO" "origin" "master" || log "清理旧备份推送失败"
            log "openclaw-backup-data 清理完成"
        fi
    fi
    
    # 清理 backup_system 仓库
    if [ -d "$SYSTEM_REPO" ]; then
        cd "$SYSTEM_REPO"
        for old_file in $(find . -name "backup_system-*.tar.gz" -mtime +7 2>/dev/null); do
            git rm -f "$old_file" 2>/dev/null && log "已从 GitHub 删除: $old_file"
        done
        if git diff --cached --quiet; then
            log "backup_system 没有需要清理的旧备份"
        else
            git commit -m "Cleanup old system backups $(date '+%Y-%m-%d')" 2>/dev/null
            git_push_with_retry "$SYSTEM_REPO" "origin" "master" || log "清理旧备份推送失败"
            log "backup_system 清理完成"
        fi
    fi
    
    log "GitHub 仓库清理完成"
}

main() {
    log "=========================================="
    log "        开始备份任务"
    log "=========================================="
    
    backup_openclaw_data
    backup_system_code
    push_data_backup
    push_system_backup
    cleanup_old
    cleanup_github_old
    
    log "=========================================="
    log "        备份任务完成"
    log "=========================================="
}

main "$@"
