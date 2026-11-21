import SwiftUI
import UIKit

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


/// Warm neutral surfaces and a restrained teal accent, adapted from MyLoon's visual system.
enum TrackerTheme {
    static let background = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 18/255, green: 17/255, blue: 15/255, alpha: 1)
            : UIColor(red: 246/255, green: 244/255, blue: 239/255, alpha: 1)
    })
    static let card = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 25/255, green: 24/255, blue: 21/255, alpha: 1)
            : UIColor(red: 253/255, green: 252/255, blue: 249/255, alpha: 1)
    })
    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 63/255, green: 207/255, blue: 166/255, alpha: 1)
            : UIColor(red: 15/255, green: 127/255, blue: 105/255, alpha: 1)
    })
}
