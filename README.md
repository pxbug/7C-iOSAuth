# 7C云iOS网络验证SDK

7C云iOS网络验证SDK，用于iOS应用的在线激活与授权验证。

## 功能特性

- 卡密激活与验证
- Token持久化存储
- 自动续期
- 设备绑定
- MD5签名校验

## 文件结构

```
7C云验证/
├── Go/                      # 验证模块源码
│   ├── GoAuth.h
│   └── GoAuth.m
├── Go.xcodeproj/           # Xcode项目文件
└── README.md
```

## 使用方法

1. 将 `Go` 文件夹导入到您的Xcode项目中
2. 在 `AppDelegate.m` 中引入头文件：

```objc
#import "GoAuth.h"
```

SDK会在应用启动3秒后自动检测激活状态，无需手动调用。

## API配置

在 `GoAuth.m` 中修改以下配置：

```objc
#define kAPIHost    @"http://api1.7ccccccc.com"
#define kAppKey     @"您的AppKey"
#define kAppSecret  @"您的AppSecret"
```

## 依赖

- iOS 9.0+
- CommonCrypto (系统框架)

## 协议

MIT License
