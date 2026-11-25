import SwiftUI

struct JunkRulesSheet: View {
    @Bindable var manager: USBDriveManager
    var showDoneButton: Bool = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                MeshGlassBackground()

                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(JunkCategory.allCases) { category in
                            let isOn = manager.enabledCategories.contains(category)
                            Button {
                                if isOn {
                                    manager.enabledCategories.remove(category)
                                } else {
                                    manager.enabledCategories.insert(category)
                                }
                            } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                                        .font(.title3)
                                        .foregroundStyle(isOn ? Color.primary : Color.secondary)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(category.title)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.primary)
                                        Text(category.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .multilineTextAlignment(.leading)
                                    }

                                    Spacer()
                                }
                                .padding(16)
                                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("垃圾清理规则")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if showDoneButton {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("完成") {
                            Task { await manager.refreshAll() }
                            dismiss()
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
        }
    }
}
