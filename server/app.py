#!/usr/bin/env python3
"""
OpenClaw 备份系统 - Flask API 服务
Author: DevOps Engineer (AI Assistant)
"""

import os
import sys
import subprocess
import json
from datetime import datetime
from flask import Flask, request, jsonify, send_file
from flask_cors import CORS

app = Flask(__name__)
CORS(app)

# 配置
BACKUP_DIR = os.path.expanduser("~/backups")
SCRIPTS_DIR = os.path.expanduser("~/backup-system/scripts")
LOG_FILE = os.path.expanduser("~/backups/backup.log")
OPENCLAW_DIR = os.path.expanduser("~/.openclaw")
LAST_PUSH_FILE = os.path.expanduser("~/backup-system/last_push.json")

def log(msg):
    """写入日志"""
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    with open(LOG_FILE, "a") as f:
        f.write(f"[{timestamp}] {msg}\n")

def save_last_push_time():
    """保存最后一次推送时间"""
    push_info = {
        "last_push": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "timestamp": datetime.now().timestamp()
    }
    with open(LAST_PUSH_FILE, "w") as f:
        json.dump(push_info, f, ensure_ascii=False, indent=2)

def get_last_push_time():
    """获取最后一次推送时间"""
    if os.path.exists(LAST_PUSH_FILE):
        try:
            with open(LAST_PUSH_FILE, "r") as f:
                data = json.load(f)
                return data.get("last_push")
        except:
            pass
    return None

def get_backup_list():
    """获取备份列表"""
    if not os.path.exists(BACKUP_DIR):
        return []
    
    backups = []
    for f in os.listdir(BACKUP_DIR):
        if (f.startswith("backup-") or f.startswith("backup_")) and f.endswith(".tar.gz"):
            path = os.path.join(BACKUP_DIR, f)
            stat = os.stat(path)
            backups.append({
                "name": f,
                "path": path,
                "size": stat.st_size,
                "size_human": get_size_human(stat.st_size),
                "modified": datetime.fromtimestamp(stat.st_mtime).strftime("%Y-%m-%d %H:%M:%S")
            })
    
    # 按修改时间排序，最新的在前
    backups.sort(key=lambda x: x["modified"], reverse=True)
    return backups

def get_size_human(size):
    """获取人类可读的文件大小"""
    for unit in ['B', 'KB', 'MB', 'GB']:
        if size < 1024.0:
            return f"{size:.1f} {unit}"
        size /= 1024.0
    return f"{size:.1f} TB"

def run_script(script_name, *args):
    """运行脚本"""
    script_path = os.path.join(SCRIPTS_DIR, script_name)
    cmd = [script_path] + list(args)
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=600)
        return result.returncode, result.stdout, result.stderr
    except subprocess.TimeoutExpired:
        return 1, "", "脚本执行超时"
    except Exception as e:
        return 1, "", str(e)

def get_system_status():
    """获取系统状态"""
    status = {
        "openclaw": {
            "running": False,
            "message": "未运行"
        },
        "gateway": {
            "running": False,
            "message": "未连接"
        },
        "github": {
            "connected": False,
            "message": "未连接",
            "last_sync": None
        },
        "cron": {
            "enabled": False,
            "schedule": "未设置",
            "next_run": None
        },
        "backup_dir": {
            "exists": os.path.exists(BACKUP_DIR),
            "path": BACKUP_DIR
        },
        "openclaw_dir": {
            "exists": os.path.exists(OPENCLAW_DIR),
            "path": OPENCLAW_DIR
        }
    }
    
    # 检查 OpenClaw 是否运行
    try:
        result = subprocess.run(["pgrep", "-f", "openclaw"], capture_output=True)
        status["openclaw"]["running"] = result.returncode == 0
        status["openclaw"]["message"] = "运行中" if result.returncode == 0 else "未运行"
    except:
        pass
    
    # 检查 OpenClaw Gateway 是否运行
    try:
        result = subprocess.run(["pgrep", "-f", "openclaw.*gateway"], capture_output=True)
        status["gateway"]["running"] = result.returncode == 0
        status["gateway"]["message"] = "正常" if result.returncode == 0 else "未连接"
    except:
        pass
    
    # 检查 GitHub 连接状态
    try:
        repo_dir = os.path.expanduser("~/backup-system")
        result = subprocess.run(["git", "-C", repo_dir, "status"], capture_output=True, text=True)
        if result.returncode == 0:
            status["github"]["connected"] = True
            status["github"]["message"] = "正常"
            # 获取最后一次推送时间（从记录文件读取）
            last_push = get_last_push_time()
            if last_push:
                status["github"]["last_sync"] = last_push
        else:
            status["github"]["message"] = "失败"
    except:
        status["github"]["message"] = "失败"
    
    # 检查定时备份设置
    try:
        result = subprocess.run(["crontab", "-l"], capture_output=True, text=True)
        if result.returncode == 0 and "backup.sh" in result.stdout:
            status["cron"]["enabled"] = True
            # 解析 cron 时间
            for line in result.stdout.split('\n'):
                if 'backup.sh' in line and not line.strip().startswith('#'):
                    parts = line.split()
                    if len(parts) >= 5:
                        minute, hour = parts[0], parts[1]
                        status["cron"]["schedule"] = f"每天 {hour}:{minute.zfill(2)}"
                    break
    except:
        pass
    
    return status

