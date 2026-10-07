/*
 * main.c —— C 多文件示例的主程序（翻译单元 1）
 *
 * 编译时看不到 vector.c 的实现，vector_push 等调用在 main.o 中
 * 只是“未定义符号 (UND)”，并生成重定位条目；链接时由 vector.o 填补。
 */
#include <stdio.h>
#include "vector.h"          /* 预处理阶段被展开到此处 */

/* ---- 本翻译单元自己的段内容 ---- */
int  g_main_seed = 7;                 /* .data */
int  g_main_scratch[512];             /* .bss  */
const char g_title[] = "C multi-file demo";  /* .rodata */

/* 由链接器在 vector.o 中找到定义并绑定地址 */
static int fib_like(int n)            /* .text, LOCAL */
{
    if (n < 2) return n;
    return fib_like(n - 1) + fib_like(n - 2);
}

int main(void)
{
    Vector v;
    vector_init(&v);                  /* → 重定位到 vector.o 的 .text */

    for (int i = 0; i < 12; i++)
        vector_push(&v, fib_like(i) + g_main_seed);

    printf("== %s ==\n", g_title);
    printf("lib: %s\n", g_vector_lib_name);       /* extern → vector.o .rodata */
    vector_print(&v);
    printf("total vectors created: %d\n", g_vector_total_created); /* extern → vector.o .data */

    /* 用一下 .bss 数组，证明运行时可写 */
    for (int i = 0; i < 512; i++) g_main_scratch[i] = i;
    printf("scratch[511] = %d\n", g_main_scratch[511]);

    vector_free(&v);
    return 0;
}
