/*
 * shape.h —— 图形库接口（被两个翻译单元共同包含）
 *
 * 预处理后，main.cpp 与 shape.cpp 各自持有一份完全相同的声明。
 * 类定义本身不产生实体数据；vtable/成员函数的实体在 shape.o 中生成，
 * 链接时 main.o 通过未定义符号 + 重定位找到它们。
 */
#ifndef SHAPE_H
#define SHAPE_H

#include <string>

/* 抽象基类：vtable 将出现在 shape.o 的 .data.rel.ro */
class Shape {
public:
    explicit Shape(std::string name);
    virtual ~Shape() = default;
    virtual double area() const = 0;          // 纯虚
    virtual const char *describe() const;     // 普通虚函数

    const std::string &name() const { return name_; }   // inline → 各 .o 的 .text（弱符号）
    static int alive_count();                            // 静态成员函数

private:
    std::string name_;
    static int s_alive;                                  // 静态成员声明
    static const char s_lib_tag[];                       // const 静态成员（类内初始化）
};

class Circle : public Shape {
public:
    explicit Circle(double r);
    double area() const override;
    const char *describe() const override;
private:
    double radius_;
};

class Rect : public Shape {
public:
    Rect(double w, double h);
    double area() const override;
private:
    double w_, h_;
};

/* 跨文件 extern 全局变量：定义在 shape.cpp */
extern int    g_shape_seq;                  // .data
extern double g_total_area;                 // .bss（零初始化）

#endif /* SHAPE_H */
