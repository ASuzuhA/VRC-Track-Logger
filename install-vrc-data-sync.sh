#!/bin/bash

# ============================================================
# VRChat data.json → GitHub 自动同步服务
#
# Debian 12
#
# 功能：
#   1. 安装 Git / Python / watchdog
#   2. 创建数据目录
#   3. 克隆 GitHub 仓库
#   4. 配置 Git HTTPS + Fine-grained PAT
#   5. 创建 watchdog Python 服务
#   6. 创建 systemd 服务
#   7. 设置开机自启
#   8. 自动启动
#
# 运行方式：
#   chmod +x install-vrc-data-sync.sh
#   ./install-vrc-data-sync.sh
#
# ============================================================

set -Eeuo pipefail


# ============================================================
# 全局配置
# ============================================================

SOURCE_DIR="/root/vrcx_data"
SOURCE_FILE="/root/vrcx_data/data.json"

SYNC_DIR="/root/vrcx_sync"
PYTHON_SCRIPT="/root/vrcx_sync/vrc-data-sync.py"

REPO_DIR="/root/vrcx_github"

SERVICE_NAME="vrc-data-sync.service"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}"

REMOTE_NAME="origin"
BRANCH_NAME="main"

DEFAULT_REPO_URL="https://github.com/ASuzuhA/VRC-Track-Logger.git"

GIT_CREDENTIAL_FILE="/root/.git-credentials"


# ============================================================
# 颜色
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'


# ============================================================
# 输出函数
# ============================================================

info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

