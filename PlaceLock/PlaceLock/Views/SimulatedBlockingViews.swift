import SwiftUI

/// Stand-in for Apple's FamilyActivityPicker while blocking is simulated (free developer account).
struct SimulatedAppPicker: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var picked: Set<String> = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(SimulatedApps.all, id: \.name) { app in
                        Button {
                            if picked.contains(app.name) { picked.remove(app.name) } else { picked.insert(app.name) }
                        } label: {
                            HStack {
                                Label(app.name, systemImage: app.symbol).foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: picked.contains(app.name) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(picked.contains(app.name) ? Color.accentColor : .secondary)
                            }
                        }
                    }
                } footer: {
                    Text("Stand-in list. With the paid developer account this becomes Apple's Screen Time picker showing your real apps.")
                }
            }
            .navigationTitle("Choose apps")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { picked = Set(model.blockList.simulatedApps) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        // Keep the list's order for display.
                        model.blockList.simulatedApps = SimulatedApps.all.map(\.name).filter(picked.contains)
                        dismiss()
                    }
                }
            }
        }
    }
}

/// What opening a blocked app would look like. With real Screen Time this is the system shield.
/// Same words as the real one (`ShieldConfigurationExtension`).
struct MockShieldView: View {
    let appName: String
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: SimulatedApps.symbol(for: appName))
                .font(.system(size: 56)).foregroundStyle(.secondary)
            Image(systemName: "lock.fill").font(.title).foregroundStyle(.tint)
            Text("\(appName) is locked").font(.title2.bold())
            Text(Brand.opensAt(model.places.filter { $0.isActive() }.map(\.name)))
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Spacer()
            Button(Brand.shieldButton) { dismiss() }
                .buttonStyle(.borderedProminent).controlSize(.large)
            Text("Simulated block screen").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(32)
    }
}
