import SwiftUI

struct AddOrderView: View {
    @EnvironmentObject private var store: OrderStore
    @Environment(\.dismiss) private var dismiss

    @State private var orderNumber = ""
    @State private var productName = ""
    @State private var storeName = ""
    @State private var status: PickupStatus = .ordered
    @State private var errorMessage: String?

    private let selectable: [PickupStatus] = [.ordered, .processing, .shippingToStore, .readyForPickup, .pickedUp, .cancelled]

    private var trimmedNumber: String { orderNumber.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
    private var trimmedProduct: String { productName.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool { !trimmedNumber.isEmpty && !trimmedProduct.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section("订单") {
                    TextField("商品名称", text: $productName)
                    TextField("订单编号，例如 W1234567890", text: $orderNumber)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }
                Section {
                    TextField("取货门店（选填）", text: $storeName)
                    Picker("当前状态", selection: $status) {
                        ForEach(selectable, id: \.self) { Text($0.title).tag($0) }
                    }
                } header: {
                    Text("取货")
                } footer: {
                    Text("之后同步到同一订单编号的 Apple 邮件时，状态会自动更新。")
                }
            }
            .navigationTitle("手动添加订单")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { Button("添加") { save() }.disabled(!canSave) }
            }
            .alert("无法添加", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("好", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
    }

    private func save() {
        guard store.order(withNumber: trimmedNumber) == nil else {
            errorMessage = "已经有相同订单编号的订单了。"
            return
        }
        store.addManual(orderNumber: trimmedNumber,
                        product: trimmedProduct,
                        store: storeName.trimmingCharacters(in: .whitespacesAndNewlines),
                        status: status)
        dismiss()
    }
}