success() {
    echo -e "${GREEN}[ OK ]${NC} $*"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

error() {
    echo -e "${RED}[ERR ]${NC} $*"
}

step() {
    echo
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}$*${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo
}


# ============================================================
# 错误处理
# ============================================================

trap 'error "安装过程中发生错误，行号：$LINENO"' ERR


# ============================================================
# 必须 Root
# ============================================================

if [ "$(id -u)" -ne 0 ]; then
    error "请使用 root 运行此脚本。"
    echo
    echo "例如："
    echo "  sudo bash $0"
    exit 1
fi


# ============================================================
# 开始
# ============================================================

clear

echo
echo "============================================================"
echo "        VRChat data.json → GitHub 自动同步安装器"
echo "============================================================"
echo
echo "本程序将在本机部署："
echo
echo "  数据源：        ${SOURCE_FILE}"
echo "  Git 仓库：      ${REPO_DIR}"
echo "  同步程序：      ${PYTHON_SCRIPT}"
echo "  systemd：       ${SERVICE_NAME}"
echo
echo "上传方式："
echo "  Git HTTPS + GitHub Fine-grained Personal Access Token"
echo
echo "运行用户："
echo "  root"
echo
echo "============================================================"
echo


# ============================================================
# 第 1 步：安装依赖
# ============================================================

step "第 1/8 步：安装系统依赖"

info "更新 APT 软件包索引..."

apt-get update

info "安装 Git / Python / watchdog / CA 证书..."

apt-get install -y \
    git \
    python3 \
    python3-watchdog \
    ca-certificates

success "系统依赖安装完成。"


# ============================================================
# 第 2 步：检查版本
# ============================================================

step "第 2/8 步：检查环境"

echo
echo "Python："
python3 --version

echo
echo "Git："
git --version

echo
echo "watchdog："

python3 - <<'PY'
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler

print("watchdog OK")
PY

echo

success "Python / Git / watchdog 均可用。"


# ============================================================
# 第 3 步：创建目录
# ============================================================

step "第 3/8 步：创建本地目录"

mkdir -p "${SOURCE_DIR}"
mkdir -p "${SYNC_DIR}"

chmod 700 "${SOURCE_DIR}"
chmod 700 "${SYNC_DIR}"

success "数据目录：${SOURCE_DIR}"
success "同步程序目录：${SYNC_DIR}"


# ============================================================
# 第 4 步：询问 GitHub 仓库
# ============================================================

step "第 4/8 步：配置 GitHub 仓库"

echo "请输入 GitHub 仓库 HTTPS 地址。"
echo
echo "例如："
echo "  https://github.com/ASuzuhA/VRC-Track-Logger.git"
echo
echo "直接回车使用默认地址："
echo "  ${DEFAULT_REPO_URL}"
echo

read -r -p "GitHub Repository URL: " REPO_URL

if [ -z "${REPO_URL}" ]; then
    REPO_URL="${DEFAULT_REPO_URL}"
fi

echo
info "GitHub Repository：${REPO_URL}"


# ============================================================
# GitHub 用户操作教程
# ============================================================

echo
echo "============================================================"
echo "                【需要你手动完成的 GitHub 操作】"
echo "============================================================"
echo
echo "现在请打开 GitHub："
echo
echo "https://github.com/settings/personal-access-tokens/new"
echo
echo "然后创建 Fine-grained Personal Access Token。"
echo
echo "推荐设置："
echo
echo "  Token name:"
echo "      VRCX Data Sync"
echo
echo "  Resource owner:"
echo "      你的 GitHub 账号"
echo
echo "  Repository access:"
echo "      Only select repositories"
echo
echo "  Selected repositories:"
echo "      选择你刚才输入的仓库"
echo
echo "  Repository permissions:"
echo "      Contents → Read and write"
echo
echo "其他权限不需要。"
echo
echo "创建 Token 后："
echo
echo "  ⚠️ GitHub 只会完整显示 Token 一次。"
echo "  ⚠️ 不要把 Token 发给别人。"
echo "  ⚠️ 不要把 Token 提交到 Git 仓库。"
echo
echo "============================================================"
echo


read -r -p "已经创建好 Token？按 Enter 继续，Ctrl+C 取消：" _


# ============================================================
# 输入 GitHub 用户名
# ============================================================

echo

read -r -p "GitHub 用户名 [默认 ASuzuhA]: " GITHUB_USERNAME

if [ -z "${GITHUB_USERNAME}" ]; then
    GITHUB_USERNAME="ASuzuhA"
fi

echo


# ============================================================
# 安全输入 Token
# ============================================================

echo "请输入 GitHub Fine-grained Personal Access Token。"
echo
echo "输入时不会显示字符，这是正常现象。"
echo

read -r -s -p "GitHub Token: " GITHUB_TOKEN

echo
echo

if [ -z "${GITHUB_TOKEN}" ]; then
    error "Token 不能为空。"
    exit 1
fi

success "Token 已接收。"


# ============================================================
# 克隆 GitHub 仓库
# ============================================================

step "正在准备本地 Git 仓库"

if [ -d "${REPO_DIR}/.git" ]; then

    info "检测到已有 Git 仓库：${REPO_DIR}"

    CURRENT_REMOTE="$(git -C "${REPO_DIR}" remote get-url "${REMOTE_NAME}" 2>/dev/null || true)"

    if [ -n "${CURRENT_REMOTE}" ]; then

        info "当前 origin：${CURRENT_REMOTE}"

        if [ "${CURRENT_REMOTE}" != "${REPO_URL}" ]; then

            info "更新 origin 为 HTTPS..."

            git -C "${REPO_DIR}" remote set-url \
                "${REMOTE_NAME}" \
                "${REPO_URL}"

        fi

    else

        info "当前没有 origin，正在添加..."

        git -C "${REPO_DIR}" remote add \
            "${REMOTE_NAME}" \
            "${REPO_URL}"

    fi

else

    if [ -e "${REPO_DIR}" ]; then

        warn "${REPO_DIR} 已存在，但不是 Git 仓库。"

        echo
        read -r -p "删除并重新克隆？[y/N]: " CONFIRM

        if [[ ! "${CONFIRM}" =~ ^[Yy]$ ]]; then
            error "安装取消。"
            exit 1
        fi

        rm -rf "${REPO_DIR}"

    fi

    info "正在从 GitHub 克隆仓库..."

    git clone \
        "${REPO_URL}" \
        "${REPO_DIR}"

fi

success "Git 仓库准备完成。"


# ============================================================
# 配置 Git 用户信息
# ============================================================

echo
echo "Git commit 需要作者信息。"
echo

read -r -p "Git 用户名 [默认 VRChat Data Sync]: " GIT_USER_NAME

if [ -z "${GIT_USER_NAME}" ]; then
    GIT_USER_NAME="VRChat Data Sync"
fi

read -r -p "Git 邮箱 [默认 ${GITHUB_USERNAME}@users.noreply.github.com]: " GIT_USER_EMAIL

if [ -z "${GIT_USER_EMAIL}" ]; then
    GIT_USER_EMAIL="${GITHUB_USERNAME}@users.noreply.github.com"
fi

git -C "${REPO_DIR}" config user.name "${GIT_USER_NAME}"
git -C "${REPO_DIR}" config user.email "${GIT_USER_EMAIL}"

success "Git commit 作者信息已配置。"


# ============================================================
# 强制使用 HTTPS
# ============================================================

info "设置 Git origin 为 HTTPS..."

git -C "${REPO_DIR}" remote set-url \
    "${REMOTE_NAME}" \
    "${REPO_URL}"


# ============================================================
# 配置 Git credential helper
# ============================================================

info "配置 Git HTTPS Credential Store..."

git config --global credential.helper store

git config --global user.name "${GIT_USER_NAME}"
git config --global user.email "${GIT_USER_EMAIL}"

export HOME="/root"


# ============================================================
# 保存 GitHub Token
# ============================================================

info "写入 Git credential..."

# 先删除旧的同源凭据
if [ -f "${GIT_CREDENTIAL_FILE}" ]; then

    sed -i \
        '\#github\.com#d' \
        "${GIT_CREDENTIAL_FILE}"

fi

# 使用 Git credential 协议保存。
#
# Token 不会出现在命令行参数里，
# 避免出现在 ps 等进程信息中。
printf 'protocol=https\nhost=github.com\nusername=%s\npassword=%s\n\n' \
    "${GITHUB_USERNAME}" \
    "${GITHUB_TOKEN}" \
    | git credential approve

unset GITHUB_TOKEN

chmod 600 "${GIT_CREDENTIAL_FILE}"

success "GitHub Credential 已配置。"

echo
echo "Credential 文件权限："
ls -l "${GIT_CREDENTIAL_FILE}"
echo


# ============================================================
# 测试 GitHub HTTPS
# ============================================================

step "测试 GitHub HTTPS 认证"

info "正在测试 git ls-remote..."

if GIT_TERMINAL_PROMPT=0 \
    git -C "${REPO_DIR}" \
    ls-remote \
    "${REMOTE_NAME}" \
    HEAD
then

    success "GitHub HTTPS 认证成功！"

else

    error "GitHub HTTPS 认证失败。"

    echo
    echo "请检查："
    echo
    echo "1. Token 是否创建成功"
    echo "2. Token 是否选择了正确的仓库"
    echo "3. Repository permissions 是否有："
    echo "      Contents → Read and write"
    echo "4. Token 是否已经过期"
    echo

    exit 1

fi


# ============================================================
# 检查 main 分支
# ============================================================

step "检查 Git main 分支"

if git -C "${REPO_DIR}" show-ref \
    --verify \
    --quiet \
    "refs/remotes/${REMOTE_NAME}/${BRANCH_NAME}"
then

    info "检测到远程 main 分支。"

    git -C "${REPO_DIR}" checkout \
        -B "${BRANCH_NAME}" \
        "${REMOTE_NAME}/${BRANCH_NAME}"

else

    warn "没有检测到远程 main 分支。"

    CURRENT_BRANCH="$(git -C "${REPO_DIR}" branch --show-current || true)"

    if [ -n "${CURRENT_BRANCH}" ]; then

        info "当前分支：${CURRENT_BRANCH}"

    fi

fi


# ============================================================
# 创建 Python 同步程序
# ============================================================

step "第 5/8 步：创建 watchdog 同步程序"

cat > "${PYTHON_SCRIPT}" <<'PYTHON'
#!/usr/bin/env python3

import json
import os
import shutil
import subprocess
import threading
import time
from pathlib import Path

from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler


# ============================================================
# 配置
# ============================================================

SOURCE_FILE = Path("/root/vrcx_data/data.json")

REPO_DIR = Path("/root/vrcx_github")
TARGET_FILE = REPO_DIR / "data.json"

REMOTE = "origin"
BRANCH = "main"

DEBOUNCE_SECONDS = 2

COMMAND_TIMEOUT = 120


# ============================================================
# 全局状态
# ============================================================

sync_lock = threading.Lock()

debounce_timer = None

timer_lock = threading.Lock()


# ============================================================
# 日志
# ============================================================

def log(message):

    print(
        f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] {message}",
        flush=True
    )


