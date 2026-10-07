#!/usr/bin/env bash
# ==============================================================================
# C / C++ 从预编译到链接的完整流程演示脚本
# 工具链: zig cc / zig c++ (clang 前端, 目标 x86_64-linux-gnu)
#         GNU readelf 2.47 (MSYS2 binutils)
# 产物:   build/ 目录下按 4 个示例分类存放各阶段中间文件
# ==============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
ZIG="$ROOT/tools/zig-x86_64-windows-0.17.0/zig.exe"
RE="$ROOT/tools/binutils/mingw64/bin/readelf.exe"
B="$ROOT/build"
LOG="$B/logs"
TARGET="x86_64-linux-gnu"

# -O0: 不优化, 保持变量与源码一一对应; -g0: 不带调试信息, 使段表干净
# -fno-sanitize=undefined: 关闭 zig cc 默认注入的 UBSan, 保持符号表干净
CFLAGS="-O0 -g0 -Wall -fno-sanitize=undefined"

mkdir -p "$B/c_single" "$B/c_multi" "$B/cpp_single" "$B/cpp_multi" "$LOG"
cd "$ROOT"

step() { echo; echo "############################################################"; echo "## $*"; echo "############################################################"; }

# ==============================================================================
step "1. C 单文件: c_single/main.c"
# ==============================================================================
cd "$ROOT/c_single"
D="$B/c_single"

echo ">>> [1/4] 预处理 (Preprocessing): 展开 #include / #define, 删除注释"
"$ZIG" cc -target "$TARGET" $CFLAGS -E main.c -o "$D/main.i"
wc -l main.c "$D/main.i"   # 对比行数, 直观看到 stdio.h 被展开

echo ">>> [2/4] 编译 (Compilation): C -> x86-64 汇编"
"$ZIG" cc -target "$TARGET" $CFLAGS -S "$D/main.i" -o "$D/main.s"
grep -nE '\.section|\.globl|\.type|\.size|\.zero|\.string|\.long|\.comm' "$D/main.s" | head -40

echo ">>> [3/4] 汇编 (Assembly): .s -> 可重定位目标文件 .o (ELF REL)"
"$ZIG" cc -target "$TARGET" $CFLAGS -c "$D/main.s" -o "$D/main.o"
"$RE" -h "$D/main.o" | grep -E "Type|Machine"

echo ">>> [4/4] 链接 (Linking): .o + libc -> 可执行文件 (ELF EXEC) + 链接映射表 app.map"
"$ZIG" cc -target "$TARGET" $CFLAGS "$D/main.o" -o "$D/app" -Wl,--print-map > "$D/app.map"
"$RE" -h "$D/app" | grep -E "Type|Machine|Entry"
ls -la "$D/app.map"

# ==============================================================================
step "2. C 多文件: c_multi/{main.c, vector.c, vector.h}"
# ==============================================================================
cd "$ROOT/c_multi"
D="$B/c_multi"

echo ">>> [1/4] 预处理: 两个翻译单元各自展开 (main.i / vector.i)"
"$ZIG" cc -target "$TARGET" $CFLAGS -E main.c   -o "$D/main.i"
"$ZIG" cc -target "$TARGET" $CFLAGS -E vector.c -o "$D/vector.i"

echo ">>> [2/4] 编译+汇编: 各自生成独立的目标文件"
"$ZIG" cc -target "$TARGET" $CFLAGS -c main.c   -o "$D/main.o"
"$ZIG" cc -target "$TARGET" $CFLAGS -c vector.c -o "$D/vector.o"

echo "    -- main.o 中的未定义符号 UND (需链接器从 vector.o/libc 解析):"
"$RE" -s -W "$D/main.o" | awk '$5=="GLOBAL" && $7=="UND" {print "  U", $8}' | sort -u | head -20
echo "    -- vector.o 中导出的全局定义 (Ndx: 1=.text 函数, .data/.bss/.rodata=数据):"
"$RE" -s -W "$D/vector.o" | awk '$5=="GLOBAL" && $7!="UND" && $4!="FILE" {printf "  [%s] %s (%s, %sB)\n", $7, $8, $4, $3}' | head -20

echo ">>> [3/4] 归档: 将 vector.o 打包为静态库 libvector.a"
"$ZIG" ar rcs "$D/libvector.a" "$D/vector.o"
ls -la "$D/libvector.a"

echo ">>> [4/4] 链接: main.o + libvector.a -> 可执行文件 + app.map"
"$ZIG" cc -target "$TARGET" $CFLAGS "$D/main.o" -L"$D" -lvector -o "$D/app" -Wl,--print-map > "$D/app.map"
ls -la "$D/app.map"
"$RE" -h "$D/app" | grep -E "Type|Entry"

echo "    -- main.o 的重定位表节选 (链接前, 调用地址是空洞):"
"$RE" -r "$D/main.o" | head -25

# ==============================================================================
step "3. C++ 单文件: cpp_single/main.cpp"
# ==============================================================================
cd "$ROOT/cpp_single"
D="$B/cpp_single"

