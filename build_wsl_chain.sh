#!/usr/bin/env bash
# ==============================================================================
# 【WSL Ubuntu · 严格链式版】C/C++ 四阶段编译全流程实测 (gcc/g++)
#
#   阶段① 预编译   main.c    --[ gcc -E ]--> main.i    (展开 #include / 替换宏 / 删注释)
#   阶段② 编译     main.i    --[ gcc -S ]--> main.s    (C → 汇编; 输入必须是①的产物)
#   阶段③ 汇编     main.s    --[ gcc -c ]--> main.o    (汇编 → 机器码 REL; 输入是②的产物)
#   阶段③.5 归档   *.o       --[ ar rcs ]--> lib*.a    (多文件项目: 打静态库+符号索引)
#   阶段④ 链接     main.o(+lib*.a) --[ gcc -Wl,-Map ]--> app  (DYN/PIE 可执行)
#
# 严格约定: 每个阶段的输入永远是上一阶段的产物文件, 绝不从源码跨级重编。
# 产物目录: build_chain/    日志: build_chain/logs/
# 用法: bash build_wsl_chain.sh
# ==============================================================================
set -uo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
B="$ROOT/build_chain"
LOG="$B/logs"
CFLAGS="-O0 -g0 -Wall"

rm -rf "$B"
mkdir -p "$B/c_single" "$B/c_multi" "$B/cpp_single" "$B/cpp_multi" "$LOG"

hr()   { echo "----------------------------------------------------------------"; }
step() { echo; echo "############################################################"; echo "## $*"; echo "############################################################"; }
trun() { echo "    \$ $*"; local t0 t1 rc; t0=$(date +%s%N); "$@"; rc=$?; t1=$(date +%s%N); echo "      [耗时 $(( (t1-t0)/1000000 )) ms, exit=$rc]"; }
finfo(){ printf "      %-14s %8s 行 %10s B\n" "$(basename "$1")" "$(wc -l < "$1" | tr -d ' ')" "$(stat -c %s "$1")"; }
bsize(){ printf "      %-14s %21s B\n" "$(basename "$1")" "$(stat -c %s "$1")"; }

uname -srmo
gcc --version | head -1
g++ --version | head -1
readelf --version | head -1
ar --version | head -1
echo "CFLAGS = $CFLAGS"

# ==============================================================================
step "项目1: C 单文件 (c_single) —— 各类变量刻意分布在不同段"
# ==============================================================================
cd "$ROOT/c_single"; D="$B/c_single"

echo ">>> 阶段① 预编译: main.c → main.i"
trun gcc $CFLAGS -E main.c -o "$D/main.i"
finfo main.c; finfo "$D/main.i"
echo "      验证: main.i 中残留 #include/#define 数 = $(grep -cE '^[[:space:]]*#[[:space:]]*(include|define)' "$D/main.i" || true) (应为 0)"
echo "      验证: stdio.h 已展开 → $(grep -c 'extern int printf' "$D/main.i" || true) 处 printf 声明"

echo ">>> 阶段② 编译: main.i → main.s   (输入 = ①的产物)"
trun gcc $CFLAGS -S "$D/main.i" -o "$D/main.s"
finfo "$D/main.s"
echo "      真机器指令(制表符开头且非.伪指令): $(awk '/^\t/ && substr($0,2,1)!="."' "$D/main.s" | wc -l) 条"
echo "      伪指令+局部标签(.开头行):          $(grep -cE '^[[:space:]]*\.' "$D/main.s" || true) 行"
echo "      -- 符号归属证据(.s 片段):"
grep -nE '(g_counter|g_bigbuf|g_msg|g_lut|s_calls):|\.globl[[:space:]]+(g_counter|g_msg)|\.local[[:space:]]+s_calls|\.zero[[:space:]]+16384|\.section[[:space:]]+\.(data|bss|rodata|text)' "$D/main.s" | head -22 | sed 's/^/      /'

echo ">>> 阶段③ 汇编: main.s → main.o   (输入 = ②的产物)"
trun gcc $CFLAGS -c "$D/main.s" -o "$D/main.o"
bsize "$D/main.o"
readelf -h "$D/main.o" | grep -E "Type|Machine" | sed 's/^ */      /'
echo "      -- main.o 关键节(size -A):"
size -A "$D/main.o" | awk '$1 ~ /^\.(text|data|bss|rodata|rela)/ {printf "      %-22s %8s B\n", $1, $2}'
echo "      -- 重定位条目数: $(readelf -r -W "$D/main.o" | grep -c R_X86_64 || true) (printf 等待链接时定址)"

