import SwiftUI

struct OrderDetailView: View {
    let order: PickupOrder
    @State private var liveActivity = LiveActivityManager()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(order.status.title).font(.largeTitle.bold())
                    Text(order.status.detail).font(.body).foregroundStyle(.secondary)
                    ProgressView(value: order.status.progress).tint(order.status == .readyForPickup ? .green : .primary).padding(.top, 8)
                }
                .padding(20).frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))

                VStack(alignment: .leading, spacing: 12) {
                    Label("订单详情", systemImage: "shippingbox")
                        .font(.headline)
                    detailRow("商品", order.productName)
                    detailRow("取货门店", order.storeName)
                    detailRow("订单编号", order.orderNumber)
                    detailRow("最后更新", order.lastUpdated.formatted(date: .abbreviated, time: .shortened))
                }.padding(18).background(.background, in: RoundedRectangle(cornerRadius: 18)).overlay(RoundedRectangle(cornerRadius: 18).stroke(.quaternary))

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
                }.padding(18).background(.background, in: RoundedRectangle(cornerRadius: 18)).overlay(RoundedRectangle(cornerRadius: 18).stroke(.quaternary))

                Button {
                    Task { await liveActivity.startOrUpdate(for: order) }
                } label: {
                    Label("在锁定屏幕和灵动岛显示", systemImage: "rectangle.inset.filled.bottom")
                        .frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent).controlSize(.large)
            }.padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("订单详情")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value).multilineTextAlignment(.trailing).textSelection(.enabled)
        }.font(.subheadline)
    }
}
