import SwiftUI

struct CleanupProgressSheet: View {
    @Bindable var manager: USBDriveManager
    @Environment(\.dismiss) private var dismiss

    private var progressRatio: Double {
        guard manager.cleanupTotalCount > 0 else { return 0 }
        return min(1.0, Double(manager.cleanupProcessedCount) / Double(manager.cleanupTotalCount))
    }

    private var formattedFreed: String {
        ByteCountFormatter.string(fromByteCount: manager.cleanupFreedBytes, countStyle: .file)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                MeshGlassBackground()

                VStack(spacing: 14) {
                    progressHeaderCard

                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(manager.cleanupLogs) { entry in
                                HStack(spacing: 10) {
                                    Image(systemName: entry.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .font(.body)
                                        .foregroundStyle(entry.succeeded ? .green : .red)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.name)
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)

                                        Text(entry.path)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }

                                    Spacer()

                                    Text(entry.formattedSize)
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .glassEffect(.regular, in: .rect(cornerRadius: 14))
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.bottom, manager.isCleaningJunk ? 24 : 92)
                    }
                }
                .padding(.top, 10)

                if !manager.isCleaningJunk {
                    Button {
                        dismiss()
                    } label: {
                        Text("完成")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.white, in: Capsule())
                            .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 14)
                }
            }
            .navigationTitle(manager.isCleaningJunk ? "正在清理隐藏文件" : "清理完成")
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(manager.isCleaningJunk)
    }

    private var progressHeaderCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                if manager.isCleaningJunk {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.85)
                } else {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                }

                Text(
                    manager.isCleaningJunk
                    ? "正在删除（\(manager.cleanupProcessedCount)/\(manager.cleanupTotalCount)）"
                    : "已清理 \(manager.cleanupDeletedCount) 个隐藏文件"
                )
                .font(.headline)

                Spacer()

                Text("释放 \(formattedFreed)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: progressRatio, total: 1.0)
                .tint(.white)

            if manager.isCleaningJunk && !manager.cleanupCurrentFileName.isEmpty {
                Text("当前：\(manager.cleanupCurrentFileName)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .padding(.horizontal, 18)
    }
}