echo ">>> 阶段④ 链接: main.o → app + app.map   (输入 = ③的产物)"
trun gcc $CFLAGS "$D/main.o" -o "$D/app" -Wl,-Map="$D/app.map"
bsize "$D/app"
readelf -h "$D/app" | grep -E "Type|Entry" | sed 's/^ */      /'
echo "      -- app 关键节(size -A):"
size -A "$D/app" | awk '$1 ~ /^\.(text|data|bss|rodata|interp|dynamic|init_array)/ {printf "      %-22s %8s B\n", $1, $2}'
echo "      -- size 总计(text/data/bss): $(size "$D/app" | tail -1)"
echo "      -- 教学点: .bss($(size -A "$D/app" | awk '$1==".bss"{print $2}') B)只记大小不占文件 → app 文件仅 $(stat -c %s "$D/app") B"
echo ">>> 运行 app:"
"$D/app" | sed 's/^/      /'

# ==============================================================================
step "项目2: C 多文件 + 静态库 (c_multi) —— 两个翻译单元各自走完①②③再归档④"
# ==============================================================================
cd "$ROOT/c_multi"; D="$B/c_multi"

for src in main.c vector.c; do
  base="${src%.c}"
  echo ">>> 翻译单元 [$src]: 链式 $src → $base.i → $base.s → $base.o"
  trun gcc $CFLAGS -E "$src"           -o "$D/$base.i"
  trun gcc $CFLAGS -S "$D/$base.i"     -o "$D/$base.s"
  trun gcc $CFLAGS -c "$D/$base.s"     -o "$D/$base.o"
  finfo "$src"; finfo "$D/$base.i"; finfo "$D/$base.s"; bsize "$D/$base.o"
  case $base in
    main)   echo "      头文件展开证据: main.i 含 vector.h 的 extern 声明 $(grep -c 'extern int g_vector_total_created' "$D/main.i" || true) 处";;
    vector) echo "      宏替换证据: vector.i 中 VECTOR_INIT_CAP 已变 8 → 'malloc(8 *' $(grep -c 'malloc(8 \*' "$D/vector.i" || true) 处";;
  esac
  hr
done

echo ">>> 链接前符号账本 —— main.o 的欠账(UND, 待④解析):"
readelf -s -W "$D/main.o" | awk '$5=="GLOBAL" && $7=="UND" {print "      U " $8}' | sort -u
echo ">>> vector.o 的存货(已定义 GLOBAL 符号, 供④解析):"
readelf -s -W "$D/vector.o" | awk '$5=="GLOBAL" && $7!="UND" {print "      " $4 " " $8 " (节" $7 ")"}' | sort -u

echo ">>> 阶段③.5 归档: vector.o → libvector.a   (输入 = ③的产物)"
trun ar rcs "$D/libvector.a" "$D/vector.o"
bsize "$D/libvector.a"
echo "      ar t 成员: $(ar t "$D/libvector.a")"
echo "      -- 归档符号索引(nm -s 摘录):"
nm -s "$D/libvector.a" | head -12 | sed 's/^/      /'

echo ">>> 阶段④ 链接: main.o + libvector.a → app   (输入 = ③/③.5 的产物)"
trun gcc $CFLAGS "$D/main.o" -L"$D" -lvector -o "$D/app" -Wl,-Map="$D/app.map"
readelf -h "$D/app" | grep -E "Type|Entry" | sed 's/^ */      /'
echo "      -- map 表: 链接器从静态库抽取成员的记录:"
grep -A2 "Archive member included" "$D/app.map" | head -4 | sed 's/^/      /'
echo "      -- 跨文件符号最终定址(readelf -s):"
readelf -s -W "$D/app" | awk '$8 ~ /^(vector_init|vector_push|vector_print|vector_sum|vector_free|g_vector_lib_name|g_vector_total_created)$/ {printf "      %-26s addr=0x%-8s size=%-6s 节[%s]\n", $8, $2, $3, $7}'
echo "      -- size 总计: $(size "$D/app" | tail -1)"
echo ">>> 运行 app:"
"$D/app" | sed 's/^/      /'

# ==============================================================================
step "项目3: C++ 单文件 (cpp_single) —— 头文件爆炸 / 名字修饰 / vtable / init_array"
# ==============================================================================
cd "$ROOT/cpp_single"; D="$B/cpp_single"