# ============================================================
# 执行命令
# ============================================================

def run_command(command, cwd=None, timeout=COMMAND_TIMEOUT):

    log(f"执行: {' '.join(command)}")

    env = os.environ.copy()

    # systemd 环境
    env["HOME"] = "/root"

    # 禁止 Git 在后台等待输入
    env["GIT_TERMINAL_PROMPT"] = "0"

    try:

        result = subprocess.run(
            command,
            cwd=str(cwd) if cwd else None,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=timeout,
            check=False,
        )

    except subprocess.TimeoutExpired:

        log(
            f"❌ 命令超时：超过 {timeout} 秒"
        )

        return False

    except Exception as e:

        log(
            f"❌ 执行命令异常："
            f"{type(e).__name__}: {e}"
        )

        return False

    output = result.stdout.strip()

    if output:

        for line in output.splitlines():

            log(f"  {line}")

    if result.returncode != 0:

        log(
            f"❌ 命令失败，退出码："
            f"{result.returncode}"
        )

        return False

    return True


# ============================================================
# JSON 检查
# ============================================================

def validate_json():

    try:

        with SOURCE_FILE.open(
            "r",
            encoding="utf-8"
        ) as f:

            json.load(f)

        return True

    except Exception as e:

        log(
            f"⚠️ JSON 暂时无法解析：{e}"
        )

        return False


