/*
 * main.cpp —— C++ 多文件示例主程序（翻译单元 1）
 *
 * main.o 中：
 *   - Shape/Circle/Rect 的构造函数、vtable 全部是 UND 符号
 *   - 虚调用生成的代码引用 “vtable@GOTPCREL” 重定位，链接时绑定到 shape.o
 */
#include <iostream>
#include "shape.h"

/* shape.cpp 中定义、未在头文件声明的工厂函数 —— 手工声明 */
Shape *make_default_shape();

/* ---- 本翻译单元的段 ---- */
int         g_run_id     = 1;                       // .data
int         g_hist[256];                            // .bss
const char  g_prog[]     = "cpp_multi demo";        // .rodata

/* 全局对象：其构造函数地址会登记到最终可执行文件的 .init_array */
static Circle g_unit_circle(2.0);                   // .bss/.data + .init_array（LOCAL）

int main()
{
    std::cout << "== " << g_prog << " ==\n";

    Rect r(3.0, 4.0);                               // 构造 → 重定位到 shape.o .text
    Shape *d = make_default_shape();

    Shape *shapes[] = { &g_unit_circle, &r, d };
    g_total_area = 0.0;
    for (Shape *s : shapes) {
        std::cout << "  " << s->name()
                  << " area=" << s->area()           // 虚调用：查 vtable
                  << " (" << s->describe() << ")\n";
        g_total_area += s->area();
    }

    std::cout << "total_area(.bss in shape.o) = " << g_total_area << "\n";
    std::cout << "alive_count = " << Shape::alive_count() << "\n";
    std::cout << "g_shape_seq(.data in shape.o) = " << g_shape_seq << "\n";

    g_hist[0] = static_cast<int>(g_total_area);     // 运行时写 .bss
    delete d;
    return 0;
}
