---
title: 协程在手，并发不愁
date: 2019-09-20
author: yzrun
layout: post
categories:
- computer
permalink: "/computer/2019/09/20/coroutine.html"
---

- 概念与实现
- 协程的使用
- vs线程进程
- 协程的优点
- kotlin的协程

(2019.09.20在团队的分享)

---

# 概念与实现

- 运行在单线程中的**并发**代码段，或：
- 一种**用户态**的轻量级线程

bonus:

- 并发 vs 并行
- 用户态 vs 内核态

---

# 概念与实现

- **属性**: 拥有自己的**寄存器上下文**和**栈**
- **行为**: 切换时，保存当前状态或恢复之前状态

因此：

- 可不必与特定的线程绑定，可以在一个线程中暂停，并在另一个线程中恢复

bonus: 对比尾递归

---

# 概念与实现

- 有栈协程(Stackful)：有自己的调用栈
- 如`Golang`，栈内存可以根据需要进行扩容和缩容，最小一般为内存页长 4KB。
- 无栈协程(Stackless)：没有自己的调用栈
- 如`Python`、`Kotlin`。上下文通过CPS(continuation-passing-style)保存，在`Kotlin`中，就是一个[Continuation](https://kotlinlang.org/api/latest/jvm/stdlib/kotlin.coroutines.experimental/-continuation/index.html)类，可想像成`Callback`。

bonus: `CPS` vs `Direct Style`

---

# 协程的使用

`python` 版

```python
def consumer(name):
    while True:
        bone = yield  # 接收producer的传参，执行后面代码，直到再次碰到yield后返回producer
        print("\033[31;1m[consumer] %s\033[0m 消费 %s " % (name, bone))

def producer(obj1, obj2):
    obj1.send(None) or obj2.send(None)   # 发None启动消费者
    for n in range(5):
        print("\033[32;1m[producer]\033[0m 生产 %s" % n)
        obj1.send(n) or obj2.send(n)    # 暂停producer，并切换到consumer
        time.sleep(1)
```

bonus: 对比子程序

---

# 协程的使用

单步调试，注意`send`(1)之后跳到了`yield`(2)：

![](/img/201909/coroutine_trace.png)

---

# 协程的使用

`kotlin`版：[playgroud](https://pl.kotl.in/7s9CC8kSa)

```kotlin
val channel = Channel<Int>()

GlobalScope.launch {
  for (x in 1..5) {
    println("[producer] 生产 $x")
    channel.send(x)
  }
}

GlobalScope.launch {
  while (true) {
    println("[consumer] 消费 ${channel.receive()}")
  }
}
```

bonus: 为何`python`和`kotlin`版输出不同？

---

# 协程的使用

![](/img/201909/pipe.jpg)

---

# 协程的使用

> 子程序就是协程的一种特例。 —— Donald Knuth

或者说，协程是子程序的泛化。

### *为什么?*

---

# vs 线程、进程

- **进程** 应用程序的启动实例，有代码和打开的文件资源、数据资源、独立的内存空间。最小的资源管理单元。
- **线程** 从属于进程，有自己的栈空间。最小的执行单元。

表面看它们是语言特性，本质却是操作系统能力，通过API暴露给用户使用。

---

# vs 线程、进程

#

---

# vs 线程、进程

#

---

# vs 线程、进程

- 谁来调度
- 何时切换

线程/进程是os通过调度算法，保存当前的上下文实现暂停，重新开始的地方不可预期。每次CPU计算的指令数量和代码跑过的CPU时间有关，跑到os分配的cpu时间到达后就会被os强制挂起。

`Coroutine`是编译器的魔术，通过插入相关的代码使得代码段能够实现分段式的执行，重新开始的地方是`yield`关键字指定的，一次一定会运行到`yield`语句，所以本质是程序员决定何时挂起。

---

# 协程的优点

```kotlin
  // 可以轻松执行以下代码：
  for (i in 1..1000_000) {
    GlobalScope.launch {
      for (x in 1..300000) {
        println("${Thread.currentThread().name} is busy calculating")
      }
    }
  }

  // 视机器配置，可能无法运行下面代码：
  for (i in 1..1000_000) {
    Thread {
      for (x in 1..300000) {
        println("${Thread.currentThread().name} is busy calculating")
      }
    }.start()
  }
```

---

# 协程的优点

### 开销小

线程的时间成本可以拆解为：

- **切换本身**的开销，主要是**寄存器保存和恢复**的成本，可腾挪的余地非常有限；
- 执行体的**调度**开销，主要是如何在大量已**准备好的执行体中选出谁获得**执行权；
- 执行体之间的**同步与互斥**成本。

线程的空间成本可以拆解为：

- 执行体的**执行状态**；
- TLS（线程**局部存储**）；
- 执行体的**堆栈**。

显然，上述成本的比重各不相同。

- 默认情况下Linux 线程在数MB 左右，其中最大的成本是堆栈。如果一个线程 1MB，那么有 1000 个线程就已经到 GB 级别了。
- 执行体的调度开销，以及执行体之间的同步与互斥成本，也是一个不可忽略的成本。单位成本看起来不大，但扛不住次数太多。

[for core2 and modern Linux context switch may cost 5-7 microseconds.](http://web.eece.maine.edu/~vweaver/projects/perf_events/overhead/fastpath2013_perfevents.pdf#page=4)

bonus: 每秒多少cs是合理的？

### 不易出错

- 共享变量的同步锁

线程的任务分配是**抢占式**，存在共享变量时，需要使用锁来保证线程间数据安全。
协程间任务分配是**分发式**，本身无此问题，但**如果运行在多线程中，依然有问题**。

No silver bullet

---

# 协程的应用

协程主要应用场景是高性能的**网络服务**。

- 来自客户端的请求包和服务器的返回包，都是网络IO；
- 过程中，需要访问存储来保存和读取自身的状态，也涉及本地或网络IO。

如果用多线程来实现，如上所述，成本高，易出错。

---

# Kotlin协程

```kotlin
public fun CoroutineScope.launch(
    context: CoroutineContext = EmptyCoroutineContext,
    start: CoroutineStart = CoroutineStart.DEFAULT,
    block: suspend CoroutineScope.() -> Unit
): Job
```

`CoroutineContext`: 可以理解为协程的上下文，其中一个实现`CoroutineDispatcher`支持4种线程模式：

- Dispatchers.Default, 默认线程池, `CPU-heavy`任务
- [Dispatchers.IO](https://kotlin.github.io/kotlinx.coroutines/kotlinx-coroutines-core/kotlinx.coroutines/-dispatchers/-i-o.html), 适合`IO-heavy`任务
- Dispatchers.Main, 主线程
- Dispatchers.Unconfined, 没指定，就是在当前线程

```kotlin
import kotlinx.coroutines.*

fun main() {
    GlobalScope.launch { // launch a new coroutine in background and continue
        delay(1000L) // non-blocking delay for 1 second (default time unit is ms)
        println("World!") // print after delay
    }
    println("Hello,") // main thread continues while coroutine is delayed
    Thread.sleep(2000L) // block main thread for 2 seconds to keep JVM alive
}
```

---

# 参考资料

- [Kotlin Coroutines Design Proposal](https://github.com/Kotlin/KEEP/blob/master/proposals/coroutines.md)
- [Kotlin Coroutine Reference](https://kotlinlang.org/docs/reference/coroutines/basics.html)
- [Shared mutable state and concurrency](https://kotlinlang.org/docs/reference/coroutines/shared-mutable-state-and-concurrency.html)
- [What does the “yield” keyword do](https://stackoverflow.com/questions/231767/what-does-the-yield-keyword-do)
- [Deep Dive into Coroutines on JVM](https://www.youtube.com/watch?v=YrrUCSi72E8)
- [协程及Python中的协程](https://www.cnblogs.com/zingp/p/5911537.html)
- [kotlin - Coroutine 协程](https://www.jianshu.com/p/76d2f47b900d)
- [从Java视角理解CPU上下文切换](http://www.itboth.com/d/J3uE7v/context-cpu-switch-context-switch-java)
