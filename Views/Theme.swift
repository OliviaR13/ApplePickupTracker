import SwiftUI
import UIKit

// App-only styling. Kept out of PickupOrder.swift because the widget target compiles that file alone.

extension PickupStatus {
    var tint: Color {
        switch self {
        case .readyForPickup: Color(uiColor: .systemGreen)
        case .shippingToStore: Color(uiColor: .systemBlue)
        case .processing: Color(uiColor: .systemOrange)
        case .cancelled: Color(uiColor: .systemRed)
        case .ordered: Color(uiColor: .systemIndigo)
        case .pickedUp: Color(uiColor: .systemTeal)
        case .completed: Color(uiColor: .systemGreen)
        case .unknown: Color(uiColor: .systemGray)
        }
    }

    var gradient: LinearGradient {
        LinearGradient(colors: [tint, tint.opacity(0.68)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// A translucent card that uses native Liquid Glass on iOS 26 and material fallback on older systems.
struct ContentCard<Content: View>: View {
    var cornerRadius: CGFloat = TrackerTheme.Radius.card
    @ViewBuilder var content: () -> Content

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    var body: some View {
        content()
            .padding(TrackerTheme.Spacing.cardInset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TrackerTheme.card, in: shape)
            .overlay {
                shape.strokeBorder(TrackerTheme.separator.opacity(0.24), lineWidth: 0.5)
            }
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


/// Semantic design tokens shared by every app screen.
enum TrackerTheme {
    // Surfaces
    static let background = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let elevatedSurface = Color(uiColor: .systemBackground)
    static let separator = Color(uiColor: .separator)
    static let accent = Color.accentColor

    // Text roles. Prefer these semantic styles over fixed white/black values.
    enum Text {
        static let primary = Color.primary
        static let secondary = Color.secondary
        static let tertiary = Color(uiColor: .tertiaryLabel)
    }

    // Layout tokens
    enum Spacing {
        static let compact: CGFloat = 8
        static let regular: CGFloat = 12
        static let section: CGFloat = 18
        static let cardInset: CGFloat = 18
        static let screenInset: CGFloat = 16
    }

    enum Radius {
        static let control: CGFloat = 12
        static let card: CGFloat = 20
        static let prominent: CGFloat = 24
    }

    // Typography uses system text styles, preserving Dynamic Type behavior.
    enum TypeScale {
        static let caption = Font.caption
        static let footnote = Font.footnote
        static let body = Font.body
        static let headline = Font.headline
        static let title = Font.title
        static let largeTitle = Font.largeTitle
    }
}
