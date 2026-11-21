import SwiftUI

// App-only styling. Kept out of PickupOrder.swift because the widget target compiles that file alone.

extension PickupStatus {
    var tint: Color {
        switch self {
        case .readyForPickup: .green
        case .shippingToStore: .blue
        case .processing: .orange
        case .cancelled: .red
        case .ordered: .indigo
        case .pickedUp: .teal
        case .completed: .green
        case .unknown: .gray
        }
    }

    var gradient: LinearGradient {
        LinearGradient(colors: [tint, tint.opacity(0.68)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// A rounded glass plate with the standard card padding.
struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 20
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlass(in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

struct StatusBadge: View {
    let status: PickupStatus
    var body: some View {
        Label(status.title, systemImage: status.symbolName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(status.tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(status.tint.opacity(0.14), in: Capsule())
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}
