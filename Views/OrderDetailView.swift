import SwiftUI
import UIKit

struct OrderDetailView: View {
    @EnvironmentObject private var store: OrderStore
    @Environment(\.dismiss) private var dismiss
    /// Snapshot used to open the screen; the live copy is looked up in the store so it refreshes after a sync.
    let initial: PickupOrder

    @State private var liveActivity = LiveActivityManager()
    @State private var activityNote: String?
    @State private var activitiesDisabled = false
    @State private var confirmingRemove = false

    private var order: PickupOrder { store.order(withNumber: initial.orderNumber) ?? initial }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                StorePhotoBanner(storeName: order.recognizedStoreName)
                LiquidGlassGroup(spacing: 12) {
                    VStack(alignment: .leading, spacing: 18) {
                        statusHero
                        itemCard
                        detailsCard
                        if hasFinancialDetails { financialCard }
                        if hasStoreDetails { storeCard }
                        timelineCard
                        if let storeName = order.recognizedStoreName {
                            Button {
                                Task { await StoreNavigator.open(storeName: storeName) }
                            } label: {
                                Label("导航到取货门店", systemImage: "map")
                                    .frame(maxWidth: .infinity)
                            }
                            .controlSize(.large)
                            .liquidGlassButton()
                        }
                        liveActivityControls
                    }
                }
            }
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("订单详情")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.success, trigger: activityNote)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(role: .destructive) { confirmingRemove = true } label: {
                        Label("从列表移除", systemImage: "trash")
                    }
                } label: { Image(systemName: "ellipsis") }
                    .accessibilityLabel("更多")
            }
        }
        .confirmationDialog("移除这个订单？", isPresented: $confirmingRemove, titleVisibility: .visible) {
            Button("移除", role: .destructive) { removeOrder() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只会从本机列表移除，之后同步也不会再加入。")
        }
    }

    private func removeOrder() {
        let number = order.orderNumber
        store.remove(orderNumber: number)
        Task { await liveActivity.end(orderNumber: number) }
        dismiss()
    }

    // MARK: - Status

    private var statusHero: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(order.status.title, systemImage: order.status.symbolName)
                .font(.title.bold())
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            Text(order.status.detail)
                .font(.subheadline)
                .opacity(0.92)
                .fixedSize(horizontal: false, vertical: true)
            if order.status.progress > 0 {
                ProgressView(value: order.status.progress)
                    .tint(.white)
                    .padding(.top, 6)
            }
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(order.status.gradient, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: order.status.tint.opacity(0.28), radius: 14, y: 6)
        .animation(.easeInOut, value: order.status)
    }

    // MARK: - Details

    private var itemCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("商品清单", systemImage: "shippingbox")
                    .font(.headline)
                Text(order.productName)
                    .font(.body.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Text("数量")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(order.quantity.map { String($0) } ?? "—")
                        .monospacedDigit()
                }
                if let amount = order.productAmount {
                    moneyRow("商品金额", amount, emphasized: true)
                }
            }
        }
    }

    private var hasFinancialDetails: Bool {
        order.subtotal != nil || order.shippingFee != nil || order.totalAmount != nil
    }

    private var financialCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("金额明细", systemImage: "yensign.circle")
                    .font(.headline)
                if let subtotal = order.subtotal { moneyRow("商品小计", subtotal) }
                if let shipping = order.shippingFee { moneyRow("配送费", shipping) }
                if let total = order.totalAmount {
                    Divider()
                    moneyRow("订单总计", total, emphasized: true)
                }
            }
        }
    }

    private var hasStoreDetails: Bool {
        order.storeAddress != nil || order.storePostalCode != nil || order.storePhone != nil
    }

    private var storeCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("取货门店", systemImage: "mappin.and.ellipse")
                    .font(.headline)
                Text(order.displayStoreName)
                    .font(.body.weight(.semibold))
                if let address = order.storeAddress, !address.isEmpty {
                    Text(address)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                if let postal = order.storePostalCode {
                    detailRow("邮政编码", postal)
                }
                if let phone = order.storePhone {
                    detailRow("联系电话", phone)
                }
            }
        }
    }

    private var detailsCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("订单信息", systemImage: "doc.text")
                    .font(.headline)
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
        }
    }

    private func moneyRow(_ title: String, _ amount: Decimal, emphasized: Bool = false) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(emphasized ? .primary : .secondary)
            Spacer()
            Text(formattedMoney(amount))
                .fontWeight(emphasized ? .semibold : .regular)
                .monospacedDigit()
        }
        .font(.subheadline)
    }

    private func formattedMoney(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = order.currencyCode ?? "CNY"
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: amount as NSDecimalNumber) ?? amount.description
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value).multilineTextAlignment(.trailing).textSelection(.enabled)
        }
        .font(.subheadline)
    }

    // MARK: - Timeline

    private var timelineCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Label("订单动态", systemImage: "clock.arrow.circlepath")
                    .font(.headline)
                timeline
            }
        }
    }

    @ViewBuilder
    private var timeline: some View {
        let events = order.history.sorted { $0.date > $1.date }
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                let isLast = index == events.count - 1
                HStack(alignment: .top, spacing: 14) {
                    VStack(spacing: 0) {
                        Circle()
                            .fill(index == 0 ? event.status.tint : Color.secondary.opacity(0.35))
                            .frame(width: 12, height: 12)
                            .padding(.top, 4)
                        if !isLast {
                            Rectangle()
                                .fill(Color.secondary.opacity(0.25))
                                .frame(width: 2)
                                .frame(maxHeight: .infinity)
                        }
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(event.status.title)
                            .font(.subheadline.weight(index == 0 ? .semibold : .regular))
                            .foregroundStyle(index == 0 ? Color.primary : Color.secondary)
                        Text(event.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, isLast ? 0 : 18)
                    Spacer(minLength: 0)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Live Activity

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
}