# ============================================================
# 等待文件稳定
# ============================================================

def wait_until_stable():

    previous = None

    for _ in range(20):

        try:

            stat = SOURCE_FILE.stat()

            current = (
                stat.st_size,
                stat.st_mtime_ns
            )

            if current == previous:

                if validate_json():

                    return True

            previous = current

        except FileNotFoundError:

            pass

        time.sleep(0.5)

    return False


# ============================================================
# Git 同步
# ============================================================

def sync_data():

    global debounce_timer

    if not sync_lock.acquire(blocking=False):

        log(
            "⏳ 已经有同步任务正在执行，"
            "本次事件跳过"
        )

        return

    try:

        log("========================================")

        log(
            "📥 检测到 data.json 更新"
        )

        log("========================================")

        if not SOURCE_FILE.exists():

            log(
                f"⚠️ 源文件不存在："
                f"{SOURCE_FILE}"
            )

            return

        log(
            "⏳ 等待 data.json 写入完成..."
        )

        if not wait_until_stable():

            log(
                "❌ data.json 长时间没有稳定，"
                "取消本次同步"
            )

            return

        log(
            "✅ data.json 已稳定且 JSON 有效"
        )

        # ----------------------------------------------------
        # 复制
        # ----------------------------------------------------

        log(
            "📋 开始复制 data.json"
        )

        temp_file = TARGET_FILE.with_suffix(
            ".json.tmp"
        )

        shutil.copy2(
            SOURCE_FILE,
            temp_file
        )

        os.replace(
            temp_file,
            TARGET_FILE
        )

        log(
            "✅ data.json 已复制到 Git 仓库"
        )

        # ----------------------------------------------------
        # Git status
        # ----------------------------------------------------

        result = subprocess.run(
            [
                "/usr/bin/git",
                "status",
                "--porcelain",
                "--",
                "data.json",
            ],
            cwd=str(REPO_DIR),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=30,
            check=False,
        )

        status = result.stdout.strip()

        if result.returncode != 0:

            log("❌ git status 失败")

            if status:

                log(status)

            return

        if not status:

            log(
                "ℹ️ data.json 没有 Git 变化，"
                "不需要 commit/push"
            )

            return

        log(
            f"📝 Git 检测到变化：{status}"
        )

        # ----------------------------------------------------
        # git add
        # ----------------------------------------------------

        if not run_command(
            [
                "/usr/bin/git",
                "add",
                "--",
                "data.json",
            ],
            cwd=REPO_DIR,
        ):

            return

        # ----------------------------------------------------
        # git commit
        # ----------------------------------------------------

        commit_message = (
            "chore: update VRChat data "
            + time.strftime(
                "%Y-%m-%d %H:%M:%S"
            )
        )

        if not run_command(
            [
                "/usr/bin/git",
                "commit",
                "-m",
                commit_message,
            ],
            cwd=REPO_DIR,
        ):

            return

        # ----------------------------------------------------
        # git push
        # ----------------------------------------------------

        log(
            "🚀 正在 push 到 GitHub..."
        )

        if not run_command(
            [
                "/usr/bin/git",
                "push",
                REMOTE,
                BRANCH,
            ],
            cwd=REPO_DIR,
            timeout=COMMAND_TIMEOUT,
        ):

            log(
                "❌ Git push 失败"
            )

            return

        log(
            "🎉 GitHub push 成功"
        )

    except Exception as e:

        log(
            "❌ 同步过程中发生异常："
            f"{type(e).__name__}: {e}"
        )

    finally:

        sync_lock.release()


