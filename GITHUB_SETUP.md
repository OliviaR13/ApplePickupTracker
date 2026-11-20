# GitHub Actions 云端 iOS 构建

本仓库使用 GitHub Actions 的 macOS Runner 编译 iOS 工程，并上传**未签名 IPA**作为构建产物。不会在 GitHub 保存 Apple Account 密码、证书或私钥。

## 首次创建仓库（Windows）

1. 在 GitHub 选择 **New repository**。
2. Repository name：`ApplePickupTracker`。
3. 选择 **Private**。
4. 不要勾选自动创建 README、`.gitignore` 或 License（避免首次导入时产生无关提交）。
5. 在 Windows 安装 GitHub Desktop：<https://desktop.github.com/>。
6. 解压本项目 ZIP，将 `ApplePickupTracker` 文件夹中的全部内容复制到本地仓库目录（包括隐藏的 `.github` 文件夹）。
7. 在 GitHub Desktop 中提交：`Add Apple Pickup Tracker and macOS CI`，然后 Push 到 `main`。

## 自动构建

- 每次 Push 到 `main` 或 `master` 自动构建。
- 也可以在仓库的 **Actions → iOS Build → Run workflow** 手动触发。
- 构建成功后打开对应的 workflow run，在 **Artifacts** 下载 `ApplePickupTracker-unsigned-ipa`。
- 解压下载的 artifact ZIP，里面是 `ApplePickupTracker-unsigned.ipa`。

## 签名说明

Actions 只负责在 macOS Runner 上生成未签名 IPA。它不会使用或保存 Apple 账号凭据。下载 IPA 后，在 Windows 使用 AltStore / Sideloadly 的个人 Apple Team 流程签名安装。免费个人签名通常约 7 天需要续签。

## Gmail OAuth 配置

在 `Gmail/GmailOAuth.swift` 和 `Resources/Info.plist` 中替换 README 所列的 OAuth 占位符，再 Push 一次即可触发新构建。不要把 Google Client Secret、Apple 密码、P12 私钥或 provisioning profile 提交到仓库。

## 构建失败排查

打开 Actions 对应运行记录，展开 `Build and package unsigned IPA` 步骤查看 Xcode 编译日志。此工作流当前不会自动签名，也不会部署到 App Store。
