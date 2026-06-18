---
title: Go项目单元测试实践
date: 2020-04-26
author: yzrun
layout: post
categories:
- computer
permalink: "/computer/2020/04/26/go-unit-test.html"
---

## 前言

单测本身不是目的，更根本地，要提升工程的可维护性。

为什么随着时间的推移，工程越来越难维护？因为工程的复杂度的增速快于我们治理复杂度的能力的增速。治理复杂度的能力落地了就是工程的可维护性。

用线性的手段去治理指数的问题，只在初期可行。长期必须要有一个比问题曲线更陡的能力曲线。

![](/img/202004/go-ut-1.jpg)

影响工程复杂度的因素：

- 业务的本质复杂性
- 互联网高人员流动性
- 文档永远缺失或滞后

治理复杂度的能力

- 设计能力
- 测试能力

本文从测试角度出发做一点探讨。首先澄清概念，这里的“测试”专指研发人员自行开展的测试工作，不包括QA同学的工作。

可能涉及单元、集成、功能测试，用下图说明：

![](/img/202004/go-ut-2.jpg)

## 测试的意义

常见的说法：

- 等项目提测后再补些单测。其心理：
  - 不知有没有意义，tl要求，没办法
  - 有意义，为了方便后续人员维护

事后补单测，好比把到女神了，依然热度不减当初，天天嘘寒问暖。是有这样的人，但你是吗？

另一种认识：

- 帮助本人开发现在的功能。**本人**！**现在**！
  在没有护栏的高速路狂奔，开得越快，死得越快。
  ![](/img/202004/go-ut-3.jpg)
- 帮助提高项目的长度维护性。顺便！
  在**高人员流动**的情境下实现工程的**长期可维护性**。
  - 靠员工传承 ✕
  - 靠文档传承 ✕
  - 自解释工程 √
- test as a doc

## 可用的测试

**低成本**地实现：

- 可重复运行
- 可自动运行
- 不依赖外部环境

即，测试本身的scalability

对比几种测试做法：

#### 流程1:

