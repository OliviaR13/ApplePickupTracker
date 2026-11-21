<div align="center">

# 🍎 Apple Pickup Tracker

**面向 Apple Store 到店取货订单的原生 iOS 追踪应用**

从 Outlook 同步 Apple 订单邮件，在设备本地识别订单、商品、门店和取货状态；通过本地通知、Live Activity 与灵动岛展示取货进度。

![iOS](https://img.shields.io/badge/iOS-17%2B-000000?logo=apple)
![Swift](https://img.shields.io/badge/Swift-5.10-F05138?logo=swift&logoColor=white)
![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-007AFF?logo=swift)
![License](https://img.shields.io/badge/License-MIT-green.svg)
![Privacy](https://img.shields.io/badge/Privacy-Local%20First-2E8B57)

[功能介绍](#功能) · [开始使用](#开始使用) · [自行构建](#自行构建) · [隐私与权限](#隐私与权限) · [许可证](#许可证)

</div>

---

## 项目简介

Apple Pickup Tracker 帮助你集中查看 Apple Store 订单的到店取货进度。应用通过 Microsoft Graph 读取 Outlook 邮箱中的 Apple 订单邮件，在 iPhone 本地完成解析和状态管理。

**设计原则：本地优先。** 应用不依赖自建业务后端，不上传邮箱内容或订单数据，也不集成广告和统计 SDK。

## 功能

| 功能 | 说明 |
|---|---|
| Outlook 邮件同步 | Microsoft OAuth 2.0（PKCE），通过 Graph 的只读 `Mail.Read` 权限读取邮件；首次扫描最近 365 天，后续增量同步 |
| 本地邮件解析 | 在设备上解析 HTML 邮件，识别订单号、商品、门店、日期和订单状态；支持简体中文、繁体中文和英文模板 |
| 订单管理 | 按进行中、已完成分组；查看订单详情与状态时间线，支持下拉刷新和本机数据清理 |
| 搜索与筛选 | 按订单号、商品或门店搜索，并按订单状态筛选 |
| 手动管理 | 手动添加订单；删除不需要追踪的订单，后续同步不会重新加入已移除的订单 |
| 门店信息 | 展示识别出的取货门店，并可跳转地图导航；支持门店照片匹配与缓存 |
| 取货通知 | 订单状态变为「可以取货」时发送 iOS 本地通知 |
| Live Activity | 在锁定屏幕和灵动岛查看取货进度 |
| 外观 | 支持跟随系统、浅色和深色外观；iOS 26 使用系统 Liquid Glass，较早系统使用 Material 回退样式 |
| 安全展示 | 支持通过 Face ID 验证后展示取货二维码 |

## 开始使用

1. 安装应用并打开设置页面。
2. 选择 **连接 Outlook**，登录 Microsoft 账户并授予邮件只读权限。
3. 返回订单页，执行首次同步。
4. 核对订单号、商品、门店和状态。不同国家或地区的 Apple 邮件模板可能存在差异。
5. 对需要持续查看的订单，进入详情页启动 Live Activity。

> 首次连接后，应用会扫描最近 365 天的邮件。系统后台刷新由 iOS 调度，无法保证固定频率或实时执行。

## 自行构建

### 环境要求

- macOS
- Xcode 26 或更新版本（用于 iOS 26 SDK 与 Liquid Glass API）
- iOS 17.0 或更新版本作为部署目标
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

### 生成 Xcode 工程

```bash
brew install xcodegen
xcodegen generate
open ApplePickupTracker.xcodeproj
```

在 Xcode 中选择 `ApplePickupTracker` scheme，并在 **Signing & Capabilities** 中配置自己的 Apple Development Team。请为主 App 和 Widget Extension 设置适合自己的 Bundle ID。

### 打包未签名 IPA

```bash
./package-unsigned-ipa.sh
```

脚本会生成未签名 IPA，供 AltStore、Sideloadly 等工具使用个人开发者签名安装。未签名 IPA 不能直接安装。

### 使用 GitHub Actions 构建

仓库包含 macOS GitHub Actions 工作流，可自动构建并上传未签名 IPA：

1. 推送代码或在 GitHub 仓库的 **Actions** 页面手动运行 iOS Build 工作流。
2. 打开对应的 workflow run。
3. 在 **Artifacts** 下载 `ApplePickupTracker-unsigned-ipa`。
4. 解压后使用自己的签名工具安装。

详细说明见 [GITHUB_SETUP.md](GITHUB_SETUP.md)。

## 配置 Microsoft OAuth

应用使用 Microsoft 身份验证和 Microsoft Graph，不需要在客户端保存 Client Secret。

1. 在 [Microsoft Entra 管理中心](https://entra.microsoft.com/) 注册应用，并按需允许个人 Microsoft 账户登录。
2. 添加 **Mobile and desktop applications** 平台及重定向 URI：`msauth.<你的 Bundle ID>://auth`。
3. 添加委托权限：
   - `Mail.Read`：读取邮件。
   - `User.Read`：读取已登录用户的基本资料。
4. 将 Application (client) ID 填入 `Outlook/OutlookOAuth.swift`。
5. 确保 `redirectURI`、`callbackScheme`、`Resources/Info.plist` 和 `project.yml` 中的 URL Scheme 与 Bundle ID 一致。

**不要提交 Client Secret、访问令牌、Apple 账号密码、P12 私钥或 provisioning profile。**

## 隐私与权限

| 数据或权限 | 用途 | 存储方式 |
|---|---|---|
| Microsoft OAuth 令牌 | 访问用户授权的 Outlook 邮件 | iOS Keychain，使用设备绑定保护 |
| Outlook 邮件 | 提取 Apple 订单信息 | 在设备上读取和解析，不上传到项目服务器 |
| 订单数据 | 展示订单与同步状态 | 应用本机容器，启用文件保护 |
| 通知权限 | 在订单可以取货时提醒 | 由 iOS 本地通知服务处理 |
| Face ID | 验证后展示取货二维码 | 由 iOS LocalAuthentication 处理 |

- Microsoft Graph 请求由设备直接发起，应用使用只读邮件权限。
- 项目没有自建业务后端、广告 SDK 或分析统计 SDK。
- 断开 Outlook 会清除本机 OAuth 令牌。
- 清除订单数据会删除本机订单记录，并结束相关 Live Activity。

## 项目结构

```text
App/             SwiftUI 应用入口、AppContainer 与依赖管理
Models/          订单模型、状态与邮件字段解析
Outlook/         Microsoft OAuth（PKCE）与 Graph 邮件客户端
Tracking/        邮件同步、后台刷新、门店目录与错误处理
Storage/         本机订单持久化
Notifications/   iOS 本地通知
LiveActivity/    ActivityKit 属性与管理器
Widget/          Live Activity / 灵动岛界面（独立 Extension Target）
Views/           SwiftUI 页面、主题与 Liquid Glass 封装
Resources/       Info.plist、Assets、entitlements 与启动屏
.github/         GitHub Actions 工作流
project.yml      XcodeGen 工程配置
```

## 已知限制

1. **后台同步不是实时服务。** iOS 决定后台刷新任务的执行时机，系统可能延迟或跳过任务。
2. **通知为本地通知。** 应用在同步过程中检测到订单变为可取货状态后安排通知；项目没有 APNs 推送中继或自建推送服务器。
3. **Live Activity 更新受运行时机限制。** 没有远程推送更新服务时，活动主要在应用同步或获得后台执行时间时更新；其持续时间也受 iOS 系统策略约束。
4. **邮件模板存在地区差异。** 订单解析依赖邮件内容和启发式规则，建议首次同步后核对商品、门店和订单状态。
5. **个人免费签名有有效期限制。** 使用免费 Personal Team 安装时，签名通常需要定期续期；具体期限由 Apple 的签名政策决定。
6. **Widget 与 App Group 能力受签名配置影响。** 某些扩展能力在免费 Personal Team 下可能无法使用。

## 免责声明

Apple Pickup Tracker 是独立的开源项目，与 Apple Inc. 或 Microsoft Corporation 没有隶属、赞助或官方合作关系。Apple、Apple Store、iPhone、iOS、Outlook 等名称和商标归其各自权利人所有。

订单识别结果取决于邮件内容和解析规则。请以 Apple 官方订单页面及取货通知为准。

## 许可证

本项目采用 [MIT License](LICENSE) 开源。你可以使用、复制、修改、合并、发布、分发、再许可和/或销售本项目的副本，但须在副本中保留原版权声明和许可证文本。

第三方组件、商标及素材仍受其各自适用的许可或权利约束。