@app.route("/")
def index():
    return jsonify({
        "service": "OpenClaw Backup API",
        "version": "1.0.0",
        "endpoints": [
            "GET /api/backups - 获取备份列表",
            "POST /api/backup - 执行备份",
            "POST /api/restore - 恢复备份",
            "DELETE /api/backup - 删除备份",
            "GET /api/logs - 获取日志",
            "GET /api/status - 系统状态"
        ]
    })

@app.route("/api/status")
def api_status():
    """获取系统状态"""
    return jsonify(get_system_status())

@app.route("/api/backups")
def api_backups():
    """获取备份列表"""
    backups = get_backup_list()
    return jsonify({
        "success": True,
        "count": len(backups),
        "backups": backups
    })

@app.route("/api/backup", methods=["POST"])
def api_backup():
    """执行备份"""
    log("API: 收到备份请求")
    
    # 执行备份脚本
    returncode, stdout, stderr = run_script("backup.sh")
    
    if returncode == 0:
        log("API: 备份成功")
        save_last_push_time()  # 记录推送时间
        backups = get_backup_list()
        return jsonify({
            "success": True,
            "message": "备份成功",
            "backups": backups
        })
    else:
        log(f"API: 备份失败 - {stderr}")
        return jsonify({
            "success": False,
            "message": f"备份失败: {stderr}",
            "stdout": stdout,
            "stderr": stderr
        }), 500

@app.route("/api/backup-system", methods=["POST"])
def api_backup_system():
    """备份系统代码"""
    log("API: 收到备份系统代码请求")
    
    # 创建备份系统代码备份
    backup_filename = f"backup_system-{datetime.now().strftime('%Y-%m-%d')}.tar.gz"
    backup_path = os.path.join(BACKUP_DIR, backup_filename)
    
    try:
        # 排除备份文件和大文件
        result = subprocess.run([
            "tar", "-czf", backup_path, "-C", os.path.expanduser("~"),
            "--exclude=backup-system/.git",
            "--exclude=backup-system/web/node_modules",
            "--exclude=backup-system/venv",
            "--exclude=backup-system/web/.next",
            "backup-system"
        ], capture_output=True, text=True, timeout=300)
        
        if result.returncode == 0 and os.path.exists(backup_path):
            size = os.path.getsize(backup_path)
            size_human = get_size_human(size)
            log(f"API: 备份系统代码备份成功 - {backup_filename} ({size_human})")
            
            # 推送到 backup_system 仓库
            try:
                subprocess.run(["git", "-C", BACKUP_DIR.rsplit('/', 1)[0], "add", f"backups/{backup_filename}"], capture_output=True)
                subprocess.run(["git", "-C", BACKUP_DIR.rsplit('/', 1)[0], "commit", "-m", f"Backup System {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}"], capture_output=True)
                push_result = subprocess.run(["git", "-C", BACKUP_DIR.rsplit('/', 1)[0], "push", "backup-system", "master"], capture_output=True, text=True)
                if push_result.returncode == 0:
                    log("API: 备份系统代码 GitHub 推送成功")
                else:
                    log(f"API: 备份系统代码 GitHub 推送失败 - {push_result.stderr}")
            except Exception as e:
                log(f"API: 备份系统代码推送异常 - {str(e)}")
            
            backups = get_backup_list()
            return jsonify({
                "success": True,
                "message": f"备份系统代码备份成功 ({size_human})",
                "backups": backups
            })
        else:
            log(f"API: 备份系统代码备份失败 - {result.stderr}")
            return jsonify({
                "success": False,
                "message": f"备份失败: {result.stderr}"
            }), 500
    except Exception as e:
        log(f"API: 备份系统代码备份异常 - {str(e)}")
        return jsonify({
            "success": False,
            "message": f"备份失败: {str(e)}"
        }), 500