echo ">>> 阶段① 预编译: main.cpp → main.ii"
trun g++ $CFLAGS -E main.cpp -o "$D/main.ii"
finfo main.cpp; finfo "$D/main.ii"
echo "      膨胀倍数: $(( $(wc -l < "$D/main.ii") / $(wc -l < main.cpp) ))× ($(wc -l < main.cpp) 行 → $(wc -l < "$D/main.ii") 行, iostream/string 全展开)"

echo ">>> 阶段② 编译: main.ii → main.s   (输入 = ①的产物)"
trun g++ $CFLAGS -S "$D/main.ii" -o "$D/main.s"
finfo "$D/main.s"
echo "      -- 名字修饰证据(.s):"
grep -nE '_ZN6Sensor|_ZN10TempSensor|_Z4max3' "$D/main.s" | head -5 | sed 's/^/      /'
echo "      -- vtable 证据(.s):"
grep -nE '_ZTV' "$D/main.s" | head -4 | sed 's/^/      /'
echo "      -- init_array(全局构造) 证据(.s):"
grep -nE 'init_array|_GLOBAL__sub_I' "$D/main.s" | head -4 | sed 's/^/      /'

echo ">>> 阶段③ 汇编: main.s → main.o   (输入 = ②的产物)"
trun g++ $CFLAGS -c "$D/main.s" -o "$D/main.o"
bsize "$D/main.o"
readelf -h "$D/main.o" | grep -E "Type" | sed 's/^ */      /'
echo "      -- WEAK 符号(模板/vtable/inline, 多重定义由链接器去重):"
readelf -s -W "$D/main.o" | awk '$5=="WEAK" && $7!="UND" {print "      W " $8}' | sort -u | head -10
echo "      -- 关键节:"
size -A "$D/main.o" | awk '$1 ~ /^\.(text|data|bss|rodata|init_array|data\.rel\.ro)/ {printf "      %-22s %8s B\n", $1, $2}'

echo ">>> 阶段④ 链接: main.o → app   (输入 = ③的产物)"
trun g++ $CFLAGS "$D/main.o" -o "$D/app" -Wl,-Map="$D/app.map"
readelf -h "$D/app" | grep -E "Type|Entry" | sed 's/^ */      /'
echo "      -- 动态库依赖(readelf -d NEEDED):"
readelf -d "$D/app" | grep NEEDED | sed 's/^ */      /'
echo "      -- 解释器: $(readelf -l -W "$D/app" | grep -A1 INTERP | tail -1 | tr -d ' []')"
echo "      -- C++ 特有符号定址:"
readelf -s -W "$D/app" | awk '$8 ~ /^(_ZTV6Sensor|_ZTV10TempSensor|_Z4max3IiET_S0_S0_S0_|_Z4max3IdET_S0_S0_S0_|g_tick|_Z10g_app_nameB5cxx11|g_samples|_ZN6Sensor9s_createdE)$/ {printf "      %-30s %-7s size=%-6s 节[%s]\n", $8, $5, $3, $7}'
echo "      -- 名字修饰还原(c++filt 示例):"
{ echo '_ZTV10TempSensor'; echo '_ZNK10TempSensor4readEv'; echo '_Z4max3IdET_S0_S0_S0_'; echo '_ZN6Sensor9s_createdE'; } | while read -r m; do printf "      %-28s → %s\n" "$m" "$(echo "$m" | c++filt)"; done
echo "      -- size 总计: $(size "$D/app" | tail -1)"
echo ">>> 运行 app:"
"$D/app" | sed 's/^/      /'

# ==============================================================================
step "项目4: C++ 多文件 + 静态库 (cpp_multi) —— 跨翻译单元的 vtable/构造/extern"
# ==============================================================================
cd "$ROOT/cpp_multi"; D="$B/cpp_multi"

for src in main.cpp shape.cpp; do
  base="${src%.cpp}"
  echo ">>> 翻译单元 [$src]: 链式 $src → $base.ii → $base.s → $base.o"
  trun g++ $CFLAGS -E "$src"           -o "$D/$base.ii"
  trun g++ $CFLAGS -S "$D/$base.ii"    -o "$D/$base.s"
  trun g++ $CFLAGS -c "$D/$base.s"     -o "$D/$base.o"
  finfo "$src"; finfo "$D/$base.ii"; finfo "$D/$base.s"; bsize "$D/$base.o"
  hr
done

