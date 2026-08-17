#!/bin/bash

# ============================================================
# VRChat Git 同步故障修复工具
#
# 用途：
#   当 GitHub main 分支出现：
#
#       ! [rejected] main -> main (fetch first)
#
#   或者：
#
#       remote contains work that you do not have locally
#
#   时使用。
#
# 目录：
#   数据源：
#       /root/vrcx_data/data.json
#
#   Git 仓库：
#       /root/vrcx_github
#
#   远程：
#       origin
#
#   分支：
#       main
#
# ============================================================

set -Eeuo pipefail


# ============================================================
# 配置
# ============================================================

SOURCE_FILE="/root/vrcx_data/data.json"

REPO_DIR="/root/vrcx_github"

REMOTE="origin"

BRANCH="main"

SERVICE="vrc-data-sync.service"

CREDENTIAL_FILE="/root/.git-credentials"


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
# 输出
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
# 必须 root
# ============================================================

if [ "$(id -u)" -ne 0 ]; then

    error "请使用 root 运行。"

    exit 1

fi


# ============================================================
# 开始
# ============================================================

clear

echo
echo "============================================================"
echo "          VRChat Git 同步故障修复工具"
echo "============================================================"
echo
echo "这个工具用于修复："
echo
echo "  git push 被 GitHub 拒绝"
echo "  fetch first"
echo "  non-fast-forward"
echo "  remote contains work"
echo
echo "============================================================"
echo


# ============================================================
# 检查目录
# ============================================================

step "第 1 步：检查本地 Git 仓库"

if [ ! -d "${REPO_DIR}/.git" ]; then

    error "Git 仓库不存在：${REPO_DIR}"

    exit 1

fi

success "Git 仓库存在。"


# ============================================================
# 检查源文件
# ============================================================

if [ ! -f "${SOURCE_FILE}" ]; then

    error "源 data.json 不存在：${SOURCE_FILE}"

    exit 1

fi

success "源 data.json 存在。"


# ============================================================
# 停止自动同步
# ============================================================

step "第 2 步：暂停自动同步服务"

if systemctl is-active --quiet "${SERVICE}"; then

    info "正在停止 ${SERVICE}..."

    systemctl stop "${SERVICE}"

    success "自动同步服务已暂停。"

else

    info "自动同步服务当前没有运行。"

fi


# ============================================================
# 检查 Git 状态
# ============================================================

step "第 3 步：检查 Git 当前状态"

cd "${REPO_DIR}"

echo

git status

echo


# ============================================================
# 显示本地 / 远程 commit
# ============================================================

step "第 4 步：检查本地与 GitHub 的差异"

info "获取 GitHub 最新状态..."

git fetch "${REMOTE}"

echo

echo "本地 HEAD："

git rev-parse HEAD

echo

echo "GitHub main："

git rev-parse "${REMOTE}/${BRANCH}"

echo


# ============================================================
# 检查是否存在本地未提交修改
# ============================================================

if ! git diff --quiet || ! git diff --cached --quiet; then

    warn "检测到本地存在未提交修改。"

    echo

    git status --short

    echo

    echo "为了避免覆盖你的修改，修复程序不会继续自动 rebase。"

    echo

    read -r -p \
        "是否将当前修改暂存到 Git stash？[y/N]: " \
        STASH_CONFIRM

    if [[ "${STASH_CONFIRM}" =~ ^[Yy]$ ]]; then

        git stash push \
            -u \
            -m "vrc-data-sync repair $(date '+%Y-%m-%d %H:%M:%S')"

        success "本地修改已经暂存到 stash。"

    else

        error "检测到未提交修改，修复终止。"

        systemctl start "${SERVICE}" || true

        exit 1

    fi

fi


# ============================================================
# 重新同步远程
# ============================================================

step "第 5 步：同步 GitHub main"

info "执行：git fetch ${REMOTE}"

git fetch "${REMOTE}"

success "GitHub 最新数据已获取。"


# ============================================================
# 分析分支关系
# ============================================================

LOCAL_COMMIT="$(git rev-parse HEAD)"

REMOTE_COMMIT="$(git rev-parse "${REMOTE}/${BRANCH}")"

echo

echo "本地 HEAD："
echo "  ${LOCAL_COMMIT}"

echo

echo "远程 main："
echo "  ${REMOTE_COMMIT}"

echo


# ============================================================
# 如果已经完全一致
# ============================================================

if [ "${LOCAL_COMMIT}" = "${REMOTE_COMMIT}" ]; then

    success "本地与 GitHub 已经完全同步。"

