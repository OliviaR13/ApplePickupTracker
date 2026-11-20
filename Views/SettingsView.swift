import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var oauth: OutlookOAuth
    @EnvironmentObject private var store: OrderStore
    @Environment(\.dismiss) private var dismiss
    let onSync: () async -> Void
    @State private var isWorking = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Outlook 邮箱") {
                    if oauth.isConnected {
                        Label("Outlook 已连接", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        if let email = oauth.accountEmail { LabeledContent("账户", value: email) }
                        Button("立即同步") { Task { isWorking = true; await onSync(); isWorking = false } }.disabled(isWorking)
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
                        }.disabled(isWorking)
                    }
                }
                Section("隐私与权限") {
                    Label("邮件内容仅在此 iPhone 上处理", systemImage: "iphone")
                    Label("订单数据保存在本机", systemImage: "lock.fill")
                    Label("Microsoft Graph：Mail.Read 只读权限", systemImage: "envelope.badge")
                }
                Section("同步") {
                    LabeledContent("上次同步", value: store.lastSync?.formatted(date: .abbreviated, time: .shortened) ?? "从未同步")
                    Text("iOS 会在系统资源允许时安排后台刷新，实际刷新时间由系统决定。").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("设置").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
            .alert("Outlook", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("好", role: .cancel) { message = nil }
            } message: { Text(message ?? "") }
        }
    }
}