echo ">>> 链接前符号账本 —— main.o 的欠账(UND 摘录, C++ 修饰名):"
readelf -s -W "$D/main.o" | awk '$7=="UND" && $8 ~ /^(make_default|_ZN5Shape|_ZN6Circle|_ZN4Rect|_ZTV|_Znwm|g_total|g_shape)/ {print "      U " $8}' | sort -u | head -12
echo ">>> shape.o 的存货(已定义符号摘录):"
readelf -s -W "$D/shape.o" | awk '$7!="UND" && $8 ~ /^(_ZN5Shape|_ZN6Circle|_ZN4Rect|_ZTV|g_total_area|g_shape_seq|make_default)/ {print "      " $5 " " $8}' | sort -u | head -16

echo ">>> 阶段③.5 归档: shape.o → libshape.a   (输入 = ③的产物)"
trun ar rcs "$D/libshape.a" "$D/shape.o"
bsize "$D/libshape.a"; echo "      ar t 成员: $(ar t "$D/libshape.a")"

echo ">>> 阶段④ 链接: main.o + libshape.a → app   (输入 = ③/③.5 的产物)"
trun g++ $CFLAGS "$D/main.o" -L"$D" -lshape -o "$D/app" -Wl,-Map="$D/app.map"
readelf -h "$D/app" | grep -E "Type|Entry" | sed 's/^ */      /'
echo "      -- map 表: 静态库抽取记录:"
grep -A2 "Archive member included" "$D/app.map" | head -4 | sed 's/^/      /'
echo "      -- 跨文件符号最终定址(c++filt 还原):"
readelf -s -W "$D/app" | awk '$8 ~ /^(_ZTV5Shape|_ZTV6Circle|_ZTV4Rect|g_shape_seq|g_total_area|make_default_shape|_ZN6CircleC1Ed)$/ {printf "      %-24s %-7s size=%-6s 节[%s]\n", $8, $5, $3, $7}' | while read -r line; do sym=$(echo "$line" | awk '{print $1}'); printf "%s → %s\n" "$line" "$(echo "$sym" | c++filt)"; done
echo "      -- size 总计: $(size "$D/app" | tail -1)"
echo ">>> 运行 app:"
"$D/app" | sed 's/^/      /'

# ==============================================================================
step "5. 汇总: 四个 app 的段尺寸对比 + readelf 深度日志归档"
# ==============================================================================
echo ">>> 四个可执行文件 size 对比 (text/data/bss/dec):"
printf "      %-12s %8s %8s %8s %10s\n" 项目 text data bss dec
for ex in c_single c_multi cpp_single cpp_multi; do
  size "$B/$ex/app" | tail -1 | awk -v n="$ex" '{printf "      %-12s %8s %8s %8s %10s\n", n, $1, $2, $3, $4}'
done
echo ">>> 四个 app 文件体积 vs .bss 逻辑大小 (零初始化不占磁盘):"
for ex in c_single c_multi cpp_single cpp_multi; do
  printf "      %-12s 文件 %7s B, .bss %7s B\n" "$ex" "$(stat -c %s "$B/$ex/app")" "$(size -A "$B/$ex/app" | awk '$1==".bss"{print $2}')"
done

for ex in c_single c_multi cpp_single cpp_multi; do
  APP="$B/$ex/app"
  { echo "===== readelf -h ====="; readelf -h "$APP"
    echo "===== readelf -S -W ====="; readelf -S -W "$APP"
    echo "===== readelf -l -W ====="; readelf -l -W "$APP"
    echo "===== readelf -d ====="; readelf -d "$APP"
    echo "===== readelf -s -W ====="; readelf -s -W "$APP"
    echo "===== size -A ====="; size -A "$APP"
  } > "$LOG/${ex}_app.txt" 2>&1
  for obj in "$B/$ex"/*.o; do
    { echo "===== readelf -h ====="; readelf -h "$obj"
      echo "===== readelf -S -W ====="; readelf -S -W "$obj"
      echo "===== readelf -r -W ====="; readelf -r -W "$obj"
      echo "===== readelf -s -W ====="; readelf -s -W "$obj"
    } > "$LOG/${ex}_$(basename "$obj").txt" 2>&1
  done
  { echo "== map 摘录: Archive member / 内存配置 =="
    grep -B1 -A3 "Archive member included" "$B/$ex/app.map" 2>/dev/null | head -8
    grep -A12 "^Memory Configuration" "$B/$ex/app.map" | head -14
  } > "$LOG/${ex}_map_extract.txt" 2>&1
done
echo ">>> 日志已归档:"; ls "$LOG" | sed 's/^/      /'

echo; echo "全部完成! 链式产物清单:"
find "$B" -maxdepth 2 -type f \( -name app -o -name "*.i" -o -name "*.ii" -o -name "*.s" -o -name "*.o" -o -name "*.a" -o -name "*.map" \) | sort | sed 's/^/  /'
