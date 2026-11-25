import SwiftUI

struct ImportConflictSheet: View {
    @Bindable var manager: USBDriveManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                MeshGlassBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        headerSummaryCard

                        ForEach($manager.pendingImportConflicts) { $item in
                            conflictCard(item: $item)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
                    .padding(.bottom, 96)
                }

                bottomConfirmButton
                    .padding(.horizontal, 18)
                    .padding(.bottom, 14)
            }
            .navigationTitle("同名文件处理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") {
                        manager.clearImportConflicts()
                        dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(manager.isProcessing)
    }

    // MARK: - Subviews

    private var headerSummaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("发现 \(manager.pendingImportConflicts.count) 个同名文件")
                    .font(.headline)

                Text(
                    manager.lastImportSuccessCount > 0
                    ? "其余 \(manager.lastImportSuccessCount) 个无冲突文件已直接导入，请选择以下同名文件要保留哪一个"
                    : "目标目录已存在同名文件，请选择要保留原文件、新文件还是两个都保留"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                batchButton("全留原文件", choice: .keepExisting)
                batchButton("全留新文件", choice: .keepNew)
                batchButton("全部都保留", choice: .keepBoth)
            }
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }

    private func batchButton(_ title: String, choice: ImportConflictChoice) -> some View {
        Button {
            for index in manager.pendingImportConflicts.indices {
                manager.pendingImportConflicts[index].choice = choice
            }
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    private func conflictCard(item: Binding<ImportConflictItem>) -> some View {
        let value = item.wrappedValue

        return VStack(alignment: .leading, spacing: 12) {
            Text(value.fileName)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)

            VStack(spacing: 8) {
                fileInfoRow(
                    label: "U 盘原文件",
                    badgeColor: .orange,
                    sizeText: value.formattedExistingSize,
                    date: value.existingDate
                )

                fileInfoRow(
                    label: "新导入文件",
                    badgeColor: .cyan,
                    sizeText: value.formattedNewSize,
                    date: value.newDate
                )
            }

            HStack(spacing: 8) {
                ForEach(ImportConflictChoice.allCases) { choice in
                    let isSelected = value.choice == choice
                    Button {
                        item.wrappedValue.choice = choice
                    } label: {
                        Text(choice.rawValue)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(isSelected ? .black : .white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(
                                isSelected ? Color.white : Color.white.opacity(0.08),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }

    private func fileInfoRow(
        label: String,
        badgeColor: Color,
        sizeText: String,
        date: Date?
    ) -> some View {
        HStack {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(badgeColor)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(badgeColor.opacity(0.16), in: Capsule())

            Spacer()

            Text(sizeText)
                .font(.caption)
                .foregroundStyle(.primary)

            if let date {
                Text("· \(date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var bottomConfirmButton: some View {
        Button {
            Task {
                await manager.resolveImportConflicts()
            }
        } label: {
            HStack(spacing: 8) {
                if manager.isProcessing {
                    ProgressView()
                        .tint(.black)
                        .scaleEffect(0.85)
                }
                Text("确认应用选择（\(manager.pendingImportConflicts.count) 项）")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.white, in: Capsule())
            .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
        }
        .disabled(manager.isProcessing)
    }
}