- 为case1在db造数据 (每次3m)
- 本地启用应用（改配置连本地服务) (每次2m)
- 在postman配置，为case1调api (若能长期保存psotman配置，则每次1m，否则每次5m）

#### 流程2:

- 为case1在db造数据 (每次3m)
- 写测试代码 (首次10min，以后0)
- 运行测试代码 (每次0.1m)

#### 流程3:

- 为case1在代码中靠数据 (首次6m，以后0)
- 写测试代码 (首次10min，以后0)
- 运行测试代码 (每次0.1m)

长期耗时对比：

- 流程1：(3+2)*n + 5 + 1*(n-1) = 6n+4
- 流程2：3*n + 10 + 0.1*n = 3.1n+10
- 流程3：6+10+0.1n = 0.1n+16

![](/img/202004/go-ut-4.jpg)

流程1和2都是非scalable的做法，问题分析：

- 流程1，依赖了外部环境，不可重复、无法自动化
- 流程2，依赖了外部环境，不可重复，可以自动化
- 流程3，不依赖外部环境，可以重复，可以自动化

以为点点postman、连mysql造条数据是图省事，诸不知这是更费事的做法。一个短期、一个长期，本质上都是“偷懒”，省点时间多看看窗外的风景、少掉几根头发。

> Less is exponentially more —— Rob Pike

如果认同上述观点，接下来的内容其实不看也没啥损失。因为你总会想出各种手段去“偷懒”的，具体的手段反而关系不大了。换言之，以下方式随时可能被更先进、更scalable的方式替代。

## 工程可测性

### 遵守控制反转原则

并不是所有代码都是可测试的。谈具体测试做法前，得先保证代码的可测性。道理上是极其简单的，即`SOLID`原则中的`D`：

> Any higher classes should always depend upon the abstraction of the class rather than the detail. –**Dependency Inversion Principle**.

但实践起来并不那么容易。
比如，业务代码中很常见的repo调用dal的写法：

```go
func (repo *RepositoryImpl) Create(ctx context.Context, user *model.User) (*int64, error) {
  // ...
  userDO := convert.UserModel2DO(user)
  dal.CreateUser(ctx, userDO)
  // ...
}
```

比如，调用rpc的写法：

```go
// 调用rpc：
thirdcall.ProduceServiceClient.QueryTaskPackPage(c, pageTaskPackRequest)

// ProduceServiceClient定义：
type Client struct {
  kc *kitc.KitcClient
}
```

毫无违和感，却是违背`DI`的，进而限制可测性。

因为抽象是可变的，实现是固定的。依赖抽象使得测试过程中剥离无关部分（可能是其它系统、也可能是本系统的其它代码）成为可能。而测试，只应测试目标代码，既不应依赖另一个系统、模块的输入，也不应输出到另一个系统、模块，这是“不依赖外部环境”的双重含义。（从这个意义上说，测试的过程应践行函数式编程的理念：pure、immutable、no side effect。）

就go语言而言，唯一的抽象工具就是`interface`了。当依赖`interface`时，可以在测试时用内存实现的db替换外部的mysql；用mock的rpc客户端替换真实的rpc调用。

### 尽量避免全局变量

一时全局一时爽，一直全局会很惨！

散落在各处的全局变量引用，让人无法快速分析出外部依赖。本质上全局变量是固定的实现，绑定全局变量同样使得剥离依赖变量困难。

建议：总是在`struct`定义里声明清楚外部依赖，哪怕只是一个`config`：

```go
type TaskPackServiceImpl struct {
	MaterialService         MaterialService
	TaskService             TaskService
	UserService             UserService
}

type MatrixClientImpl struct {
	Config config.MatrixConfig
}
```

有个例外情况。构造器初始化传参的方式过于简单，复杂项目下，在我们没有依赖注入工具的情况下，会让单例生成变得很繁琐。如`TaskPackService`和`TaskService`互相依赖，无法直接构造出来。如果严格执行上述建议，相当于人工实现依赖注入。所有单例都先使用无参数构造器`new`出来，然后再遍历依赖图，一个个`set`属性。

在引入依赖注入工具之前，这种耦合严重的场景可以直接引用全局变量，其余场景（占多数，毕竟是微服务）仍坚持该建议。

## 方法与实操

权衡投入产出，推荐对服务的serivce层做测试。服务的handler层和api暂不推荐。以service的公有方法为单位编写若干测试用例。

推荐两种实践：

- 对复杂的service方法做单元测试，即把该方法的外部依赖全部mock掉，包括其它service，和自己dal层。
- 复杂度一般的service方法，直接做集成测试，即不mock其它的其它service，不mock自己的dal层。但mock掉外部依赖：rpc、中间件的调用，等。

总得来说：`Mock`，只是结合具体场景的手段不尽相同。

#### 场景1，数据库调用

有两种路线：

- 1，直接把dal层mock掉
- 2，dal层真实，但db被mock

建议走路线2，因为我们的业务往往`sql`的正确性是非常关键的，有些功能甚至就是些`crud`，路线1把dal层都mock掉了，发现问题的可能性大大降低了。

用内存数据库替代真实数据库（这也是一种mock）。

- dao依赖抽象的`DBManager`
- 提供`DBManager`的两个实现
- 在init内提供选择（只在这里有区别，其余代码完全一样）

```go
// 抽象的db协议
type DBManager interface {
	WithDB(ctx context.Context) context.Context
	GetDB(ctx context.Context) *gorm.DB
	TransactionWithResult(ctx context.Context, fc func(ctx context.Context) (interface{}, error)) (result interface{}, err error)
	Transaction(ctx context.Context, fc func(ctx context.Context) error) (err error)
}

// 测试用的db实现
type DBManagerFake struct {
}

// 生产用的db实现
type DBManagerReal struct {
}

// dal包的Init方法提供两种Init:
func Init() {
	initRealDB()   // 外部mysql
	EMDBManager = &DBManagerReal{}
	initDAOs()
}

func InitTest() {
	initFakeDB()  // 内存sqlite
	EMDBManager = &DBManagerFake{}
	initDAOs()
}

// XXX_test.go文件里使用InitTest：
func TestAuditPassAction_Transfer_DoublePass(t *testing.T) {
	dal.InitTest()
	repository.Init()
	Init()
	// ...
}
```

#### 场景2，外部调用

数据库场景里代码在我们掌握范围内，像redis、rpc之类的（统称外部调用）客户端代码都是提供好的，像我司的kitool生成的客户端代码就是一个`type Client struct`，并没有提供`interface`，怎么办？

我们自己写个`interface`，再引用预生成的代码实现该`interface`。实际使用时，不直接用预生成的代码，而是通过依赖该`interface`。

以`crowd`项目和题库的交互为例，我们自己定义`interface`表达题库提供的能力协议：

```go
type MatrixClient interface {
	AddUpdateBook(ctx context.Context, requests []*AddUpdateBookRequest) (*MatrixResponse, error)
	UpdateBookState(ctx context.Context, requests []*UpdateBookStateRequest) (*MatrixResponse, error)
	AddUpdateItem(ctx context.Context, requests []*AddUpdateItemRequest) (*MatrixResponse, error)
	UpdateItemState(ctx context.Context, itemIds []int64, state int) (*MatrixResponse, error)
}
```

然后有两份实现

- 真实的`MatrixClientImpl`，生产使用
- 假的`MockMatrixClient`，测试时使用。

类似地，其它形式的外部依赖，也可以这么解决。付出的额外成本是：

- 一个`interface`定义
- 一个调用真实接口的`implementation`

这个成本是非常小的，因为`interface`的定义就是原方法签名的拷贝，而`implementation`只是简单地返回真实调用。

`MockMatrixClient`怎么搞后面再介绍。

值得讨论的问题是，换位思考下，作为服务提供方时，我们是否应该提供`interface+implementation`，而不是只提供`implementation`？

乍一看，前者更好。但更推荐后者，因为一个`interface`往往有多个方法，但多数场景下，并不会用到全部方法。一个大而全的`interface`反而让使用方背负过多负担。使用方根据需求定义自己的小`interface`，成本更低。

### 用例的编写

#### 收集用例

产品 < 研发 < QA：

- 产品给规则(和典型case)
- 研发单测覆盖主干case
- QA覆盖各种情形的case
- bug反馈

建议：当修复qa反馈的bug后，应该考虑落地成代码内的测试用例，方便后续回归。（当因某个路段护栏坏了掉进沟里，把车吊上起之后，还想把护栏补一补，对吧？）

#### 保持独立

- 一个测试方法对应一个case
- 用例之间不共享数据、状态
- 线程安全，可并发跑测试

测试代码与业务代码分离

- 文件独立，测试代码写在XXX\_test.go里
- 包独立, 业务为`package service`，对应测试应为`package service_test`。
  - 独立包的好处是编译后成的生产用的可执行文件内不会包括`test`相关代码。
  - 减少包互相依赖的可能性。

### 单测覆盖率

命令：

- cd app/service
- go test -coverprofile=c.out
- go tool cover -html=c.out

注意，覆盖率是statements，不是branches。

多少合适？

覆盖率不是追求的目标，作为研发，**覆盖主干case**是目标。但这个目标不易量化和评价。因此暂且用覆盖率代替，个人想法：60%及格，80%良好。[awesome-go](https://github.com/avelino/awesome-go)要求项目测试覆盖率达到80% 以上才有资格入选。Go社区两个常用库的覆盖率情况：

- gin: 98%
- gorm: 78%

### mock生成工具

利用[mockgen](https://github.com/golang/mock)，只要有`interface`，就能自动生成`implementation`。

例如：

```bash
mockgen -source=search.go -package=thirdcall -destination=search_mock.go
```

对`search.go`内的`interface`进行mock，生成实现`search_mock.go`，其package为`thirdcall`。

注意，`search_mock.go`为自动生成的代码，任何时候都不应人工修改它。当源`interface`有变化时，应重新执行上述命令。

mock生成的代码虽然是固定的，其行为表现却是高度可制定的。可以在测试代码里直接指定被Mock对象的行为，如：

```go
// 执行SearchItem时传ctx和任意参数，都返回指定的resp和nil：
algoService.EXPECT().
  SearchItem(ctx, gomock.Any()).
  Return(resp, nil)

// 执行SearchItem时传ctx和任意参数，sleep两分钟，然后返回nil, nil。模拟服务超时。
algoService := thirdcall.NewMockAlgorithmService(ctrl)
algoService.
  EXPECT().
  SearchItem(ctx, gomock.Any()).
  DoAndReturn(func(ctx context.Context, r *searchpage0.SearchItemRequest) (*searchpage.KitcSearchItemResponse, error) {
    time.Sleep(time.Minute * 2)
    return nil, nil
  }).
  AnyTimes()
```

### 测试的成本

- 项目初期，更长的开发时间
- 更高的技能要求，对语言、对设计
- 更煎熬的心理：
  - 长短期思维的博弈
  - 个人vs团队,前人vs后人