else

    # --------------------------------------------------------
    # 检查本地是否领先
    # --------------------------------------------------------

    AHEAD_COUNT="$(
        git rev-list \
            --count \
            "${REMOTE}/${BRANCH}..HEAD"
    )"

    BEHIND_COUNT="$(
        git rev-list \
            --count \
            "HEAD..${REMOTE}/${BRANCH}"
    )"

    echo
    echo "本地领先：${AHEAD_COUNT} 个 commit"
    echo "远程领先：${BEHIND_COUNT} 个 commit"
    echo


    # --------------------------------------------------------
    # 只有远程领先
    # --------------------------------------------------------

    if [ "${AHEAD_COUNT}" -eq 0 ] &&
       [ "${BEHIND_COUNT}" -gt 0 ]; then

        info "GitHub 比本地更新。"

        info "执行 fast-forward..."

        git merge \
            --ff-only \
            "${REMOTE}/${BRANCH}"

        success "本地已经追上 GitHub。"


    # --------------------------------------------------------
    # 只有本地领先
    # --------------------------------------------------------

    elif [ "${AHEAD_COUNT}" -gt 0 ] &&
         [ "${BEHIND_COUNT}" -eq 0 ]; then

        success "本地比 GitHub 更新。"

        info "无需 rebase，准备 push。"


    # --------------------------------------------------------
    # 两边都有新 commit
    # --------------------------------------------------------

    elif [ "${AHEAD_COUNT}" -gt 0 ] &&
         [ "${BEHIND_COUNT}" -gt 0 ]; then

        warn "检测到本地和 GitHub 都存在新的 commit。"

        echo

        echo "将执行："

        echo

        echo "  git rebase ${REMOTE}/${BRANCH}"

        echo

        info "开始 rebase..."

        if ! git rebase "${REMOTE}/${BRANCH}"; then

            echo

            error "Git rebase 出现冲突。"

            echo

            git status

            echo

            echo "============================================================"
            echo "需要人工处理冲突"
            echo "============================================================"
            echo
            echo "处理完冲突后："
            echo
            echo "  git add <文件>"
            echo "  git rebase --continue"
            echo
            echo "如果想取消："
            echo
            echo "  git rebase --abort"
            echo

            error "自动修复没有继续，以免覆盖你的内容。"

            exit 1

        fi

        success "rebase 成功。"

    fi

fi


# ============================================================
# 强制重新复制最新 data.json
# ============================================================

step "第 6 步：确保最新 data.json 在 Git 仓库中"

info "源文件："
echo "  ${SOURCE_FILE}"

info "目标文件："
echo "  ${REPO_DIR}/data.json"

echo

cp -f \
    "${SOURCE_FILE}" \
    "${REPO_DIR}/data.json"

success "最新 data.json 已复制。"


# ============================================================
# 检查 JSON
# ============================================================

info "验证 JSON..."

python3 - <<PY
import json

path = "${SOURCE_FILE}"

with open(path, "r", encoding="utf-8") as f:
    json.load(f)

print("JSON OK")
PY

success "JSON 验证通过。"


# ============================================================
# Git add
# ============================================================

step "第 7 步：提交最新 data.json"

git add -- data.json

if git diff --cached --quiet; then

    info "data.json 没有变化。"

else

    COMMIT_MESSAGE="chore: update VRChat data $(date '+%Y-%m-%d %H:%M:%S')"

    git commit \
        -m "${COMMIT_MESSAGE}"

    success "新的 data.json commit 已创建。"

fi


# ============================================================
# Push
# ============================================================

step "第 8 步：Push 到 GitHub"

info "第一次尝试 push..."

if git push "${REMOTE}" "${BRANCH}"; then

    success "🎉 GitHub push 成功！"

else

    warn "第一次 push 失败。"

    echo

    warn "重新 fetch GitHub..."

    git fetch "${REMOTE}"

    echo

    warn "重新检查分支关系..."

    LOCAL_COMMIT="$(git rev-parse HEAD)"

    REMOTE_COMMIT="$(git rev-parse "${REMOTE}/${BRANCH}")"

    if [ "${LOCAL_COMMIT}" != "${REMOTE_COMMIT}" ]; then

        info "执行 rebase..."

        if ! git rebase "${REMOTE}/${BRANCH}"; then

            error "rebase 冲突，停止修复。"

            echo

            git status

            exit 1

        fi

    fi

    echo

    info "第二次 push..."

    if git push "${REMOTE}" "${BRANCH}"; then

        success "🎉 第二次 push 成功！"

    else

        error "第二次 push 仍然失败。"

        echo

        echo "请查看："

        echo

        git status

        echo

        exit 1

    fi

fi


# ============================================================
# 恢复 stash
# ============================================================

if git stash list | grep -q "vrc-data-sync repair"; then

    step "恢复之前暂存的本地修改"

    warn "检测到之前保存的 stash。"

    echo

    git stash list

    echo

    read -r -p \
        "是否现在恢复 stash？[y/N]: " \
        RESTORE_STASH

    if [[ "${RESTORE_STASH}" =~ ^[Yy]$ ]]; then

        if git stash pop; then

            success "stash 已恢复。"

        else

            warn "stash 恢复时产生冲突。"

            echo

            git status

        fi

    else

        info "stash 保留，没有自动删除。"

    fi

fi


# ============================================================
# 恢复 systemd
# ============================================================

step "第 9 步：恢复自动同步服务"

systemctl start "${SERVICE}"

sleep 2

if systemctl is-active --quiet "${SERVICE}"; then

    success "自动同步服务已经恢复运行。"

else

    error "自动同步服务启动失败。"

    echo

    systemctl status \
        "${SERVICE}" \
        --no-pager \
        -l

    exit 1

fi


# ============================================================
# 最终状态
# ============================================================

step "修复完成"

echo

echo "Git 分支："

git status

echo

echo "当前 commit："

git log -1 --oneline

echo

echo "GitHub remote："

git remote -v

echo

echo "systemd："

systemctl is-active "${SERVICE}"

echo

echo "开机自启："

systemctl is-enabled "${SERVICE}"

echo

echo "============================================================"
echo "                    🎉 修复完成"
echo "============================================================"
echo
echo "自动同步服务已经重新启动。"
echo
echo "实时查看日志："
echo
echo "  journalctl -u ${SERVICE} -f"
echo
echo "============================================================"
echo
