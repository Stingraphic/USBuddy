import QuickLook
import SwiftUI

private enum DuplicateFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case similarName = "相似文件名"
    case exactHash = "内容相同"

    var id: String { rawValue }
}

struct DuplicateFilesSheet: View {
    @Bindable var manager: USBDriveManager
    @Environment(\.dismiss) private var dismiss

    @State private var selectedFilter: DuplicateFilter = .all
    @State private var selectedIDs: Set<URL> = []
    @State private var previewURL: URL?
    @State private var showDeleteConfirm = false

    private var filteredGroups: [DuplicateGroup] {
        switch selectedFilter {
        case .all:
            manager.duplicateGroups
        case .similarName:
            manager.duplicateGroups.filter { $0.matchType == .similarName }
        case .exactHash:
            manager.duplicateGroups.filter { $0.matchType == .exactHash }
        }
    }

    private var selectedItems: [USBFileItem] {
        manager.duplicateGroups
            .flatMap(\.items)
            .filter { selectedIDs.contains($0.id) }
    }

    private var selectedBytes: Int64 {
        selectedItems.reduce(0) { $0 + $1.size }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                MeshGlassBackground()

                if manager.isScanningDuplicates {
                    scanningView
                } else if manager.duplicateGroups.isEmpty {
                    emptyView
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            summaryCard

                            Picker("筛选类型", selection: $selectedFilter) {
                                ForEach(DuplicateFilter.allCases) { filter in
                                    Text(filter.rawValue).tag(filter)
                                }
                            }
                            .pickerStyle(.segmented)

                            ForEach(filteredGroups) { group in
                                groupCard(group)
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 12)
                        .padding(.bottom, selectedItems.isEmpty ? 28 : 96)
                    }
                }

                if !selectedItems.isEmpty && !manager.isScanningDuplicates {
                    bottomActionBar
                        .padding(.horizontal, 18)
                        .padding(.bottom, 14)
                }
            }
            .navigationTitle("重复文件识别")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            await manager.scanDuplicates()
                            selectAllExtraCopies()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(manager.isScanningDuplicates || manager.isProcessing)
                }
            }
        }
        .preferredColorScheme(.dark)
        .quickLookPreview($previewURL)
        .task {
            if !manager.hasScannedDuplicates {
                await manager.scanDuplicates()
            }
            selectAllExtraCopies()
        }
        .confirmationDialog(
            "确认删除选中的 \(selectedItems.count) 个重复文件？",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button(
                "删除并释放 \(ByteCountFormatter.string(fromByteCount: selectedBytes, countStyle: .file))",
                role: .destructive
            ) {
                let targets = selectedItems
                Task {
                    await manager.cleanDuplicateFiles(targets)
                    selectAllExtraCopies()
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后将直接从 U 盘移除所选副本，建议每组至少保留 1 份原文件。")
        }
    }

    // MARK: - Subviews

    private var scanningView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
                .tint(.white)

            Text("正在扫描相似文件名与 SHA-256 哈希...")
                .font(.headline)

            Text("自动识别 xxx 2 / (1) / 副本 等相似命名，以及内容完全相同的重复文件")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("没有发现重复文件")
                .font(.title3.bold())

            Text("已扫描 \(manager.scannedFileCountForDuplicates) 个文件，未发现相似文件名或内容重复")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

            Button {
                Task {
                    await manager.scanDuplicates()
                    selectAllExtraCopies()
                }
            } label: {
                Text("重新扫描")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 10)
                    .background(Color.white, in: Capsule())
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var summaryCard: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("发现 \(manager.duplicateGroups.count) 组共 \(manager.duplicateTotalCount) 个重复副本")
                    .font(.headline)

                Text("全部清理最多可释放 \(manager.formattedDuplicateReclaimableSize)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                if selectedItems.count == manager.duplicateTotalCount {
                    selectedIDs.removeAll()
                } else {
                    selectAllExtraCopies()
                }
            } label: {
                Text(selectedItems.count == manager.duplicateTotalCount ? "取消全选" : "智能全选")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white, in: Capsule())
            }
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }

    private func groupCard(_ group: DuplicateGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(group.items.first?.name ?? "重复文件")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                Text(group.matchType.rawValue)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(group.matchType == .similarName ? .orange : .cyan)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(
                        (group.matchType == .similarName ? Color.orange : Color.cyan).opacity(0.16),
                        in: Capsule()
                    )

                Spacer()

                Text("\(group.items.count) 份")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                    let isSelected = selectedIDs.contains(item.id)
                    HStack(spacing: 10) {
                        Button {
                            toggleSelection(item.id)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(isSelected ? Color.white : Color.secondary)

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(item.name)
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)

                                        if index == 0 {
                                            Text("建议保留")
                                                .font(.caption2.weight(.semibold))
                                                .foregroundStyle(.green)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(.green.opacity(0.16), in: Capsule())
                                        }
                                    }

                                    Text("\(item.formattedSize) · \(relativePath(for: item.url))")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }

                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)

                        Button {
                            previewURL = item.url
                        } label: {
                            Image(systemName: "eye")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 30, height: 30)
                                .background(.white.opacity(0.08), in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }

    private var bottomActionBar: some View {
        Button {
            showDeleteConfirm = true
        } label: {
            HStack(spacing: 8) {
                if manager.isProcessing {
                    ProgressView()
                        .tint(.black)
                        .scaleEffect(0.85)
                }
                Text("删除选中的 \(selectedItems.count) 个重复文件（释放 \(ByteCountFormatter.string(fromByteCount: selectedBytes, countStyle: .file))）")
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

    // MARK: - Helpers

    private func toggleSelection(_ id: URL) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    private func selectAllExtraCopies() {
        var next: Set<URL> = []
        for group in manager.duplicateGroups {
            for (index, item) in group.items.enumerated() where index > 0 {
                next.insert(item.id)
            }
        }
        selectedIDs = next
    }

    private func relativePath(for url: URL) -> String {
        guard let rootPath = manager.rootURL?.standardizedFileURL.path else {
            return url.path
        }
        let itemPath = url.standardizedFileURL.path
        if itemPath.hasPrefix(rootPath) {
            let suffix = String(itemPath.dropFirst(rootPath.count))
            return suffix.isEmpty ? "/" : suffix
        }
        return itemPath
    }
}
