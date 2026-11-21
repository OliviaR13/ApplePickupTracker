import SwiftUI
import UIKit
import LocalAuthentication

struct OrderDetailView: View {
    @EnvironmentObject private var store: OrderStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    /// Snapshot used to open the screen; the live copy is looked up in the store so it refreshes after a sync.
    let initial: PickupOrder
    let loadOriginalMail: (String) async throws -> OriginalMailMessage

    @State private var liveActivity = LiveActivityManager()
    @State private var activityNote: String?
    @State private var activitiesDisabled = false
    @State private var confirmingRemove = false
    @State private var showingQRCode = false
    @State private var isQRCodeUnlocked = false
    @State private var previousBrightness: CGFloat?
    @State private var originalMail: OriginalMailMessage?
    @State private var showingOriginalMail = false
    @State private var originalMailError: String?
    @AppStorage("security.protectQRCodeWithBiometrics") private var protectQRCodeWithBiometrics = true

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
                        if hasPickupAssets { pickupPassCard }
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
        .onChange(of: protectQRCodeWithBiometrics) { _, enabled in
            isQRCodeUnlocked = !enabled
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active && protectQRCodeWithBiometrics {
                isQRCodeUnlocked = false
            }
        }
        .onDisappear {
            isQRCodeUnlocked = false
            restoreBrightness()
        }
        .alert("无法解锁二维码", isPresented: Binding(
            get: { originalMailError != nil },
            set: { if !$0 { originalMailError = nil } }
        )) {
            Button("好", role: .cancel) { originalMailError = nil }
        } message: {
            Text(originalMailError ?? "")
        }
        .sheet(isPresented: $showingOriginalMail) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(originalMail?.sender ?? "正在从 Outlook 加载邮件…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        if let date = originalMail?.receivedAt {
                            Text(date.formatted(date: .long, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    Divider()
                    if let mail = originalMail {
                        OriginalMailBodyView(content: mail.body, isHTML: mail.isHTML)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ContentUnavailableView("正在加载邮件原文", systemImage: "envelope.open", description: Text("正在从 Outlook 获取完整邮件内容。"))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .navigationTitle(originalMail?.subject ?? "邮件原文")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { showingOriginalMail = false } } }
            }
        }
        .fullScreenCover(isPresented: $showingQRCode, onDismiss: restoreBrightness) {
            if let image = pickupQRCodeImage {
                PickupQRCodeFullscreen(image: image, orderNumber: order.orderNumber)
            }
        }
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
        ContentCard {
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


    private var pickupQRCodeImage: UIImage? {
        guard let encoded = order.pickupQRCode,
              let data = Data(base64Encoded: encoded),
              let image = UIImage(data: data) else { return nil }
        return image
    }

    private var walletPassDestination: URL? {
        guard let raw = order.walletPassURL,
              let url = URL(string: raw),
              url.scheme?.lowercased() == "https",
              url.host?.lowercased() == "storepass.apple.com",
              url.path.lowercased().contains("/mpo/v2/apu/passcreator/") else { return nil }
        return url
    }

    private var hasPickupAssets: Bool {
        pickupQRCodeImage != nil || walletPassDestination != nil
    }

    private var pickupPassCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Label("到店取货凭证", systemImage: "qrcode")
                    .font(.headline)
                if let image = pickupQRCodeImage {
                    Button { Task { await presentQRCode() } } label: {
                        ZStack {
                            Image(uiImage: image)
                                .resizable()
                                .interpolation(.none)
                                .scaledToFit()
                                .frame(maxWidth: 240, maxHeight: 240)
                                .padding(14)
                                .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
                                .blur(radius: protectQRCodeWithBiometrics && !isQRCodeUnlocked ? 13 : 0)

                            if protectQRCodeWithBiometrics && !isQRCodeUnlocked {
                                VStack(spacing: 8) {
                                    Image(systemName: "faceid")
                                        .font(.system(size: 30, weight: .medium))
                                    Text("点击验证以显示二维码")
                                        .font(.caption.weight(.semibold))
                                }
                                .foregroundStyle(.primary)
                                .padding(14)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .accessibilityLabel(protectQRCodeWithBiometrics && !isQRCodeUnlocked
                                            ? "二维码已隐藏，点击使用 Face ID 解锁"
                                            : "查看 Apple Store 取货二维码")
                    }
                    .buttonStyle(.plain)
                    Text(protectQRCodeWithBiometrics
                         ? (isQRCodeUnlocked ? "二维码已解锁，再次点击可全屏展示。" : "二维码已模糊隐藏，验证身份后将在此处显示。")
                         : "点击二维码放大并临时调高屏幕亮度。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                    Text("请在门店出示此二维码完成取货。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                if let destination = walletPassDestination {
                    Link(destination: destination) {
                        Label("添加到 Apple Wallet", systemImage: "wallet.pass")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                    .liquidGlassButton()
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
        order.recognizedStoreName != nil || order.storeAddress != nil || order.storePostalCode != nil || order.storePhone != nil
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
        formatter.locale = Locale(identifier: order.currencyCode == "HKD" ? "zh_HK" : "zh_CN")
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
                if let alerts = order.alerts, !alerts.isEmpty { alertTimeline(alerts) }
                timeline
            }
        }
    }

    private func alertTimeline(_ alerts: [OrderAlert]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("订单异常与提醒", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
            ForEach(alerts.sorted { $0.date > $1.date }) { alert in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(alert.title).font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(alert.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    Text(alert.detail).font(.footnote).foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private func presentQRCode() async {
        if protectQRCodeWithBiometrics && !isQRCodeUnlocked {
            let context = LAContext()
            context.localizedCancelTitle = "取消"
            do {
                var error: NSError?
                guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
                    originalMailError = error?.localizedDescription ?? "此设备尚未设置 Face ID 或设备密码。"
                    return
                }
                _ = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "验证身份后显示 Apple Store 取货二维码")
                isQRCodeUnlocked = true
            } catch {
                originalMailError = error.localizedDescription
            }
            return
        }

        previousBrightness = UIScreen.main.brightness
        UIScreen.main.brightness = 1.0
        showingQRCode = true
    }

    private func restoreBrightness() {
        if let previousBrightness {
            UIScreen.main.brightness = previousBrightness
            self.previousBrightness = nil
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
                        if let messageID = event.messageID, messageID != "manual" {
                            Button {
                                originalMail = nil
                                showingOriginalMail = true
                                Task {
                                    do { originalMail = try await loadOriginalMail(messageID) }
                                    catch { originalMail = OriginalMailMessage(subject: "无法加载邮件", sender: "", receivedAt: nil, body: error.localizedDescription, contentType: "text") }
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(event.status.title)
                                        .font(.subheadline.weight(index == 0 ? .semibold : .regular))
                                        .foregroundStyle(index == 0 ? Color.primary : Color.secondary)
                                    Text("查看邮件原文").font(.caption2).foregroundStyle(.tint)
                                }
                            }.buttonStyle(.plain)
                        } else {
                            Text(event.status.title)
                                .font(.subheadline.weight(index == 0 ? .semibold : .regular))
                                .foregroundStyle(index == 0 ? Color.primary : Color.secondary)
                        }
                        Text(event.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption).foregroundStyle(.secondary)
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

private struct PickupQRCodeFullscreen: View {
    let image: UIImage
    let orderNumber: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 22) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Apple Store 取货凭证")
                            .font(.headline).foregroundStyle(.white)
                        Text(orderNumber).font(.caption.monospaced()).foregroundStyle(.white.opacity(0.65))
                    }
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding(12)
                            .background(.white.opacity(0.14), in: Circle())
                    }
                    .accessibilityLabel("关闭二维码")
                }
                Spacer(minLength: 12)
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .padding(20)
                    .background(.white, in: RoundedRectangle(cornerRadius: 22))
                    .padding(.horizontal, 8)
                    .accessibilityLabel("Apple Store 取货二维码")
                Text("请将此二维码出示给 Apple Store 员工")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.75))
                Spacer(minLength: 12)
            }
            .padding(24)
        }
        .statusBarHidden()
    }
}
