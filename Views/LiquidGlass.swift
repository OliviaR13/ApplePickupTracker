import SwiftUI

/// Groups nearby Liquid Glass surfaces so they sample one shared region.
/// On iOS 17–18 the container is a no-op and each surface uses its own fallback.
struct LiquidGlassGroup<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder var content: () -> Content

    var body: some View {
        if #available(iOS 26, *) {
            glassContainer
        } else {
            content()
        }
    }

    @available(iOS 26, *)
    private var glassContainer: some View {
        GlassEffectContainer(spacing: spacing) {
            content()
        }
    }
}

private struct LiquidGlassModifier<S: Shape>: ViewModifier {
    var shape: S

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            glass(content)
        } else {
            content.background(.ultraThinMaterial, in: shape)
        }
    }

    @available(iOS 26, *)
    private func glass(_ content: Content) -> some View {
        content.glassEffect(.regular, in: shape)
    }
}

private struct ProminentGlassButtonModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            prominent(content)
        } else {
            content.buttonStyle(.borderedProminent)
        }
    }

    @available(iOS 26, *)
    private func prominent(_ content: Content) -> some View {
        content.buttonStyle(.glassProminent)
    }
}

private struct ToolbarGlassButtonModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            glass(content)
        } else {
            content
        }
    }

    @available(iOS 26, *)
    private func glass(_ content: Content) -> some View {
        content.buttonStyle(.glass)
    }
}

private struct GlassButtonModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            glass(content)
        } else {
            content.buttonStyle(.bordered)
        }
    }

    @available(iOS 26, *)
    private func glass(_ content: Content) -> some View {
        content.buttonStyle(.glass)
    }
}

extension View {
    /// Liquid Glass plate on iOS 26. Falls back to ultra-thin material.
    func liquidGlass<S: Shape>(in shape: S) -> some View {
        modifier(LiquidGlassModifier(shape: shape))
    }

    /// Primary action. Uses the system prominent glass button on iOS 26.
    func liquidGlassProminentButton() -> some View {
        modifier(ProminentGlassButtonModifier())
    }

    /// Secondary action. Uses the system glass button on iOS 26.
    func liquidGlassButton() -> some View {
        modifier(GlassButtonModifier())
    }

    /// Navigation-bar control. iOS 26 draws the system glass toolbar button;
    /// earlier systems keep the plain toolbar item.
    func toolbarGlassButton() -> some View {
        modifier(ToolbarGlassButtonModifier())
    }
}
