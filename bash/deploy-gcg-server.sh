#!/usr/bin/env bash

# deploy-gcg-server.sh
# 交互式 一键部署脚本（数字菜单）
# 说明：脚本将操作分为“服务端 (Server)” 和 “客户端 (Client)” 两部分，
# 每个操作都有一个数字编号，运行脚本后输入数字即可执行相应步骤。
#
# 使用：
#   chmod +x deploy-gcg-server.sh
#   ./deploy-gcg-server.sh
# 或：一次性执行某个步骤（非交互）：
#   ./deploy-gcg-server.sh --run 3   # 直接运行菜单项 3
# 可选参数：
#   --base-dir DIR   指定基目录（默认为脚本所在目录下的 gcg 文件夹）
#   --install-deps   在需要时安装 apt 依赖（会使用 sudo）
#
set -euo pipefail

# 默认变量（必要时可在脚本头手动修改）
BASE_DIR="$(dirname "$(realpath "$0")")/gcg"
SERVER_REPO="https://github.com/FogMoe/gcgserver.git"
SERVER_BRANCH="fix"
CLIENT_REPO="https://github.com/FogMoe/galaxycardgame.git"
CLIENT_BRANCH="server"
PREMAKE_BIN_NAME="premake5"
LUA_INCLUDE_DIR="/usr/include/lua5.4"
LUA_LIB_NAME="lua5.4-c++"

# 解析命令行快速运行某项（可选）
QUICK_RUN=""
INSTALL_DEPS=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-dir) BASE_DIR="$2"; shift 2 ;;
    --install-deps) INSTALL_DEPS=true; shift ;;
    --run) QUICK_RUN="$2"; shift 2 ;;
    --help) echo "Usage: $0 [--base-dir DIR] [--install-deps] [--run N]"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

# 创建目录
mkdir -p "$BASE_DIR"

DEPENDENCIES_OK="true"

