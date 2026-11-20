import ActivityKit
import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var oauth: OutlookOAuth
    @EnvironmentObject private var store: OrderStore
    @Environment(\\.dismiss) private var dismiss
    let onSync: () async -> Void
    @State private var isWorking = false
    @State private var message: String?
    @State private var activitiesEnabled = true
    @State private var showingDeleteConfirmation = false
    @State private var exportURL: URL?

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
                        Text("使用个人 Microsoft 账户登录，并以只读权限查找 Apple 订单邮件。")
                            .foregroundStyle(.secondary)
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
                    Label(activitiesEnabled ? "实时活动可用" : "实时活动已关闭",
                          systemImage: activitiesEnabled ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .foregroundStyle(activitiesEnabled ? .green : .orange)
                    Text("只有在订单详情中主动开启的订单才会显示实时活动。同步会更新已有活动，不会为所有订单自动创建活动。远程推送更新需要开发者签名和 APNs；当前版本在本机同步时更新。")
                        .font(.footnote).foregroundStyle(.secondary)
                    if !activitiesEnabled {
                        Button("打开系统设置") {
                            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                            UIApplication.shared.open(url)
                        }
                        .liquidGlassButton()
                    }
                }
                Section("订单数据管理") {
                    LabeledContent("本地订单", value: "\\(store.orders.count) 条")
                    Button {
                        do { exportURL = try store.makeExportFile() }
                        catch { message = "导出失败：\\(error.localizedDescription)" }
                    } label: {
                        Label("导出订单为 JSON", systemImage: "square.and.arrow.up")
                    }
                    .disabled(store.orders.isEmpty)
                    if let exportURL {
                        ShareLink(item: exportURL) {
                            Label("分享导出文件", systemImage: "doc.zipper")
                        }
                    }
                    Button("删除全部订单数据", role: .destructive) {
                        showingDeleteConfirmation = true
                    }
                    .disabled(store.orders.isEmpty)
                    Text("导出文件仅在你主动分享时离开设备。删除订单不会断开 Outlook 连接；如需撤销邮箱授权，请单独断开 Outlook。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("同步") {
                    LabeledContent("上次同步", value: store.lastSync?.formatted(date: .abbreviated, time: .shortened) ?? "从未同步")
                    Text("iOS 会在系统资源允许时安排后台刷新，实际刷新时间由系统决定。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("设置").navigationBarTitleDisplayMode(.inline)
            .task { activitiesEnabled = ActivityAuthorizationInfo().areActivitiesEnabled }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
            .alert("Outlook", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("好", role: .cancel) { message = nil }
            } message: { Text(message ?? "") }
            .confirmationDialog("删除全部订单？", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
                Button("删除全部订单", role: .destructive) {
                    store.deleteAllOrders()
                    NotificationManager.shared.removeAllPending()
                    Task { await LiveActivityManager().endAll() }
                    exportURL = nil
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("这会永久删除本机保存的订单、状态历史和取货说明。Outlook 连接不会受到影响。")
            }
        }
    }
}
