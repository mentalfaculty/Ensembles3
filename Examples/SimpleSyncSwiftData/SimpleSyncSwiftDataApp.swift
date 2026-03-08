import SwiftUI
import EnsemblesSwiftData

/// A minimal SwiftData app demonstrating Ensembles sync between two
/// simulated devices. Both share a local cloud directory so you can
/// see sync working without multiple devices or CloudKit setup.
@main
struct SimpleSyncSwiftDataApp: App {
    @State private var device1 = SyncController(name: "Device1")
    @State private var device2 = SyncController(name: "Device2")

    var body: some Scene {
        WindowGroup {
            HStack(spacing: 0) {
                DevicePanel(title: "Device 1")
                    .modelContainer(device1.container.modelContainer)
                Divider()
                DevicePanel(title: "Device 2")
                    .modelContainer(device2.container.modelContainer)
            }
        }
    }
}

struct DevicePanel: View {
    let title: String

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.top, 12)
            DeviceView()
        }
        .frame(maxWidth: .infinity)
    }
}
