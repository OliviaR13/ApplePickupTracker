import ActivityKit
import SwiftUI
import WidgetKit

struct PickupLiveActivityView: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PickupAttributes.self) { context in
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("APPLE STORE PICKUP", systemImage: "bag")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Text(context.state.status.title).font(.caption.weight(.semibold))
                }
                Text(context.attributes.productName).font(.headline)
                ProgressView(value: context.state.status.progress)
                    .tint(context.state.status == .readyForPickup ? .green : .primary)
                HStack {
                    Text(context.state.storeName).lineLimit(1)
                    Spacer()
                    Text(context.state.lastUpdated, style: .time)
                }.font(.caption2).foregroundStyle(.secondary)
            }
            .padding()
            .activityBackgroundTint(Color(uiColor: .secondarySystemBackground))
            .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "bag.fill").font(.title2)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.status.title).font(.caption.weight(.semibold))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(context.attributes.productName).font(.headline)
                        ProgressView(value: context.state.status.progress)
                        Text(context.state.storeName).font(.caption2).foregroundStyle(.secondary)
                    }.padding(.top, 4)
                }
            } compactLeading: {
                Image(systemName: "bag.fill")
            } compactTrailing: {
                Text(context.state.status == .readyForPickup ? "Ready" : "•")
                    .font(.caption2.weight(.bold))
            } minimal: {
                Image(systemName: "bag.fill")
            }
            .keylineTint(context.state.status == .readyForPickup ? .green : .primary)
        }
    }
}

@main
struct PickupWidgetBundle: WidgetBundle {
    var body: some Widget { PickupLiveActivityView() }
}
