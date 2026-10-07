#!/usr/bin/env bash
# ==============================================================================
# 使用 MSYS2 (C:\msys64) 的 gcc/g++ 16.2.0 在 Windows 本机编译全部 4 个示例
#   - 生成可直接运行的 .exe (PE 格式)
#   - 每次链接都通过 -Wl,-Map=xxx.map 生成链接映射表
#
# 注意: Windows 链接器 ld.exe 不能处理含中文的路径(Illegal byte sequence),
#       因此本脚本先在 ASCII 临时目录 /tmp/nb 中构建, 完成后把产物拷回
#       项目的 build_native/ 目录(源文件从中文路径读取没有问题)。
#
# 运行方式(两种任选):
#   1) 在 "MSYS2 UCRT64" 窗口中:  cd /h/强化学习/deep_learn/c_cpp_elf_demo && bash build_native.sh
#   2) 在任意 bash 中: /c/msys64/usr/bin/bash -lc 'export PATH=/ucrt64/bin:$PATH; bash /h/强化学习/deep_learn/c_cpp_elf_demo/build_native.sh'
# ==============================================================================
set -euo pipefail

export PATH=/ucrt64/bin:$PATH       # 关键! cc1/ld 依赖 ucrt64/bin 下的 DLL

ROOT="$(cd "$(dirname "$0")" && pwd)"   # 项目目录(可含中文, 仅作源文件读取)
N="$ROOT/build_native"                  # 最终产物存放处
W="/tmp/nb"                             # ASCII 构建工作区

CFLAGS="-O0 -g -Wall"

rm -rf "$W"; mkdir -p "$W/c_single" "$W/c_multi" "$W/cpp_single" "$W/cpp_multi"
mkdir -p "$N"
step() { echo; echo "======== $* ========"; }

gcc --version | head -1
g++ --version | head -1

step "1. C 单文件 (gcc) —— 一条命令走完 预处理/编译/汇编/链接 + map"
gcc $CFLAGS "$ROOT/c_single/main.c" -o "$W/c_single/app.exe" -Wl,-Map="$W/c_single/app.map" 2>&1 | grep -v "unused-variable\|s_hidden\|\^" || true
"$W/c_single/app.exe"

step "2. C 多文件 (gcc 分文件编译 + ar 静态库) + map"
gcc $CFLAGS -c "$ROOT/c_multi/main.c"   -o "$W/c_multi/main.o"
gcc $CFLAGS -c "$ROOT/c_multi/vector.c" -o "$W/c_multi/vector.o"
ar rcs "$W/c_multi/libvector.a" "$W/c_multi/vector.o"
gcc $CFLAGS "$W/c_multi/main.o" -L"$W/c_multi" -lvector -o "$W/c_multi/app.exe" -Wl,-Map="$W/c_multi/app.map"
"$W/c_multi/app.exe"

step "3. C++ 单文件 (g++) + map"
g++ $CFLAGS "$ROOT/cpp_single/main.cpp" -o "$W/cpp_single/app.exe" -Wl,-Map="$W/cpp_single/app.map"
"$W/cpp_single/app.exe"

step "4. C++ 多文件 (g++ 分文件编译 + ar 静态库) + map"
g++ $CFLAGS -c "$ROOT/cpp_multi/main.cpp"  -o "$W/cpp_multi/main.o"
g++ $CFLAGS -c "$ROOT/cpp_multi/shape.cpp" -o "$W/cpp_multi/shape.o"
ar rcs "$W/cpp_multi/libshape.a" "$W/cpp_multi/shape.o"
g++ $CFLAGS "$W/cpp_multi/main.o" -L"$W/cpp_multi" -lshape -o "$W/cpp_multi/app.exe" -Wl,-Map="$W/cpp_multi/app.map"
"$W/cpp_multi/app.exe"

step "拷贝产物回项目目录 build_native/"
cp -r "$W"/c_single "$W"/c_multi "$W"/cpp_single "$W"/cpp_multi "$N/"
ls -la "$N"/*/app.map "$N"/*/app.exe | awk '{print $5, $9}'
echo
echo "查看 map 表: less build_native/c_multi/app.map"
