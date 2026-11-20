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

    var body: some View {
        NavigationStack {
            Form {
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
                Section("隐私与权限") {
                    Label("邮件内容仅在此设备上处理", systemImage: "iphone")
                    Label("订单数据保存在本机", systemImage: "lock.fill")
                    Label("Microsoft Graph：Mail.Read 只读权限", systemImage: "envelope.badge")
                }
                Section("实时活动") {
                    Label(activitiesEnabled ? "实时活动可用" : "实时活动已关闭", systemImage: activitiesEnabled ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .foregroundStyle(activitiesEnabled ? .green : .orange)
                    Text("取货状态可以显示在锁定屏幕和灵动岛。若系统关闭了实时活动，请在本 App 的设置里重新打开。远程推送更新需要开发者签名和 APNs，此版本只在打开 App 或同步时更新。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if !activitiesEnabled {
                        Button("打开系统设置") {
                            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                            UIApplication.shared.open(url)
                        }
                        .liquidGlassButton()
                    }
                }
                Section("同步") {
                    LabeledContent("上次同步", value: store.lastSync?.formatted(date: .abbreviated, time: .shortened) ?? "从未同步")
                    Text("iOS 会在系统资源允许时安排后台刷新，实际刷新时间由系统决定。").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("设置").navigationBarTitleDisplayMode(.inline)
            .task { activitiesEnabled = ActivityAuthorizationInfo().areActivitiesEnabled }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
            .alert("Outlook", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("好", role: .cancel) { message = nil }
            } message: { Text(message ?? "") }
        }
    }
}
