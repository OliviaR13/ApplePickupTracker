<div align="center">

# 🍎 Apple Pickup Tracker

**自动追踪 Apple Store 取货订单的 iOS 应用**
读取 Outlook 里的 Apple 订单邮件，在本机解析状态，并通过通知、锁定屏幕和灵动岛提醒你「可以取货了」。

![Platform](https://img.shields.io/badge/iOS-17%2B-black?logo=apple)
![Swift](https://img.shields.io/badge/Swift-5.10-orange?logo=swift)
![UI](https://img.shields.io/badge/SwiftUI-Liquid%20Glass-blue)
![Privacy](https://img.shields.io/badge/数据-仅保存在本机-green)

</div>

---

## ✨ 功能

| | |
|---|---|
| 📬 **邮件同步** | Microsoft OAuth 2.0 (PKCE) + Graph 只读 `Mail.Read`；首次扫描 365 天，之后增量同步 |
| 🧠 **本机解析** | 在设备上把 HTML 邮件转成文本，识别订单号、商品、门店、状态（繁体 / 简体中文、英文） |
| 📦 **订单管理** | 「进行中 / 已完成」分组、状态时间线、下拉刷新、一键清除本机数据 |
| 🔎 **搜索与筛选** | 按商品、门店、订单号搜索；按「全部 / 可取货 / 进行中 / 已完成」筛选 |
| ✍️ **手动增删** | 手动添加订单（之后同号邮件会自动更新）；左滑或在详情页移除订单，同步不会再加回来 |
| 🧭 **门店导航** | 订单详情一键在「地图」中打开取货门店 |
| 🏬 **门店照片** | 按门店名匹配 Apple 零售店列表并展示店面照片（带缓存） |
| 🔔 **取货提醒** | 订单变为「可以取货」时发送本地通知 |
| 🏝 **实时活动** | 锁定屏幕与灵动岛显示取货进度；设置页带自检面板，可一键重新启动 |
| 🪟 **Liquid Glass** | iOS 26 使用系统液态玻璃，iOS 17–18 自动回退到 Material |

> 不含任何开发者后端、统计或广告 SDK：邮件内容和订单数据都只在你的设备上处理。

## 📱 截图与使用流程

1. 打开 App → **连接 Outlook** 并授予只读权限
2. 点击 **同步**，核对订单号、商品、门店和状态
3. 进入订单详情，点 **在锁定屏幕和灵动岛显示**
4. 订单备妥时会收到通知

## 🗂 项目结构

```
App/            应用入口与全局依赖容器（AppContainer）
Models/         PickupOrder、状态检测、邮件字段解析
Outlook/        Microsoft OAuth(PKCE) 与 Graph 邮件客户端
Tracking/       同步服务、后台刷新、门店目录、错误文案
Storage/        订单 JSON 持久化（Application Support + 文件保护）
LiveActivity/   ActivityKit 属性与管理器
Widget/         灵动岛 / 锁屏 Live Activity 界面（独立 target）
Notifications/  本地通知
Views/          SwiftUI 界面、主题与 Liquid Glass 封装
Resources/      Info.plist、图标、启动屏、entitlements
project.yml     XcodeGen 工程描述（.xcodeproj 由它生成）
```

## 🛠 在 macOS 上构建

需要 macOS、Xcode 26+（iOS 26 SDK）、iOS 17 部署目标和 XcodeGen。

```bash
brew install xcodegen
xcodegen generate
open ApplePickupTracker.xcodeproj
```

选择 `ApplePickupTracker` scheme，在 *Signing & Capabilities* 里设置你的 Personal Team，并为 App 与 Widget 使用唯一的 Bundle ID（必须与 Azure 里登记的重定向 URI 一致）。

只想生成未签名 IPA（交给 AltStore / Sideloadly 签名）：

```bash
./package-unsigned-ipa.sh      # 输出 build/ApplePickupTracker-unsigned.ipa
```

没有 Mac？用 GitHub Actions 云端构建，见 [`GITHUB_SETUP.md`](GITHUB_SETUP.md)。

## 🔐 配置 Microsoft OAuth

1. 在 Azure 门户注册支持**个人 Microsoft 账户**的应用，添加 **Mobile and desktop** 重定向 URI：`msauth.<bundle id>://auth`
2. 添加委托权限 `Mail.Read` 和 `User.Read`
3. 把 Application (client) ID 填入 `Outlook/OutlookOAuth.swift` 的 `clientID`，并让 `redirectURI` / `callbackScheme` 与 Bundle ID 一致
4. 同一个 scheme（`msauth.<bundle id>`）还需要出现在 `Resources/Info.plist` 与 `project.yml` 的 `CFBundleURLSchemes` 中

App 内不放任何 Client Secret，授权流程使用 PKCE。

## ⚠️ 已知限制

1. 本仓库是源码工程，不是已签名的 IPA；签名需要 Xcode 与你自己的 Apple 账号。
2. 后台刷新由 iOS 决定是否、何时执行，不是实时轮询。
3. Live Activity 在 App 前台打开或同步时启动，之后只在 App 获得运行时间时更新；项目不含 APNs 推送中继。
4. 不同地区的 Apple 邮件模板有差异，解析器基于启发式规则，需要用你所在地区的真实邮件校验订单号、商品、门店与状态。
5. 免费 Personal Team 的描述文件通常 7 天过期，需要重新签名安装；Live Activity 扩展必须包含在已签名的 App 中。
6. 实时活动由系统限制最长约 8 小时，且没有推送服务时只在打开 App 或后台刷新时更新。
7. 主屏幕小组件需要 App Group，而免费 Personal Team 通常无法使用，因此暂未提供。

## 🔒 隐私

- OAuth 令牌保存在 Keychain（`ThisDeviceOnly`）
- 解析后的订单保存在本机 App 容器，启用文件保护
- 无统计、无广告、无后端
- 「断开 Outlook 连接」会删除本机令牌；「设置 › 清除订单数据」会删除订单记录并结束实时活动

## 🤖 GitHub Actions

`.github/workflows/ios-build.yml` 会在 push 到 `main` / `master` / `cursor/**`、Pull Request 或手动触发时，于 `macos-15` + Xcode 26 上构建，并上传 `ApplePickupTracker-unsigned-ipa`（保留 14 天）。构建失败时会额外上传 `xcodebuild-log` 方便排查。
