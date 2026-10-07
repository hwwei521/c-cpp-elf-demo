/*
 * ============================================================================
 * C 单文件示例 —— 覆盖 ELF 的各个典型段
 * ============================================================================
 * 每个全局对象都被刻意放置到不同的段中，便于用 readelf 观察：
 *   .text    代码段（函数机器指令）
 *   .rodata  只读数据段（const 常量、字符串字面量）
 *   .data    已初始化全局/静态变量（可读写）
 *   .bss     未初始化（或初始化为 0）的全局/静态变量（不占文件体积）
 */
#include <stdio.h>

/* ========================= .data 段：已初始化的全局变量 ========================= */
int    g_counter   = 42;                 /* 4 字节，SHT_PROGBITS，可写 */
double g_ratio     = 3.14159;            /* 8 字节 */
char   g_name[]    = "deep_learn";       /* 数组初始化 → 内容拷贝进 .data */
int    g_array[4]  = {1, 2, 3, 4};

/* ========================= .bss 段：未初始化的全局变量 ========================== */
int    g_bigbuf[4096];                   /* 16 KB，只记录大小，不占 ELF 文件空间 */
char   g_flag;
double g_result;

/* ========================= .rodata 段：只读常量 ================================= */
const char  g_msg[]      = "Hello, ELF sections!";   /* const 数组 → .rodata */
const int   g_lut[8]     = {1, 1, 2, 3, 5, 8, 13, 21};
const char *const g_pp   = "pointer to const string";/* 指针本身也是 const */
/* 注意：普通 char *p = "str"; 中 p 在 .data，"str" 在 .rodata */
char *g_ptr_to_literal   = "literal in rodata";

/* ========================= 文件作用域 static 变量 =============================== */
static int s_calls   = 0;                /* 已初始化 → .data（符号为 LOCAL） */
static int s_hidden;                     /* 未初始化 → .bss  （符号为 LOCAL） */
static const char s_tag[] = "[static]";  /* → .rodata */

/* ========================= .text 段：函数 ===================================== */
int add(int a, int b)
{
    return a + b;
}

static int next_call_id(void)            /* static 函数 → .text，符号 LOCAL */
{
    s_calls++;
    return s_calls;
}

/* switch 跳转表演示：编译器可能生成 .rodata 中的跳转表 */
const char *level_name(int level)
{
    switch (level) {
    case 0:  return "zero";
    case 1:  return "one";
    case 2:  return "two";
    case 3:  return "three";
    default: return "unknown";
    }
}

void compute(void)
{
    g_result = 0.0;
    for (int i = 0; i < 4096; i++) {
        g_bigbuf[i] = i * 2;
        g_result += g_bigbuf[i] * g_ratio;
    }
    g_result += add(g_counter, g_array[3]);
}

int main(void)
{
    printf("%s %s\n", s_tag, g_msg);
    printf("call id      = %d\n", next_call_id());
    printf("g_counter    = %d\n", g_counter);
    printf("g_name       = %s\n", g_name);
    printf("g_ptr        = %s\n", g_ptr_to_literal);
    printf("lut[7]       = %d\n", g_lut[7]);
    printf("level(2)     = %s\n", level_name(2));

    compute();
    printf("g_result     = %.2f (bss var written at runtime)\n", g_result);
    printf("g_flag       = %d (bss auto zero-init)\n", (int)g_flag);
    return 0;
}
