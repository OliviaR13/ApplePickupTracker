import ActivityKit
import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var oauth: OutlookOAuth
    @EnvironmentObject private var store: OrderStore
    @Environment(\.dismiss) private var dismiss
    let onSync: () async -> Void
    @State private var isWorking = false
    @State private var message: String?
    @State private var activitiesEnabled = true
    @State private var confirmingClear = false
    @State private var runningCount = 0
    @State private var restartNote: String?

    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            Form {
                outlookSection
                Section("隐私与权限") {
                    Label("邮件内容仅在此设备上处理", systemImage: "iphone")
                    Label("订单数据保存在本机", systemImage: "lock.fill")
                    Label("Microsoft Graph：Mail.Read 只读权限", systemImage: "envelope.badge")
                }
                liveActivitySection
                Section("同步") {
                    LabeledContent("上次同步", value: store.lastSync?.formatted(date: .abbreviated, time: .shortened) ?? "从未同步")
                    Text("iOS 会在系统资源允许时安排后台刷新，实际刷新时间由系统决定。").font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    Button("清除订单数据", role: .destructive) { confirmingClear = true }
                        .disabled(store.orders.isEmpty)
                } header: {
                    Text("数据")
                } footer: {
                    Text("只会删除本机保存的订单记录，不会影响 Outlook 邮箱里的邮件。")
                }
                Section("关于") {
                    LabeledContent("版本", value: versionText)
                }
            }
            .navigationTitle("设置").navigationBarTitleDisplayMode(.inline)
            .task {
                activitiesEnabled = ActivityAuthorizationInfo().areActivitiesEnabled
                runningCount = LiveActivityManager().runningCount
            }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
            .alert("Outlook", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("好", role: .cancel) { message = nil }
            } message: { Text(message ?? "") }
            .confirmationDialog("清除所有已保存的订单？", isPresented: $confirmingClear, titleVisibility: .visible) {
                Button("清除", role: .destructive) { Task { await clearData() } }
                Button("取消", role: .cancel) {}
            } message: {
                Text("订单记录和锁定屏幕上的实时活动都会被移除，下次同步会重新扫描邮箱。")
            }
        }
    }

    private var outlookSection: some View {
        Section("Outlook 邮箱") {
            if oauth.isConnected {
                Label("Outlook 已连接", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                if let email = oauth.accountEmail { LabeledContent("账户", value: email) }
                Button("立即同步") { Task { isWorking = true; await onSync(); isWorking = false } }
                    .liquidGlassProminentButton()
                    .disabled(isWorking)
                Button("断开 Outlook 连接", role: .destructive) { oauth.disconnect() }
            } else {
                Text("使用个人 Microsoft 账户登录，并以只读权限查找 Apple 订单邮件。").foregroundStyle(.secondary)
                Button("连接 Outlook") {
                    Task {
                        isWorking = true
                        do { try await oauth.connect(); await onSync() }
                        catch { message = error.localizedDescription }
                        isWorking = false
                    }
                }
                .liquidGlassProminentButton()
                .disabled(isWorking)
            }
        }
    }

    private var liveActivitySection: some View {
        Section {
            diagnosticRow("系统允许实时活动", ok: activitiesEnabled)
            diagnosticRow("锁屏 / 灵动岛扩展已安装", ok: extensionInstalled)
            LabeledContent("正在显示", value: "\(runningCount) 个")
            if !activitiesEnabled {
                Button("打开系统设置") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                }
                .liquidGlassButton()
            }
            Button("重新启动实时活动") { Task { await restartActivities() } }
                .disabled(!activitiesEnabled || !extensionInstalled)
        } header: {
            Text("实时活动")
        } footer: {
            Text(liveActivityFooter)
        }
    }

    private func diagnosticRow(_ title: String, ok: Bool) -> some View {
        Label(title, systemImage: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
            .foregroundStyle(ok ? .green : .red)
    }

    /// The Live Activity UI lives in `PickupWidget.appex`. Some sideloading setups drop app extensions.
    private var extensionInstalled: Bool {
        guard let plugIns = Bundle.main.builtInPlugInsURL,
              let items = try? FileManager.default.contentsOfDirectory(atPath: plugIns.path) else { return false }
        return items.contains("PickupWidget.appex")
    }

    private var liveActivityFooter: String {
        if !activitiesEnabled {
            return "系统里关闭了本 App 的实时活动。请在系统设置中打开后再回来。"
        }
        if !extensionInstalled {
            return "安装包里没有找到实时活动扩展，所以锁定屏幕和灵动岛不会显示。免费账号侧载时，签名工具可能会移除或无法签名 App 扩展，请在 AltStore / Sideloadly 中保留扩展后重新安装。"
        }
        if let restartNote { return restartNote }
        return "实时活动最长显示约 8 小时，没有推送服务时只会在打开 App 或后台刷新时更新。每次打开 App 同步都会自动重新启动。"
    }

    private func restartActivities() async {
        let manager = LiveActivityManager()
        await manager.reconcile(with: store.orders)
        runningCount = manager.runningCount
        restartNote = runningCount == 0
            ? "没有需要显示的订单（只会为最近 14 天内未完成的订单启动）。"
            : "已显示 \(runningCount) 个实时活动，请锁屏查看。"
    }

    private func clearData() async {
        store.clearAll()
        SyncService.resetScanState()
        await LiveActivityManager().endAll()
    }
}