@app.route("/api/restore", methods=["POST"])
def api_restore():
    """恢复备份"""
    data = request.get_json()
    filename = data.get("filename")
    
    if not filename:
        return jsonify({
            "success": False,
            "message": "缺少 filename 参数"
        }), 400
    
    log(f"API: 收到恢复请求 - {filename}")
    
    # 执行恢复脚本
    returncode, stdout, stderr = run_script("restore.sh", filename)
    
    if returncode == 0:
        log(f"API: 恢复成功 - {filename}")
        return jsonify({
            "success": True,
            "message": f"恢复成功: {filename}",
            "stdout": stdout
        })
    else:
        log(f"API: 恢复失败 - {stderr}")
        return jsonify({
            "success": False,
            "message": f"恢复失败: {stderr}",
            "stdout": stdout,
            "stderr": stderr
        }), 500

@app.route("/api/backup/<filename>", methods=["DELETE"])
def api_delete_backup(filename):
    """删除备份"""
    # 安全检查
    if ".." in filename or "/" in filename:
        return jsonify({
            "success": False,
            "message": "无效的文件名"
        }), 400
    
    backup_path = os.path.join(BACKUP_DIR, filename)
    
    if not os.path.exists(backup_path):
        return jsonify({
            "success": False,
            "message": "备份文件不存在"
        }), 404
    
    try:
        os.remove(backup_path)
        log(f"API: 删除备份成功 - {filename}")
        
        # 同时尝试从 GitHub 删除（如果配置了）
        # 这里简化处理，实际可能需要 git 操作
        
        return jsonify({
            "success": True,
            "message": f"删除成功: {filename}"
        })
    except Exception as e:
        log(f"API: 删除备份失败 - {str(e)}")
        return jsonify({
            "success": False,
            "message": f"删除失败: {str(e)}"
        }), 500

@app.route("/api/logs")
def api_logs():
    """获取日志"""
    if not os.path.exists(LOG_FILE):
        return jsonify({
            "success": True,
            "logs": [],
            "message": "暂无日志"
        })
    
    try:
        with open(LOG_FILE, "r") as f:
            lines = f.readlines()
        
        # 返回最后100行
        recent_lines = lines[-100:] if len(lines) > 100 else lines
        
        return jsonify({
            "success": True,
            "logs": [line.strip() for line in recent_lines],
            "total": len(lines)
        })
    except Exception as e:
        return jsonify({
            "success": False,
            "message": f"读取日志失败: {str(e)}"
        }), 500

@app.route("/api/cleanup", methods=["POST"])
def api_cleanup():
    """执行清理"""
    log("API: 收到清理请求")
    
    returncode, stdout, stderr = run_script("cleanup.sh")
    
    if returncode == 0:
        log("API: 清理成功")
        return jsonify({
            "success": True,
            "message": "清理成功",
            "stdout": stdout
        })
    else:
        log(f"API: 清理失败 - {stderr}")
        return jsonify({
            "success": False,
            "message": f"清理失败: {stderr}"
        }), 500

if __name__ == "__main__":
    # 确保目录存在
    os.makedirs(BACKUP_DIR, exist_ok=True)
    
    print("=" * 50)
    print("OpenClaw 备份系统 API 服务")
    print("=" * 50)
    print(f"备份目录: {BACKUP_DIR}")
    print(f"日志文件: {LOG_FILE}")
    print(f"API 地址: http://localhost:5000")
    print("=" * 50)
    
    # 启动服务
    app.run(host="0.0.0.0", port=5000, debug=False)