# ============================================================
# 防抖
# ============================================================

def schedule_sync():

    global debounce_timer

    with timer_lock:

        if debounce_timer is not None:

            debounce_timer.cancel()

        debounce_timer = threading.Timer(
            DEBOUNCE_SECONDS,
            sync_data
        )

        debounce_timer.daemon = True

        debounce_timer.start()


# ============================================================
# watchdog
# ============================================================

class DataFileHandler(
    FileSystemEventHandler
):

    def is_target(self, path):

        try:

            return (
                Path(path).resolve()
                == SOURCE_FILE.resolve()
            )

        except Exception:

            return (
                Path(path)
                == SOURCE_FILE
            )

    def handle_event(self, event):

        if event.is_directory:

            return

        if self.is_target(
            event.src_path
        ):

            log(
                f"📡 文件事件："
                f"{event.event_type} -> "
                f"{event.src_path}"
            )

            schedule_sync()

        if hasattr(
            event,
            "dest_path"
        ):

            if event.dest_path:

                if self.is_target(
                    event.dest_path
                ):

                    log(
                        f"📡 文件移动："
                        f"{event.src_path} -> "
                        f"{event.dest_path}"
                    )

                    schedule_sync()

    def on_modified(self, event):

        self.handle_event(event)

    def on_created(self, event):

        self.handle_event(event)

    def on_moved(self, event):

        self.handle_event(event)

    def on_closed(self, event):

        self.handle_event(event)


# ============================================================
# 主程序
# ============================================================

def main():

    watch_dir = SOURCE_FILE.parent

    if not watch_dir.exists():

        log(
            f"❌ 监听目录不存在："
            f"{watch_dir}"
        )

        raise SystemExit(1)

    if not REPO_DIR.exists():

        log(
            f"❌ Git 仓库不存在："
            f"{REPO_DIR}"
        )

        raise SystemExit(1)

    log("========================================")

    log(
        "🤖 VRChat 数据自动同步服务"
    )

    log("========================================")

    log(
        f"📌 数据源：{SOURCE_FILE}"
    )

    log(
        f"📌 Git 仓库：{REPO_DIR}"
    )

    log(
        f"📌 Git 目标：{TARGET_FILE}"
    )

    log(
        f"📌 Remote：{REMOTE}"
    )

    log(
        f"📌 Branch：{BRANCH}"
    )

    log(
        "📌 Git 认证：HTTPS + "
        "/root/.git-credentials"
    )

    log(
        f"📌 防抖时间："
        f"{DEBOUNCE_SECONDS} 秒"
    )

    event_handler = DataFileHandler()

    observer = Observer()

    observer.schedule(
        event_handler,
        str(watch_dir),
        recursive=False,
    )

    observer.start()

    log(
        "👂 watchdog/inotify 监听已启动"
    )

    try:

        while True:

            time.sleep(3600)

    except KeyboardInterrupt:

        log(
            "🛑 收到停止信号"
        )

    finally:

        observer.stop()

        observer.join()

        log(
            "👋 服务已停止"
        )


if __name__ == "__main__":

    main()
PYTHON

chmod 700 "${SYNC_DIR}"
chmod 700 "${PYTHON_SCRIPT}"

success "Python 同步程序创建完成：${PYTHON_SCRIPT}"


# ============================================================
# 创建 systemd
# ============================================================

step "第 6/8 步：创建 systemd 服务"

cat > "${SERVICE_FILE}" <<EOF
[Unit]
Description=VRChat Data Auto Sync to GitHub
After=network-online.target
Wants=network-online.target

[Service]
Type=simple

User=root
Group=root

ExecStart=/usr/bin/python3 ${PYTHON_SCRIPT}

WorkingDirectory=${REPO_DIR}

Environment="HOME=/root"
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin"
Environment="GIT_TERMINAL_PROMPT=0"

Restart=always
RestartSec=5

StandardOutput=journal
StandardError=journal

