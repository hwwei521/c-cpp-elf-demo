/*
 * shape.cpp —— 图形库实现（翻译单元 2）
 *
 * 单独编译为 shape.o：
 *   - 包含本文件所有实体的段（.text/.data/.rodata/.bss/.data.rel.ro）
 *   - 对 std::string 等库符号的引用是 UND（未定义），等待链接
 *   - vtable 里的函数地址在链接前是重定位条目（.rela.data.rel.ro）
 */
#include "shape.h"
#include <cmath>
#include <cstdio>

/* ===================== .data / .bss ===================== */
int    Shape::s_alive       = 0;             // 静态成员定义 → .data
int    g_shape_seq          = 1000;          // → .data
double g_total_area;                         // → .bss

/* ===================== .rodata ===================== */
const char Shape::s_lib_tag[] = "shape-lib"; // → .rodata
static const double kUnitScale = 1.0;        // → .rodata（LOCAL）

/* ===================== .text ===================== */
Shape::Shape(std::string name)               // 修饰名 _ZN5ShapeC2ENSt7__cxx1112basic_stringIcSt11char_traits...
    : name_(std::move(name))
{
    s_alive++;
    g_shape_seq++;
}

const char *Shape::describe() const
{
    return "generic shape";
}

int Shape::alive_count() { return s_alive; }

Circle::Circle(double r) : Shape("circle"), radius_(r) {}

double Circle::area() const
{
    return M_PI * radius_ * radius_ * kUnitScale;   // 调用 libm → UND 符号
}

const char *Circle::describe() const
{
    return "circle: pi*r^2";
}

Rect::Rect(double w, double h) : Shape("rect"), w_(w), h_(h) {}

double Rect::area() const
{
    return w_ * h_;
}

/* 工厂函数：演示跨文件调用的普通符号 */
Shape *make_default_shape()
{
    return new Circle(1.0);
}
