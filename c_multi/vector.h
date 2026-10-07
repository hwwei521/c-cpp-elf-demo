/*
 * vector.h —— 简易整型向量库（头文件）
 *
 * 头文件在预处理阶段被“原样展开”进翻译单元：
 *   - 只有声明（函数原型 / extern 变量 / 类型 / 宏）不会产生实体数据
 *   - 实体的定义在 vector.c 中，编译后位于 vector.o 的各个段
 */
#ifndef VECTOR_H
#define VECTOR_H

#include <stddef.h>

#define VECTOR_INIT_CAP 8

typedef struct {
    int   *data;      /* 堆内存指针（运行时 malloc，不属于任何静态段） */
    size_t size;
    size_t cap;
} Vector;

/* extern 声明：告诉编译器“定义在别的 .o 里”，链接器负责解析地址 */
extern int  g_vector_total_created;      /* 定义在 vector.c → .data */
extern const char g_vector_lib_name[];   /* 定义在 vector.c → .rodata */

void vector_init(Vector *v);
void vector_push(Vector *v, int value);
int  vector_sum(const Vector *v);
void vector_free(Vector *v);
void vector_print(const Vector *v);

#endif /* VECTOR_H */
