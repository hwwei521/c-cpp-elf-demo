/*
 * ============================================================================
 * C++ 单文件示例 —— 除 C 的段之外，重点展示 C++ 特有的 ELF 内容
 * ============================================================================
 *   .text        成员函数 / 模板实例 / 编译器生成函数
 *   .rodata      字符串字面量、const 常量、（部分）虚表
 *   .data        已初始化全局对象、静态数据成员
 *   .bss         未初始化全局对象（POD 类型零初始化）
 *   .init_array  全局对象构造函数指针表（main 之前执行）★C++ 特有
 *   .data.rel.ro 虚函数表 vtable、typeinfo（重定位后只读）★C++ 特有
 *   名字修饰      符号表中可见 _Z... 形式的 mangled name
 */
#include <iostream>
#include <string>

/* ===================== .data / .bss：全局对象 ===================== */
int          g_tick       = 100;              // .data（POD，值直接写入文件）
std::string  g_app_name   = "cpp_single";     // .data + .init_array（构造函数）
double       g_samples[128];                  // .bss （零初始化，不占文件体积）

/* ===================== .rodata：常量 ===================== */
const char   kBanner[]   = "C++ single-file ELF demo";
const double kPi         = 3.14159265358979;

/* ===================== 类：虚函数 → vtable (.data.rel.ro) ===================== */
class Sensor {
public:
    Sensor() : id_(++s_created) {}            // 构造函数 → .text（修饰名 _ZN6SensorC1Ev）
    virtual ~Sensor() = default;              // 虚析构 → vtable 条目
    virtual const char *kind() const = 0;     // 纯虚 → vtable 中指向 __cxa_pure_virtual
    virtual double read() const;              // 虚函数 → .text + vtable 条目
    int id() const { return id_; }

    static int instance_count() { return s_created; }  // inline → .text

private:
    int id_;
    static int s_created;                     // 静态成员声明
};
int Sensor::s_created = 0;                    // 静态成员定义 → .data

double Sensor::read() const { return id_ * kPi; }   // .text

class TempSensor : public Sensor {            // 派生类：另一张 vtable
public:
    const char *kind() const override { return "temperature"; }  // inline 虚函数
    double read() const override;
};
double TempSensor::read() const { return 25.0 + id(); }

/* ===================== 全局对象：构造函数指针进入 .init_array ===================== */
TempSensor g_boot_sensor;                     // main 之前必须构造 → .init_array

/* ===================== 模板：实例化发生在编译期，代码进 .text ===================== */
template <typename T>
T max3(T a, T b, T c)
{
    T m = a > b ? a : b;
    return m > c ? m : c;
}

/* ===================== .text ===================== */
static void report(const Sensor &s)           // static → 符号 LOCAL
{
    std::cout << "  sensor#" << s.id()
              << " kind=" << s.kind()          // 通过 vtable 动态分派
              << " read=" << s.read() << "\n";
}

int main()
{
    std::cout << kBanner << "\n";
    std::cout << "app_name(.data+init_array): " << g_app_name << "\n";

    report(g_boot_sensor);                     // 全局对象（.init_array 已构造）
    TempSensor local;
    report(local);

    /* 两次模板实例化 → .text 中两份不同的修饰符号
       _Z4max3IiET_S0_S0_S0_  与  _Z4max3IdET_S0_S0_S0_ */
    std::cout << "max3<int>(3,9,4)    = " << max3<int>(3, 9, 4) << "\n";
    std::cout << "max3<double>(1.5,9.25,3.75) = " << max3<double>(1.5, 9.25, 3.75) << "\n";

    g_samples[0] = g_tick;                     // .bss 运行时写入
    std::cout << "s_created(.data static member) = " << Sensor::instance_count() << "\n";
    return 0;
}
