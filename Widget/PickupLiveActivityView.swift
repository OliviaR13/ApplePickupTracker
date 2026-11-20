import ActivityKit
import SwiftUI
import WidgetKit

/// iOS 17 and later draw an empty capsule when a Live Activity has no `containerBackground`.
/// Dynamic system colors also come out black on that capsule, so every color here is explicit.
struct PickupLiveActivityView: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PickupAttributes.self) { context in
            LockScreenActivity(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    IslandSymbol(status: context.state.status)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    IslandStatus(status: context.state.status)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    IslandDetail(context: context)
                }
            } compactLeading: {
                IslandSymbol(status: context.state.status)
            } compactTrailing: {
                Text(compactStatus(context.state.status))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
            } minimal: {
                IslandSymbol(status: context.state.status)
            }
            .keylineTint(context.state.status == .readyForPickup ? Color(red: 0.18, green: 0.62, blue: 0.34) : Color.white)
        }
    }
}

private struct LockScreenActivity: View {
    @Environment(\.colorScheme) private var colorScheme
    let context: ActivityViewContext<PickupAttributes>

    var body: some View {
        let palette = ActivityPalette(colorScheme)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label(context.state.status.title, systemImage: context.state.status.symbolName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.accent(for: context.state.status))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(context.state.lastUpdated.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(palette.secondary)
            }
            Text(context.attributes.productName)
                .font(.headline)
                .foregroundStyle(palette.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            ActivityProgress(value: context.state.status.progress, tint: palette.accent(for: context.state.status), track: palette.secondary.opacity(0.28))
            Text(context.state.storeName)
                .font(.caption)
                .foregroundStyle(palette.secondary)
                .lineLimit(1)
            if context.isStale {
                Text("信息可能已过期，打开 App 即可刷新")
                    .font(.caption2)
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
            }
        }
        .padding(4)
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
        .activityBackgroundTint(palette.background)
        .activitySystemActionForegroundColor(palette.primary)
        .containerBackground(palette.background, for: .widget)
    }
}

private struct IslandSymbol: View {
    @Environment(\.colorScheme) private var colorScheme
    let status: PickupStatus

    var body: some View {
        Image(systemName: status == .readyForPickup ? "checkmark.circle.fill" : "bag.fill")
            .foregroundStyle(ActivityPalette(colorScheme).accent(for: status))
    }
}

private struct IslandStatus: View {
    let status: PickupStatus

    var body: some View {
        Text(status.title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
    }
}

private struct IslandDetail: View {
    @Environment(\.colorScheme) private var colorScheme
    let context: ActivityViewContext<PickupAttributes>

    var body: some View {
        let accent = ActivityPalette(colorScheme).accent(for: context.state.status)
        VStack(alignment: .leading, spacing: 6) {
            Text(context.attributes.productName)
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(2)
            ActivityProgress(value: context.state.status.progress, tint: accent, track: Color.white.opacity(0.28))
            HStack {
                Text(context.state.storeName).lineLimit(1)
                Spacer(minLength: 8)
                Text(context.state.lastUpdated.formatted(date: .omitted, time: .shortened))
            }
            .font(.caption2)
            .foregroundStyle(Color.white.opacity(0.75))
        }
        .padding(.top, 4)
    }
}

private struct ActivityProgress: View {
    var value: Double
    var tint: Color
    var track: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(tint).frame(width: max(6, geo.size.width * min(max(value, 0), 1)))
            }
        }
        .frame(height: 6)
    }
}

private struct ActivityPalette {
    var background: Color
    var primary: Color
    var secondary: Color

    init(_ scheme: ColorScheme) {
        if scheme == .dark {
            background = Color(red: 0.14, green: 0.15, blue: 0.17)
            primary = Color.white
            secondary = Color.white.opacity(0.72)
        } else {
            background = Color(red: 0.96, green: 0.97, blue: 0.98)
            primary = Color(red: 0.07, green: 0.08, blue: 0.10)
            secondary = Color(red: 0.32, green: 0.34, blue: 0.38)
        }
    }

    func accent(for status: PickupStatus) -> Color {
        switch status {
        case .readyForPickup: Color(red: 0.18, green: 0.62, blue: 0.34)
        case .shippingToStore: Color(red: 0.20, green: 0.46, blue: 0.86)
        case .processing: Color(red: 0.86, green: 0.48, blue: 0.12)
        case .cancelled: Color(red: 0.82, green: 0.22, blue: 0.22)
        case .ordered, .pickedUp, .unknown: secondary
        }
    }
}

private func compactStatus(_ status: PickupStatus) -> String {
    switch status {
    case .readyForPickup: "可取"
    case .shippingToStore: "运送"
    case .processing: "处理"
    case .ordered: "下单"
    case .pickedUp: "已取"
    case .cancelled: "取消"
    case .unknown: "订单"
    }
}

@main
struct PickupWidgetBundle: WidgetBundle {
    var body: some Widget { PickupLiveActivityView() }
}
