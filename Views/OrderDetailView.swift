import SwiftUI
import UIKit

struct OrderDetailView: View {
    let order: PickupOrder
    @Environment(\.dismiss) private var dismiss
    @State private var liveActivity = LiveActivityManager()
    @State private var activityNote: String?
    @State private var activitiesDisabled = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                StorePhotoBanner(storeName: order.recognizedStoreName)
                LiquidGlassGroup(spacing: 12) {
                    VStack(alignment: .leading, spacing: 22) {
                        statusCard

                    VStack(alignment: .leading, spacing: 12) {
                        Label("订单详情", systemImage: "shippingbox")
                            .font(.headline)
                        detailRow("商品", order.productName)
                        detailRow("取货门店", order.displayStoreName)
                        detailRow("订单编号", order.orderNumber)
                        detailRow("最后更新", order.lastUpdated.formatted(date: .abbreviated, time: .shortened))
                        if let note = order.pickupNote, !note.isEmpty {
                            DisclosureGroup("取货说明") {
                                Text(note)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.top, 4)
                            }
                            .font(.subheadline.weight(.semibold))
                        }
                    }
                    .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                    .liquidGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                    VStack(alignment: .leading, spacing: 16) {
                        Text("订单动态").font(.headline)
                        ForEach(order.history.sorted { $0.date < $1.date }) { event in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(event.status == order.status ? .green : .secondary)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(event.status.title).font(.subheadline.weight(.semibold))
                                    Text(event.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                    .liquidGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                    liveActivityControls
                }
                }
            }
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("订单详情")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("返回")
            }
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(order.status.title, systemImage: order.status.symbolName)
                .font(.largeTitle.bold())
                .lineLimit(3)
                .minimumScaleFactor(0.7)
                .foregroundStyle(order.status.tint)
            Text(order.status.detail).font(.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ProgressView(value: order.status.progress).tint(order.status.tint).padding(.top, 8)
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var liveActivityControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                Task { await showOnLockScreen() }
            } label: {
                Label("在锁定屏幕和灵动岛显示", systemImage: "rectangle.inset.filled.bottom")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .liquidGlassProminentButton()
            if activitiesDisabled {
                Text("实时活动已关闭。打开「设置 › Apple Pickup Tracker › 实时活动」后即可在锁定屏幕和灵动岛查看取货状态。远程推送更新需要签名和 APNs，当前版本只在本机同步时更新。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("打开系统设置") { openSettings() }
                    .liquidGlassButton()
            } else if let activityNote {
                Text(activityNote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func showOnLockScreen() async {
        switch await liveActivity.startOrUpdate(for: order) {
        case .disabled:
            activitiesDisabled = true
            activityNote = nil
        case .started, .updated:
            activitiesDisabled = false
            activityNote = "已显示在锁定屏幕和灵动岛。状态会在这台设备同步邮件时更新。"
        case .ended:
            activitiesDisabled = false
            activityNote = "订单已结束，实时活动会在一小时后从锁定屏幕消失。"
        case .failed(let message):
            activitiesDisabled = false
            activityNote = message
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value).multilineTextAlignment(.trailing).textSelection(.enabled)
        }.font(.subheadline)
    }
}
