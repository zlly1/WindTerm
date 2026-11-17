#!/bin/bash
#
# build.sh — 在现代 macOS 上构建仓库内捆绑的 libssh
#
# 背景：src/libssh 基于 libssh 0.9.5（2021 年发布，上游已 EOL）。
#       在 macOS 14+ / Xcode 16+ / OpenSSL 3 上原本无法编译，已修复：
#         1) src/init.c                —— is_ssh_initialized() 缺少 void 原型
#         2) examples/sshnetcat.c      —— cleanup_pcap() 同上
#         3) tests/sftp_stress/main.c  —— signal_stop() / thread() 同上
#         4) CMakeLists.txt            —— cmake_minimum_required 3.3.0 -> 3.10
#                                        （CMake 4.x 已移除对 <3.5 的兼容）
#
# 用法：
#   ./build.sh                  # 默认 arm64，Release
#   ARCH=x86_64 ./build.sh      # 构建 Intel 版
#   BUILD_TYPE=Debug ./build.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$(cd "$SCRIPT_DIR/../../src/libssh" && pwd)"
BUILD_DIR="${BUILD_DIR:-$SCRIPT_DIR/build}"
ARCH="${ARCH:-arm64}"
BUILD_TYPE="${BUILD_TYPE:-Release}"

command -v cmake >/dev/null 2>&1 || { echo "ERROR: 需要 cmake >= 3.10" >&2; exit 1; }

# 优先用 Homebrew 的 openssl@3
OPENSSL_DIR="${OPENSSL_ROOT_DIR:-/opt/homebrew/opt/openssl@3}"
[ -d "$OPENSSL_DIR" ] || OPENSSL_DIR="/usr/local/opt/openssl@3"

echo "==> 源码: $SRC_DIR"
echo "==> 架构: $ARCH | 类型: $BUILD_TYPE"
echo "==> OpenSSL: $OPENSSL_DIR"

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

cmake "$SRC_DIR" \
    -DCMAKE_OSX_ARCHITECTURES="$ARCH" \
    -DOPENSSL_ROOT_DIR="$OPENSSL_DIR" \
    -DCMAKE_BUILD_TYPE="$BUILD_TYPE"

cmake --build . -j"$(sysctl -n hw.ncpu)"

echo ""
echo "==> 产物："
file lib/libssh.dylib 2>/dev/null || true
otool -L lib/libssh.dylib 2>/dev/null | grep -E "ssl|crypto" || true