echo ">>> [1/4] 预处理: 展开 iostream/string 等头文件 (.ii 为 C++ 惯例后缀)"
"$ZIG" c++ -target "$TARGET" $CFLAGS -E main.cpp -o "$D/main.ii"
wc -l main.cpp "$D/main.ii"

echo ">>> [2/4] 编译: C++ -> 汇编 (观察名字修饰与 vtable)"
"$ZIG" c++ -target "$TARGET" $CFLAGS -S "$D/main.ii" -o "$D/main.s"
grep -nE '_ZTV|_ZTI|init_array|\.globl.*_Z' "$D/main.s" | head -30

echo ">>> [3/4] 汇编: -> main.o"
"$ZIG" c++ -target "$TARGET" $CFLAGS -c "$D/main.s" -o "$D/main.o"

echo ">>> [4/4] 链接: -> 可执行文件 + app.map"
"$ZIG" c++ -target "$TARGET" $CFLAGS "$D/main.o" -o "$D/app" -Wl,--print-map > "$D/app.map"
ls -la "$D/app.map"
ls -la "$D/app.map"
"$RE" -h "$D/app" | grep -E "Type|Entry"

# ==============================================================================
step "4. C++ 多文件: cpp_multi/{main.cpp, shape.cpp, shape.h}"
# ==============================================================================
cd "$ROOT/cpp_multi"
D="$B/cpp_multi"

echo ">>> [1/4] 预处理"
"$ZIG" c++ -target "$TARGET" $CFLAGS -E main.cpp  -o "$D/main.ii"
"$ZIG" c++ -target "$TARGET" $CFLAGS -E shape.cpp -o "$D/shape.ii"

echo ">>> [2/4] 编译+汇编: 各自生成 main.o / shape.o"
"$ZIG" c++ -target "$TARGET" $CFLAGS -c main.cpp  -o "$D/main.o"
"$ZIG" c++ -target "$TARGET" $CFLAGS -c shape.cpp -o "$D/shape.o"

echo ">>> [3/4] 归档为静态库 libshape.a (演示 C++ 静态库)"
"$ZIG" ar rcs "$D/libshape.a" "$D/shape.o"

echo ">>> [4/4] 链接: main.o + libshape.a -> 可执行文件 + app.map"
"$ZIG" c++ -target "$TARGET" $CFLAGS "$D/main.o" -L"$D" -lshape -o "$D/app" -Wl,--print-map > "$D/app.map"
ls -la "$D/app.map"
ls -la "$D/app.map"
"$RE" -h "$D/app" | grep -E "Type|Entry"

# ==============================================================================
step "5. readelf 深度解析 (输出保存到 build/logs/)"
# ==============================================================================
for ex in c_single c_multi cpp_single cpp_multi; do
    APP="$B/$ex/app"
    {
      echo "==================== $ex/app ===================="
      echo "----- readelf -h (ELF 头) -----";     "$RE" -h "$APP"
      echo "----- readelf -S (节头表) -----";     "$RE" -S -W "$APP"
      echo "----- readelf -l (程序头/段) -----";  "$RE" -l -W "$APP"
      echo "----- readelf -d (动态段) -----";     "$RE" -d "$APP" || true
    } > "$LOG/${ex}_app_readelf.txt" 2>&1
    for obj in "$B/$ex"/*.o; do
      [ -f "$obj" ] || continue
      {
        echo "==================== $obj ===================="
        echo "----- readelf -h -----"; "$RE" -h "$obj"
        echo "----- readelf -S -W -----"; "$RE" -S -W "$obj"
        echo "----- readelf -r (重定位) -----"; "$RE" -r -W "$obj" | head -80
        echo "----- readelf -s (符号表节选) -----"; "$RE" -s -W "$obj" | head -60
      } > "$LOG/$(basename "$ex")_$(basename "$obj")_readelf.txt" 2>&1
    done
done

# 关键符号归属段验证 (g_counter→.data, g_msg→.rodata, g_bigbuf→.bss ...)
{
  echo "== c_single/app 关键符号 =="
  "$RE" -s -W "$B/c_single/app" | grep -E "g_counter|g_msg|g_bigbuf|g_lut|s_calls|level_name|main$" || true
  echo "== cpp_single/app 关键符号 (修饰名) =="
  "$RE" -s -W "$B/cpp_single/app" | grep -E "g_tick|g_app_name|g_samples|kBanner|_ZTV|_ZTI|_ZN6Sensor|_Z4max3|g_boot_sensor" | head -40 || true
} > "$LOG/key_symbols.txt" 2>&1

echo
echo "全部完成! 产物:"
find "$B" -maxdepth 2 -type f \( -name "app" -o -name "*.o" -o -name "*.a" -o -name "*.i" -o -name "*.ii" -o -name "*.s" -o -name "*.map" \) | sort
echo; echo "readelf 日志: $LOG/"