TimeoutStopSec=15

[Install]
WantedBy=multi-user.target
EOF

chmod 644 "${SERVICE_FILE}"

success "systemd 服务创建完成。"


# ============================================================
# 检查 Python
# ============================================================

step "第 7/8 步：检查程序"

python3 -m py_compile "${PYTHON_SCRIPT}"

success "Python 语法检查通过。"


# ============================================================
# systemd reload + enable + start
# ============================================================

info "重新加载 systemd..."

systemctl daemon-reload

info "设置开机自动启动..."

systemctl enable "${SERVICE_NAME}"

info "启动服务..."

systemctl restart "${SERVICE_NAME}"

sleep 2


# ============================================================
# 检查服务
# ============================================================

if systemctl is-active --quiet "${SERVICE_NAME}"; then

    success "VRChat 数据同步服务启动成功！"

else

    error "VRChat 数据同步服务启动失败。"

    echo
    systemctl status \
        "${SERVICE_NAME}" \
        --no-pager \
        -l

    echo
    echo "查看详细日志："
    echo
    echo "  journalctl -u ${SERVICE_NAME} -n 100 --no-pager"
    echo

    exit 1

fi


# ============================================================
# 最终检查
# ============================================================

step "第 8/8 步：最终检查"

echo
echo "服务状态："

systemctl is-active \
    "${SERVICE_NAME}"

echo

echo "开机自启："

systemctl is-enabled \
    "${SERVICE_NAME}"

echo

echo "Git Remote："

git -C "${REPO_DIR}" remote -v

echo

echo "Git Credential："

if [ -f "${GIT_CREDENTIAL_FILE}" ]; then

    echo "  /root/.git-credentials 存在"

    ls -l "${GIT_CREDENTIAL_FILE}"

else

    warn "/root/.git-credentials 不存在！"

fi

echo

echo "数据源目录："

ls -ld "${SOURCE_DIR}"

echo

echo "Git 仓库："

ls -ld "${REPO_DIR}"

echo


# ============================================================
# 完成
# ============================================================

echo
echo "============================================================"
echo "                  🎉 部署完成！"
echo "============================================================"
echo
echo "数据源："
echo "  ${SOURCE_FILE}"
echo
echo "Git 仓库："
echo "  ${REPO_DIR}"
echo
echo "同步程序："
echo "  ${PYTHON_SCRIPT}"
echo
echo "systemd："
echo "  ${SERVICE_NAME}"
echo
echo "GitHub 上传方式："
echo "  HTTPS + Fine-grained Personal Access Token"
echo
echo "开机自启："
echo "  已启用"
echo
echo "当前状态："
echo "  $(systemctl is-active "${SERVICE_NAME}")"
echo
echo "============================================================"
echo
echo "常用命令："
echo
echo "查看服务状态："
echo "  systemctl status ${SERVICE_NAME}"
echo
echo "实时查看同步日志："
echo "  journalctl -u ${SERVICE_NAME} -f"
echo
echo "查看最近 100 条日志："
echo "  journalctl -u ${SERVICE_NAME} -n 100 --no-pager"
echo
echo "停止服务："
echo "  systemctl stop ${SERVICE_NAME}"
echo
echo "重新启动："
echo "  systemctl restart ${SERVICE_NAME}"
echo
echo "取消开机自启："
echo "  systemctl disable ${SERVICE_NAME}"
echo
echo "============================================================"
echo
echo "服务会持续监听："
echo
echo "  ${SOURCE_FILE}"
echo
echo "只要 data.json 发生变化，就会自动："
echo
echo "  data.json"
echo "      ↓"
echo "  watchdog/inotify"
echo "      ↓"
echo "  等待文件稳定"
echo "      ↓"
echo "  JSON 验证"
echo "      ↓"
echo "  复制到 Git 仓库"
echo "      ↓"
echo "  git add"
echo "      ↓"
echo "  git commit"
echo "      ↓"
echo "  git push origin main"
echo "      ↓"
echo "  GitHub"
echo
echo "============================================================"
echo
echo "💡 建议现在执行一次："
echo
echo "  journalctl -u ${SERVICE_NAME} -f"
echo
echo "然后让 VRCX 更新一次 data.json，观察是否出现："
echo
echo "  🎉 GitHub push 成功"
echo
echo "============================================================"
echo
