---
title: monkey patch in go
date: 2020-06-20
author: yzrun
layout: post
categories:
- computer
permalink: "/computer/2020/06/20/go-monkey-patch.html"
---

## 什么是monkey patch

早前的一个python项目遇到性能瓶颈，试图用对标准库做`monkey
patch`，在不改源码的情况下，用[gevent](http://www.gevent.org/api/gevent.monkey.html)让标准库用上非阻塞IO。
留下的印象是以为在`python`等动态语言里才有`monkey patch`。

偶然看到[bouk/monkey](https://github.com/bouk/monkey)，才发现，`go`语言也可以实现。好奇之下，研究了它的原理。作者有个[博客](https://bou.ke/blog/monkey-patching-in-go/)，讲得很好，但缺了很多细节和过程。于是，从问题源头出发，自己理一遍，收益良多：

- 程序的编译、连接与执行
- `go`工具`compile`与`objdump`
- `go`函数值实现
- plan9汇编
- X86指令、寄存器

## 魔法

简单来说，通过`monkey patch`，以下代码将输出”2”而不是”1”：

```go
package main

func a() int { return 1 }
func b() int { return 2 }

func main() {
  replace(a, b)
  println(a())
}
```

不难看出，魔法都藏在`replace`函数里：需要修改`a`函数，使其不执行自己的函数体，而是跳转到函数`b`。

为了讲清楚如何实现，得先铺垫几点背景知识。

## go与汇编

在`go`项目里使用汇编是件很容易的事。`go`代码`func.go`里只声明函数：

```go
package main

func a() int
func b() int

func main() {
  println(a())
}
```

汇编代码`func.s`里，实现两函数，这里，我们让`a`函数跳转到`b`函数：

```assembly
#include "textflag.h"

TEXT ·a(SB), NOSPLIT, $0-8
  JMP ·b(SB)

TEXT ·b(SB), NOSPLIT, $0-8
  MOVQ $2, ret1+0(FP)
  RET
```

把`func.go`和`func.s`放到同一目录，然后执行：
`GO111MODULE="off"; go build -o func &&
./func`。这段代码定义了两个函数，`a`函数直接跳转到`b`函数，`b`返回整数`2`。至此，没什么大不了，手动实现跳转而已。

关于汇编的语法，不是本文的重点，可以参考文后链接。

## go的函数值类型

手动跳转显然不够，`replace(f, g)`的职责就动态改变函数`f`的代码，分两步：

- 取得函数`g`的地址
- 重写`f`，使其跳转到`g`

需要指出的是，`replace`的入参`f`或`g`很容易被误解为函数`a`或`b`的指针，但其实它们是指针的指针。这点可以通过反编译来验证，保存下面代码到`funcaddr.go`：

```go
package main

import (
  "fmt"
  "unsafe"
)

func a() int { return 1 }

func main() {
  f := a
  fmt.Printf("0x%x\n", **(**uintptr)(unsafe.Pointer(&f)))
}
```

执行 `go build funcaddr.go && ./funcaddr`得到：`0x109adc0`。

再执行`go tool objdump -S funcaddr`，搜索这个地址，发现确实是`a`函数的地址：

```assembly
TEXT main.a(SB) funcaddr.go
func a() int { return 1 }
  0x109adc0             48c744240801000000      MOVQ $0x1, 0x8(SP)
  0x109adc9             c3                      RET
```

Ok，通过函数值`f`可以拿到函数`a`的地址了。为什么要拿到地址呢？

## 在运行时改写函数

函数体本质是一段字符串，知道开始地址后，从那里开始写入表示新逻辑的字符串即可实现覆盖。随之而来的问题是：

- 新逻辑的字符串是什么？
- 如何知道覆盖的范围？

因为新的字符串要能直接被机器运行，所以它必须是机器码。把汇编翻译成机器码，并不是件容易的事，同一段汇编在不同平台得到的机器不尽相同。如果想手动翻译，可参考文后链接。

我用了一个取巧的方式，反翻译上面的`func`: `go tool objdump -S
func`，找到`main.a`的定义：

```
TEXT main.a(SB) func.s
  0x1054e70         e90b000000           JMP main.b(SB)
  //...
```

其中，`e90b000000`就是跳转到函数`b`的机器码。终于可以来实现`replace`函数了：

```go
func rawMemoryAccess(b uintptr) []byte {
  return (*(*[0xFF]byte)(unsafe.Pointer(b)))[:]
}

func replace(f, g func() int) {
  bytes := []byte{0xe9, 0x0b, 0x00, 0x00, 0x00}
  funcLocation := **(**uintptr)(unsafe.Pointer(&f))
  window := rawMemoryAccess(funcLocation)
  copy(window, bytes)
}
```

逻辑实现了，但这段代码是无法运行的。因为加载的二进制文件[默认是无法修改的](https://en.wikipedia.org/wiki/Segmentation_fault#Writing_to_read-only_memory)，即`copy`这行将报错。我们用系统调用`mprotect`来关闭这一保护机制，得到可用的代码：

```go
//go:noinline
package main

import (
  "syscall"
  "unsafe"
)

func a() int {return 1}
func b() int {return 2}

func rawMemoryAccess(b uintptr) []byte {
  return (*(*[0xFF]byte)(unsafe.Pointer(b)))[:]
}

func getPage(p uintptr) []byte {
  return (*(*[0xFFFFFF]byte)(unsafe.Pointer(p
& ^uintptr(syscall.Getpagesize()-1))))[:syscall.Getpagesize()]
}

func assembleJump(g func() int) []byte {
  return []byte{0xe9, 0x0b, 0x00, 0x00, 0x00}
}

func replace(f, g func() int) {
  bytes := assembleJump(g)
  functionLocation := **(**uintptr)(unsafe.Pointer(&f))
  window := rawMemoryAccess(functionLocation)

  page := getPage(functionLocation)
  syscall.Mprotect(page,
syscall.PROT_READ|syscall.PROT_WRITE|syscall.PROT_EXEC)

  copy(window, bytes)
}

func main() {
    replace(a, b)
    println(a())
}
```

现在可以直接执行`go run
func.go`，因为`func.s`只是用于帮助理解，现在不再需要了。
注意`//go:noinine`这行，用于关闭函数内联，这样才能支持改写。

眼尖的读者可能发现了，这个`replace`不够通用，还是写死了跳转到函数`b`而不是指定的函数`g`，实际上`g`参数根本没用上！
为了通用，我们改造`assembleJump`，让跳转的机器码使用`g`所指向的地址：

```go
func assembleJump(f func() int) []byte {
  funcVal := *(*uintptr)(unsafe.Pointer(&f))
  return []byte{
    0x48, 0xC7, 0xC2,
    byte(funcVal >> 0),
    byte(funcVal >> 8),
    byte(funcVal >> 16),
    byte(funcVal >> 24), // MOV rdx, funcVal
    0xFF, 0x22,          // JMP rdx
  }
}
```

这里不是直接`jmp`到函数`g`，而是先把`g`的地址存到寄存器`rdx`，再`jmp`到`rdx`。

用这个通用的`assembleJump`替换上面返回固定值的`assembleJump`，大功造成。

## monkey patch的应用

显然，这是一种hack，不能用于生产环境。随着go版本的迭代，没准不久的将来就失效了。如果仔细观察，会发现我们手写的汇编或者机器码，比`go`编译得到的少了些含有`FUNCDATA`和`PCDATA`字眼的内容：

```
  0x0000 00000 (func.go:9) FUNCDATA        $0,
gclocals·33cdeccccebe80329f1fdbee7f5874cb(
SB)
  0x0000 00000 (func.go:9) FUNCDATA        $1,
gclocals·33cdeccccebe80329f1fdbee7f5874cb(
SB)
  0x0000 00000 (func.go:9) FUNCDATA        $2,
gclocals·33cdeccccebe80329f1fdbee7f5874cb(
SB)
  0x0000 00000 (func.go:9) PCDATA  $0, $0
  0x0000 00000 (func.go:9) PCDATA  $1, $0
```

`PCDATA`把程序计数器和代码行号对应起来，`FUNCDATA`则是为垃圾回收服务的，详见[Object
Files and Function
Metadata](https://www.altoros.com/blog/golang-internals-part-4-object-files-and-function-metadata/)。缺少它们，相应功能就有缺陷。

难道，只能用于装逼了？

不，有一个场合正是用武之地：测试。将它用于打桩，让用户在单元测试中低成本的完成mock。

`go`的各种mock工具都只能对`interface`类型做mock。虽然我们一直提倡依赖倒置，现实中，还是有很多代码直接依赖了具体实现，给mock带来不必要的麻烦。

正好，黑魔法般的`monkey
patch`来搭救了。使用封装好的[monkey](https://github.com/bouk/monkey)，可以非常简单地实现对非`interface`依赖的mock。

举个例子，`RpcClient`是个`struct`，代表外部rpc调用：

```go
package rpc

type RpcClient struct {
}

func (rpc *RpcClient) SayHello() string {
  // call remote endpoint
  return "hello world"
}
```

在测试时mock这个rpc调用，返回指定内容：

```go
package rpc

import (
  "bou.ke/monkey"
  "github.com/stretchr/testify/assert"
  "reflect"
  "testing"
)

func TestSayHello(t *testing.T) {
    var client = &RpcClient{}

  fakeRpc := monkey.PatchInstanceMethod(reflect.TypeOf(client), "SayHello",
func(rpcClient *RpcClient) string {
    return "hi five"
  })
  defer fakeRpc.Unpatch()

  msg := client.SayHello()
  assert.Equal(t, "hi five", msg)
}
```

执行测试时，需要关闭内联：`go test -gcflags=-l`。

## 参考链接

- [A Quick Guide to Go’s
  Assembler](http://www.mit.edu/afs.new/sipb/project/golang/doc/asm.html)
- [A Primer on Go
  Assembly](https://github.com/teh-cmc/go-internals/blob/master/chapter1_assembly_primer/README.md#a-word-about-goroutines-stacks-and-splits)
- [A Beginners’ Guide to x86-64 Instruction
  Encoding](https://www.systutorials.com/beginners-guide-x86-64-instruction-encoding/)
- [X86-64 Instruction
  Encoding](https://wiki.osdev.org/X86-64_Instruction_Encoding)