# 检查必要工具的函数
check_dependencies() {
  local missing_tools=()
  
  # 检查必要的命令行工具
  for tool in git curl wget unzip make npm tar; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      missing_tools+=("$tool")
    fi
  done
  
  if [ ${#missing_tools[@]} -gt 0 ]; then
    echo "错误：缺少以下必要工具：${missing_tools[*]}" >&2
    echo "请运行菜单项 1 安装系统依赖，或手动安装这些工具。" >&2
    return 1
  fi
  
  return 0
}

# 检查依赖（除非是安装依赖的操作）
if [ "$QUICK_RUN" != "1" ] && [ "$INSTALL_DEPS" != "true" ]; then
  if ! check_dependencies; then
    DEPENDENCIES_OK="false"
    echo "提示：检测到缺少依赖，请运行: $0 --install-deps" >&2
    echo "或者直接运行: $0 --run 1 来安装系统依赖。" >&2
  fi
fi

# 工具函数：克隆或更新仓库
clone_or_pull() {
  local repo_url="$1"
  local branch="$2"
  local dest="$3"
  if [ -d "$dest/.git" ]; then
    echo "更新仓库 $dest -> 分支 $branch"
    git -C "$dest" fetch --all --prune
    git -C "$dest" checkout "$branch" || git -C "$dest" checkout -B "$branch" "origin/$branch"
    git -C "$dest" pull --ff-only || git -C "$dest" pull
  else
    echo "克隆仓库 $repo_url 到 $dest (分支 $branch)"
    git clone -b "$branch" "$repo_url" "$dest"
  fi
}

# 1) 安装系统依赖（可选）
install_system_deps() {
  echo "安装系统依赖（需要 sudo）..."
  sudo apt update
  sudo apt install -y libevent-dev libfreetype6-dev libgl1-mesa-dev libglu1-mesa-dev libxxf86vm-dev libsqlite3-dev libopusfile-dev libvorbis-dev build-essential wget unzip curl git npm liblua5.4-dev
  if check_dependencies; then
    DEPENDENCIES_OK="true"
  else
    DEPENDENCIES_OK="false"
    echo "警告：依赖安装后仍检测到缺失，请检查输出信息。" >&2
  fi
}

# ----- 服务端(Server) 操作 -----
# 2) 克隆或更新 gcgserver
server_clone_update() {
  local SERVER_DIR="$BASE_DIR/gcgserver"
  clone_or_pull "$SERVER_REPO" "$SERVER_BRANCH" "$SERVER_DIR"
}

# 3) 在 gcgserver 目录运行 npm install
server_npm_install() {
  local SERVER_DIR="$BASE_DIR/gcgserver"
  if [ -f "$SERVER_DIR/package.json" ]; then
    echo "在 $SERVER_DIR 运行 npm install"
    (cd "$SERVER_DIR" && npm install)
  else
    echo "跳过：$SERVER_DIR/package.json 不存在"
  fi
}

# 4) 在 gcgserver 创建/替换 ygopro 符号链接（指向客户端）
server_create_symlink() {
  local SERVER_DIR="$BASE_DIR/gcgserver"
  local CLIENT_DIR="$BASE_DIR/galaxycardgame"
  local LINK_PATH="$SERVER_DIR/ygopro"
  
  if [ ! -d "$CLIENT_DIR" ]; then
    echo "错误：客户端目录 $CLIENT_DIR 不存在。请先运行菜单项 6 克隆客户端。" >&2
    return 1
  fi
  
  if [ ! -d "$SERVER_DIR" ]; then
    echo "错误：服务端目录 $SERVER_DIR 不存在。请先运行菜单项 2 克隆服务端。" >&2
    return 1
  fi
  
  if [ -L "$LINK_PATH" ] || [ -e "$LINK_PATH" ]; then
    echo "移除已存在的 $LINK_PATH"
    rm -rf "$LINK_PATH"
  fi
  ln -s "$CLIENT_DIR" "$LINK_PATH"
  echo "已创建符号链接: $LINK_PATH -> $CLIENT_DIR"
}

# 5) 启动 gcgserver（npm start，前台运行）
server_start() {
  local SERVER_DIR="$BASE_DIR/gcgserver"
  if [ -f "$SERVER_DIR/package.json" ]; then
    echo "启动服务器： cd $SERVER_DIR && npm start （Ctrl+C 停止）"
    cd "$SERVER_DIR"
    npm start
  else
    echo "无法启动：$SERVER_DIR/package.json 不存在"
  fi
}

# ----- 客户端(Client) 操作 -----
# 6) 克隆或更新 galaxycardgame
client_clone_update() {
  local CLIENT_DIR="$BASE_DIR/galaxycardgame"
  clone_or_pull "$CLIENT_REPO" "$CLIENT_BRANCH" "$CLIENT_DIR"
}

# 7) 下载 premake5（如果缺失）
client_download_premake() {
  local CLIENT_DIR="$BASE_DIR/galaxycardgame"
  if [ ! -d "$CLIENT_DIR" ]; then
    echo "错误：客户端目录 $CLIENT_DIR 不存在。请先运行菜单项 6 克隆客户端。" >&2
    return 1
  fi
  cd "$CLIENT_DIR"
  if [ ! -x "./$PREMAKE_BIN_NAME" ]; then
    echo "下载 premake5..."
    local download_url=""
    download_url=$(fetch_latest_premake_url || true)
    if [ -z "$download_url" ]; then
      echo "警告：无法获取最新版本下载链接，改用预设备用链接。" >&2
      download_url="https://github.com/premake/premake-core/releases/download/v5.0.0-alpha16/premake-5.0.0-alpha16-linux.tar.gz"
    fi
    if ! wget -qO premake5.tar.gz "$download_url"; then
      echo "错误：下载 premake5 失败，请检查网络连接或稍后重试。" >&2
      return 1
    fi
    tar -xzf premake5.tar.gz
    rm -f premake5.tar.gz
    if compgen -G "premake-*/$PREMAKE_BIN_NAME" > /dev/null; then
      mv premake-*/$PREMAKE_BIN_NAME . || true
      rm -rf premake-*
    fi
    chmod +x ./$PREMAKE_BIN_NAME || true
    if [ -x "./$PREMAKE_BIN_NAME" ]; then
      echo "premake5 就绪： $CLIENT_DIR/$PREMAKE_BIN_NAME"
    else
      echo "警告：premake5 可执行文件仍不可用，请手动检查。" >&2
      return 1
    fi
  else
    echo "premake5 已存在： $CLIENT_DIR/$PREMAKE_BIN_NAME"
  fi
}

# 通用函数：检测 GitHub API rate limit
check_github_rate_limit() {
  local remaining=$(curl -sI https://api.github.com/rate_limit | awk '/^x-ratelimit-remaining:/ {print $2}' | tr -d '\r')
  if [ -n "$remaining" ] && [ "$remaining" -eq 0 ] 2>/dev/null; then
    return 1
  fi
  return 0
}

fetch_latest_premake_url() {
  if check_github_rate_limit; then
    curl -s https://api.github.com/repos/premake/premake-core/releases/latest \
      | grep "browser_download_url.*premake-.*linux.*tar.gz" \
      | cut -d '"' -f 4 | head -n1
  fi
}

# 8) 用 premake 生成 gmake（指定 Lua include/lib）
client_run_premake() {
  local CLIENT_DIR="$BASE_DIR/galaxycardgame"
  if [ ! -d "$CLIENT_DIR" ]; then
    echo "错误：客户端目录 $CLIENT_DIR 不存在。请先运行菜单项 6 克隆客户端。" >&2
    return 1
  fi
  cd "$CLIENT_DIR"
  if [ -x "./$PREMAKE_BIN_NAME" ]; then
    echo "运行 premake 生成 gmake 文件..."
    ./$PREMAKE_BIN_NAME gmake --no-build-lua --lua-lib-name="$LUA_LIB_NAME" --lua-include-dir="$LUA_INCLUDE_DIR"
  else
    echo "找不到 premake5，可先运行菜单项 7 下载 premake5。"
    return 1
  fi
}

# 9) 确保 sqlite3/sqlite3.h 存在（从官网自动抓取）
client_ensure_sqlite() {
  local CLIENT_DIR="$BASE_DIR/galaxycardgame"
  if [ -f "$CLIENT_DIR/sqlite3/sqlite3.h" ]; then
    echo "sqlite3/sqlite3.h 已存在，跳过下载。"
    return
  fi
  echo "尝试下载 sqlite amalgamation 到 $CLIENT_DIR/sqlite3/ ..."
  mkdir -p "$CLIENT_DIR/sqlite3"
  
  # 创建临时目录避免文件冲突
  local TEMP_DIR=$(mktemp -d)
  cd "$TEMP_DIR"
  
  SQLITE_ZIP_URL=$(curl -s https://www.sqlite.org/download.html | grep -oE 'https://www.sqlite.org/[0-9]{4}/sqlite-amalgamation-[0-9]+\\.zip' | head -n1 || true)
  if [ -z "$SQLITE_ZIP_URL" ]; then
    echo "警告：无法从官网页面解析版本号，改用最新稳定版本链接。" >&2
    SQLITE_ZIP_URL="https://www.sqlite.org/2025/sqlite-amalgamation-3500400.zip"
  fi
  echo "下载： $SQLITE_ZIP_URL"
  
  if wget -qO sqlite-amalgamation.zip "$SQLITE_ZIP_URL"; then
    unzip -o sqlite-amalgamation.zip >/dev/null
    if mv -f sqlite-amalgamation-*/sqlite3.[ch] "$CLIENT_DIR/sqlite3/" 2>/dev/null; then
      echo "sqlite 已放置到 $CLIENT_DIR/sqlite3/"
    else
      echo "警告：无法移动 sqlite 文件到目标目录，请手动检查。" >&2
    fi
  else
    echo "下载失败，跳过 sqlite 自动获取。" >&2
  fi
  
  # 清理临时目录
  cd "$BASE_DIR"
  rm -rf "$TEMP_DIR"
  
  if [ ! -f "$CLIENT_DIR/sqlite3/sqlite3.h" ]; then
    echo "警告：仍未找到 sqlite3.h，请手动放置到 $CLIENT_DIR/sqlite3/ 下或安装 libsqlite3-dev。" >&2
  fi
}

# 10) 构建客户端（make config=release）
client_build() {
  local CLIENT_DIR="$BASE_DIR/galaxycardgame"
  if [ -d "$CLIENT_DIR/build" ]; then
    echo "开始构建 galaxycardgame (release)..."
    (cd "$CLIENT_DIR/build" && make config=release)
  else
    echo "构建目录不存在: $CLIENT_DIR/build 。请先运行 premake（菜单项 8）。" >&2
  fi
}

# 11) 将编译好的 ygopro 移回项目根（可选）
client_move_ygopro() {
  local CLIENT_DIR="$BASE_DIR/galaxycardgame"
  if [ -f "$CLIENT_DIR/bin/release/ygopro" ]; then
    echo "移动 ygopro 到 $CLIENT_DIR/ygopro"
    mv -f "$CLIENT_DIR/bin/release/ygopro" "$CLIENT_DIR/ygopro"
  else
    echo "未找到 bin/release/ygopro，跳过。"
  fi
}

# 14) 更新服务（git pull + pm2 restart）
update_services() {
  local SERVER_DIR="$BASE_DIR/gcgserver"
  local CLIENT_DIR="$BASE_DIR/galaxycardgame"
  local SCRIPT_URL="https://raw.githubusercontent.com/FogMoe/gcgserver/fix/bash/deploy-gcg-server.sh"

  echo "=== 开始更新服务 ==="

  # 首先更新脚本本身
  echo "正在更新部署脚本..."
  local TEMP_SCRIPT="/tmp/deploy-gcg-server-new.sh"
  if curl -fsSL -o "$TEMP_SCRIPT" "$SCRIPT_URL"; then
    if [ -f "$TEMP_SCRIPT" ] && [ -s "$TEMP_SCRIPT" ]; then
      # 检查下载的脚本是否有效
      if bash -n "$TEMP_SCRIPT" 2>/dev/null; then
        chmod +x "$TEMP_SCRIPT"
        # 获取当前脚本路径
        local CURRENT_SCRIPT="$0"
        if [ "$CURRENT_SCRIPT" = "bash" ] || [ "$CURRENT_SCRIPT" = "-bash" ]; then
          CURRENT_SCRIPT="./deploy-gcg-server.sh"
        fi

        # 备份当前脚本
        cp "$CURRENT_SCRIPT" "${CURRENT_SCRIPT}.backup"

        # 替换脚本
        cp "$TEMP_SCRIPT" "$CURRENT_SCRIPT"
        rm -f "$TEMP_SCRIPT"

        echo "✓ 部署脚本更新完成"
        echo "提示：脚本已更新，请重新运行脚本以确保使用最新版本"
        echo "如果更新后出现问题，可以使用备份文件：${CURRENT_SCRIPT}.backup"
      else
        echo "✗ 下载的脚本语法检查失败，跳过脚本更新" >&2
        rm -f "$TEMP_SCRIPT"
      fi
    else
      echo "✗ 脚本下载失败或文件为空，跳过脚本更新" >&2
    fi
  else
    echo "✗ 无法下载脚本更新，跳过脚本更新" >&2
  fi

  # 检查目录是否存在
  if [ ! -d "$SERVER_DIR" ]; then
    echo "错误：服务端目录 $SERVER_DIR 不存在。请先运行菜单项 2 克隆服务端。" >&2
    return 1
  fi

  if [ ! -d "$CLIENT_DIR" ]; then
    echo "错误：客户端目录 $CLIENT_DIR 不存在。请先运行菜单项 6 克隆客户端。" >&2
    return 1
  fi

  # 更新服务端代码
  echo "正在更新服务端代码..."
  if git -C "$SERVER_DIR" pull; then
    echo "✓ 服务端代码更新完成"
  else
    echo "✗ 服务端代码更新失败" >&2
    return 1
  fi

  # 更新客户端代码
  echo "正在更新客户端代码..."
  if git -C "$CLIENT_DIR" pull; then
    echo "✓ 客户端代码更新完成"
  else
    echo "✗ 客户端代码更新失败" >&2
    return 1
  fi

  # 检查 pm2 是否安装
  if ! command -v pm2 >/dev/null 2>&1; then
    echo "警告：未找到 pm2，跳过服务重启。"
    echo "提示：如果需要重启服务，请手动安装 pm2 或使用其他方式重启服务。"
    return 0
  fi

  # 重启 pm2 服务
  echo "正在重启 pm2 服务..."
  if pm2 restart all; then
    echo "✓ pm2 服务重启完成"
  else
    echo "✗ pm2 服务重启失败，请检查 pm2 状态" >&2
    echo "提示：可以运行 'pm2 list' 查看当前服务状态"
    return 1
  fi

  echo "=== 服务更新完成 ==="
  echo "提示：如果有新的依赖变更，可能需要重新运行 npm install（菜单项 3）"
}

# ----- 组合操作 -----
full_client_build() {
  client_clone_update
  client_download_premake
  client_run_premake
  client_ensure_sqlite
  client_build
  client_move_ygopro
}

full_server_prepare() {
  server_clone_update
  server_npm_install
  server_create_symlink
}

full_deploy_all() {
  if [ "$INSTALL_DEPS" = true ]; then
    install_system_deps
  fi
  full_client_build
  full_server_prepare
}

# ----- 菜单显示与交互 -----
print_menu() {
  cat <<EOF

==== 部署脚本 菜单 ====
Server (服务端):
  2) 克隆/更新 gcgserver
  3) 在 gcgserver 运行 npm install
  4) 在 gcgserver 创建/替换 ygopro 符号链接 -> 指向客户端
  5) 启动 gcgserver (npm start，前台)

Client (客户端):
  6) 克隆/更新 galaxycardgame
  7) 下载 premake5
  8) 用 premake 生成 gmake 文件
  9) 下载/确保 sqlite amalgamation 到 sqlite3/
 10) 构建客户端（make config=release）
 11) 将 bin/release/ygopro 移到项目根 (ygopro)

