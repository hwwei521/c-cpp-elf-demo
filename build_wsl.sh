#!/usr/bin/env bash
# ==============================================================================
# 【WSL Ubuntu 版】C/C++ 从预编译到链接的完整流程 —— 使用真正的 Linux gcc/g++
# 与 build.sh(zig交叉) 完全同构, 但:
#   - 编译器: gcc/g++ (Ubuntu apt 安装)
#   - 链接器: GNU ld (支持 -Wl,-Map= 生成映射表)
#   - 产物:   原生 Linux ELF, 可以直接运行!
# 用法: 在 WSL Ubuntu 中执行  bash build_wsl.sh
# ==============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
B="$ROOT/build_wsl"
LOG="$B/logs"
CFLAGS="-O0 -g0 -Wall"          # 与文档一致的干净选项

mkdir -p "$B/c_single" "$B/c_multi" "$B/cpp_single" "$B/cpp_multi" "$LOG"
step() { echo; echo "############################################################"; echo "## $*"; echo "############################################################"; }

gcc --version | head -1
g++ --version | head -1
readelf --version | head -1

# ==============================================================================
step "1. C 单文件"
# ==============================================================================
cd "$ROOT/c_single"; D="$B/c_single"
echo ">>> [1/4] 预处理"; gcc $CFLAGS -E main.c -o "$D/main.i"; wc -l main.c "$D/main.i"
echo ">>> [2/4] 编译";   gcc $CFLAGS -S "$D/main.i" -o "$D/main.s"
grep -cE '^\s*\.' "$D/main.s" | xargs echo "    汇编指令数:"
echo ">>> [3/4] 汇编";   gcc $CFLAGS -c "$D/main.s" -o "$D/main.o"
readelf -h "$D/main.o" | grep -E "Type|Machine"
echo ">>> [4/4] 链接 (生成 map 表)"
gcc $CFLAGS "$D/main.o" -o "$D/app" -Wl,-Map="$D/app.map"
readelf -h "$D/app" | grep -E "Type|Entry"
echo ">>> 运行:"; "$D/app"

# ==============================================================================
step "2. C 多文件 + 静态库"
# ==============================================================================
cd "$ROOT/c_multi"; D="$B/c_multi"
echo ">>> [1/4] 预处理"
gcc $CFLAGS -E main.c -o "$D/main.i"; gcc $CFLAGS -E vector.c -o "$D/vector.i"
echo ">>> [2/4][3/4] 编译+汇编"
gcc $CFLAGS -c main.c -o "$D/main.o"; gcc $CFLAGS -c vector.c -o "$D/vector.o"
echo "    -- main.o 未定义符号(UND):"
readelf -s -W "$D/main.o" | awk '$5=="GLOBAL" && $7=="UND" {print "      U", $8}' | sort -u | head -12
echo ">>> [3.5/4] 归档静态库"; ar rcs "$D/libvector.a" "$D/vector.o"; ls -la "$D/libvector.a"
echo ">>> [4/4] 链接 (生成 map 表)"
gcc $CFLAGS "$D/main.o" -L"$D" -lvector -o "$D/app" -Wl,-Map="$D/app.map"
echo "    -- map 中静态库成员抽取记录:"
grep -A2 "Archive member included" "$D/app.map" | head -5
echo ">>> 运行:"; "$D/app"

# ==============================================================================
step "3. C++ 单文件"
# ==============================================================================
cd "$ROOT/cpp_single"; D="$B/cpp_single"
echo ">>> [1/4] 预处理"; g++ $CFLAGS -E main.cpp -o "$D/main.ii"; wc -l main.cpp "$D/main.ii"
echo ">>> [2/4] 编译";   g++ $CFLAGS -S "$D/main.ii" -o "$D/main.s"
grep -nE '_ZTV|init_array' "$D/main.s" | head -6
echo ">>> [3/4] 汇编";   g++ $CFLAGS -c "$D/main.s" -o "$D/main.o"
echo ">>> [4/4] 链接 (生成 map 表)"
g++ $CFLAGS "$D/main.o" -o "$D/app" -Wl,-Map="$D/app.map"
echo ">>> 运行:"; "$D/app"

# ==============================================================================
step "4. C++ 多文件 + 静态库"
# ==============================================================================
cd "$ROOT/cpp_multi"; D="$B/cpp_multi"
echo ">>> [1/4] 预处理"
g++ $CFLAGS -E main.cpp -o "$D/main.ii"; g++ $CFLAGS -E shape.cpp -o "$D/shape.ii"
echo ">>> [2/4][3/4] 编译+汇编"
g++ $CFLAGS -c main.cpp -o "$D/main.o"; g++ $CFLAGS -c shape.cpp -o "$D/shape.o"
echo ">>> [3.5/4] 归档静态库"; ar rcs "$D/libshape.a" "$D/shape.o"
echo ">>> [4/4] 链接 (生成 map 表)"
g++ $CFLAGS "$D/main.o" -L"$D" -lshape -o "$D/app" -Wl,-Map="$D/app.map"
echo ">>> 运行:"; "$D/app"

# ==============================================================================
step "5. readelf 深度解析 (日志存 $LOG)"
# ==============================================================================
for ex in c_single c_multi cpp_single cpp_multi; do
    APP="$B/$ex/app"
    { echo "===== readelf -h ====="; readelf -h "$APP"
      echo "===== readelf -S -W ====="; readelf -S -W "$APP"
      echo "===== readelf -l -W ====="; readelf -l -W "$APP"
      echo "===== readelf -d ====="; readelf -d "$APP"
      echo "===== readelf -s (关键符号) ====="; readelf -s -W "$APP" | head -80 || true
    } > "$LOG/${ex}_app.txt" 2>&1
    for obj in "$B/$ex"/*.o; do
      { echo "===== readelf -h ====="; readelf -h "$obj"
        echo "===== readelf -S -W ====="; readelf -S -W "$obj"
        echo "===== readelf -r -W ====="; readelf -r -W "$obj" | head -60 || true
      } > "$LOG/${ex}_$(basename "$obj").txt" 2>&1
    done
done
{ echo "== c_single 关键符号 =="; readelf -s -W "$B/c_single/app" | grep -E "g_counter|g_msg|g_bigbuf|g_lut|s_calls|level_name| main$" || true
  echo "== cpp_single 关键符号 =="; readelf -s -W "$B/cpp_single/app" | grep -E "g_tick|g_app_name|g_samples|_ZTV6Sensor|_ZTV10TempSensor|_Z4max3|g_boot_sensor" | head -20 || true
  echo "== cpp_multi 关键符号 =="; readelf -s -W "$B/cpp_multi/app" | grep -E "g_shape_seq|g_total_area|_ZTV5Shape|_ZTV6Circle|_ZTV4Rect|g_unit_circle" | head -15 || true
} > "$LOG/key_symbols.txt" 2>&1

echo; echo "全部完成! 产物与 map 表:"
find "$B" -maxdepth 2 -type f \( -name app -o -name "*.map" -o -name "*.o" -o -name "*.a" \) | sort
