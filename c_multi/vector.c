/*
 * vector.c —— 向量库实现（独立翻译单元）
 *
 * 单独编译成 vector.o 时：
 *   - 本文件定义的实体分别进入 .text/.data/.rodata/.bss
 *   - 对 main.c 中符号的引用（如果有）记录在重定位表 .rela.text 中
 *   - 链接阶段由链接器把两个 .o 的同名段“拼接”成最终可执行文件的段
 */
#include "vector.h"
#include <stdio.h>
#include <stdlib.h>

/* ---- .data：已初始化全局变量（被 main.c 用 extern 引用）---- */
int g_vector_total_created = 0;

/* ---- .rodata：常量数组 ---- */
const char g_vector_lib_name[] = "mini-vector-lib v1.0";

/* ---- .bss：未初始化全局变量 ---- */
static size_t s_total_pushes;      /* static → 符号表中标记 LOCAL */

/* ---- .text ---- */
void vector_init(Vector *v)
{
    v->data = malloc(VECTOR_INIT_CAP * sizeof(int));
    if (!v->data) { perror("malloc"); exit(1); }
    v->size = 0;
    v->cap  = VECTOR_INIT_CAP;
    g_vector_total_created++;
}

void vector_push(Vector *v, int value)
{
    if (v->size == v->cap) {                 /* 扩容 */
        v->cap *= 2;
        v->data = realloc(v->data, v->cap * sizeof(int));
        if (!v->data) { perror("realloc"); exit(1); }
    }
    v->data[v->size++] = value;
    s_total_pushes++;                        /* .bss 变量运行时自增 */
}

int vector_sum(const Vector *v)
{
    int s = 0;
    for (size_t i = 0; i < v->size; i++) s += v->data[i];
    return s;
}

void vector_free(Vector *v)
{
    free(v->data);
    v->data = NULL;
    v->size = v->cap = 0;
}

void vector_print(const Vector *v)
{
    printf("vector(%zu/%zu, pushes=%zu): [", v->size, v->cap, s_total_pushes);
    for (size_t i = 0; i < v->size; i++) printf("%d%s", v->data[i], i + 1 < v->size ? ", " : "");
    printf("]  sum=%d\n", vector_sum(v));
}