组合/辅助操作:
  1) 安装系统依赖（sudo apt install ...）
 12) 全量构建客户端（相当于 6,7,8,9,10,11）
 13) 全量部署（客户端构建 + 服务端准备）
 14) 更新服务（git pull + pm2 restart）
  0) 退出

直接运行：输入编号并回车来执行对应步骤（可重复执行）。
EOF
}

requires_dependencies() {
  case "$1" in
    0|1) return 1 ;;
    *) return 0 ;;
  esac
}

ensure_dependencies_for_choice() {
  local choice="$1"
  if requires_dependencies "$choice"; then
    if [ "$DEPENDENCIES_OK" != "true" ]; then
      echo "错误：检测到依赖尚未满足，请先运行菜单项 1 或使用 --install-deps。" >&2
      return 1
    fi
    if ! check_dependencies; then
      DEPENDENCIES_OK="false"
      echo "错误：依赖检查未通过，请先安装缺失的依赖。" >&2
      echo "提示：可以运行菜单项 1 或命令 $0 --install-deps。" >&2
      return 1
    fi
  fi
  return 0
}

# 执行单项函数的映射
run_item() {
  local choice="$1"
  if ! ensure_dependencies_for_choice "$choice"; then
    return 1
  fi
  case "$choice" in
    1) install_system_deps ;;
    2) server_clone_update ;;
    3) server_npm_install ;;
    4) server_create_symlink ;;
    5) server_start ;;
    6) client_clone_update ;;
    7) client_download_premake ;;
    8) client_run_premake ;;
    9) client_ensure_sqlite ;;
    10) client_build ;;
    11) client_move_ygopro ;;
    12) full_client_build ;;
    13) full_deploy_all ;;
    14) update_services ;;
    0) echo "退出。"; exit 0 ;;
    *) echo "无效选项：$choice" ;;
  esac
}

# 如果命令行给了 --run，则直接执行对应编号并退出
if [ -n "$QUICK_RUN" ]; then
  run_item "$QUICK_RUN"
  exit 0
fi

# 交互循环
while true; do
  print_menu
  read -rp "请输入要执行的编号 (0 退出): " CHOICE
  # 允许用户输入多个以空格分隔的编号，一次执行序列
  for num in $CHOICE; do
    run_item "$num"
  done
  echo "操作完成。继续选择或输入 0 退出。"
done
