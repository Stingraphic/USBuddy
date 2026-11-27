import PhotosUI
import QuickLook
import SwiftUI
import UniformTypeIdentifiers

struct FileBrowserView: View {
    @Bindable var manager: USBDriveManager
    @Binding var navigationPath: NavigationPath

    @State private var isSelecting = false
    @State private var selectedIDs: Set<URL> = []
    @State private var previewURL: URL?

    @State private var showFileImporter = false
    @State private var showPhotoPicker = false
    @State private var selectedPhotos: [PhotosPickerItem] = []

    @State private var showNewFolderAlert = false
    @State private var newFolderName = ""

    @State private var renameTarget: USBFileItem?
    @State private var renameText = ""

    @State private var showDeleteSelectedConfirm = false

    var body: some View {
        ZStack(alignment: .bottom) {
            MeshGlassBackground()

            VStack(spacing: 12) {
                breadcrumbBar

                searchBar

                storageStatusStrip

                fileList
            }

            if isSelecting {
                multiSelectBottomBar
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .navigationTitle(manager.currentDirectoryURL?.lastPathComponent ?? "全部文件")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    withAnimation(.snappy) {
                        isSelecting.toggle()
                        selectedIDs.removeAll()
                    }
                } label: {
                    Text(isSelecting ? "完成" : "选择")
                        .fontWeight(.medium)
                }

                Menu {
                    Menu("排序方式") {
                        ForEach(FileSortOption.allCases) { option in
                            Button {
                                manager.sortOption = option
                            } label: {
                                if manager.sortOption == option {
                                    Label(option.rawValue, systemImage: "checkmark")
                                } else {
                                    Text(option.rawValue)
                                }
                            }
                        }
                    }

                    Toggle("显示 .xxxx 隐藏文件", isOn: $manager.showHiddenDotFiles)

                    Divider()

                    Button {
                        showPhotoPicker = true
                    } label: {
                        Label("从相册导入到当前目录", systemImage: "photo.on.rectangle")
                    }

                    Button {
                        showFileImporter = true
                    } label: {
                        Label("从文件导入到当前目录", systemImage: "doc.badge.plus")
                    }

                    Button {
                        showNewFolderAlert = true
                    } label: {
                        Label("新建文件夹", systemImage: "folder.badge.plus")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .quickLookPreview($previewURL)
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                Task { await manager.importFiles(urls: urls) }
            }
        }
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $selectedPhotos,
            matching: .any(of: [.images, .videos])
        )
        .onChange(of: selectedPhotos) { _, items in
            guard !items.isEmpty else { return }
            Task {
                await handlePhotoImports(items)
                selectedPhotos = []
            }
        }
        .alert("新建文件夹", isPresented: $showNewFolderAlert) {
            TextField("文件夹名称", text: $newFolderName)
            Button("取消", role: .cancel) { newFolderName = "" }
            Button("创建") {
                let name = newFolderName
                newFolderName = ""
                Task { await manager.createFolder(named: name) }
            }
        }
        .alert("重命名", isPresented: Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )) {
            TextField("新名称", text: $renameText)
            Button("取消", role: .cancel) { renameTarget = nil }
            Button("确定") {
                if let target = renameTarget {
                    let next = renameText
                    renameTarget = nil
                    Task { await manager.renameItem(target, to: next) }
                }
            }
        }
        .confirmationDialog(
            "确认删除选中的 \(selectedIDs.count) 项？",
            isPresented: $showDeleteSelectedConfirm,
            titleVisibility: .visible
        ) {
            Button("永久删除", role: .destructive) {
                let targets = manager.filteredEntries.filter { selectedIDs.contains($0.id) }
                selectedIDs.removeAll()
                isSelecting = false
                Task { await manager.deleteItems(targets) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("U 盘上的文件删除后将无法从系统废纸篓恢复。")
        }
    }

    // MARK: - Subviews

    private var breadcrumbBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(manager.breadcrumbs.enumerated()), id: \.element) { index, url in
                    Button {
                        manager.navigate(to: url)
                    } label: {
                        Text(index == 0 ? "根目录" : url.lastPathComponent)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(url == manager.currentDirectoryURL ? .primary : .secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                    }
                    .glassEffect(.regular.interactive(), in: .capsule)

                    if index < manager.breadcrumbs.count - 1 {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.top, 4)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("搜索当前目录文件名", text: $manager.searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !manager.searchText.isEmpty {
                Button {
                    manager.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal, 20)
    }

    private var storageStatusStrip: some View {
        HStack(spacing: 6) {
            Image(systemName: "externaldrive")
                .font(.caption2)
            Text("U 盘剩余 \(manager.driveStats.formattedRemainingShort)")
                .font(.caption.weight(.medium))
            Spacer()
            Text("共 \(manager.driveStats.formattedTotal)")
                .font(.caption2)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 22)
    }

    private var fileList: some View {
        List {
            ForEach(manager.filteredEntries) { item in
                fileRow(item)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 5, leading: 20, bottom: 5, trailing: 20))
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button {
                            Task {
                                try? await Task.sleep(for: .milliseconds(150))
                                await manager.deleteItems([item])
                            }
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                        .tint(.red)
                    }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .overlay {
            if manager.filteredEntries.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "folder")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("当前目录没有文件")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .refreshable {
            if let current = manager.currentDirectoryURL {
                await manager.loadDirectory(current)
            }
        }
    }

    private func fileRow(_ item: USBFileItem) -> some View {
        let isChecked = selectedIDs.contains(item.id)

        return Button {
            if isSelecting {
                if isChecked {
                    selectedIDs.remove(item.id)
                } else {
                    selectedIDs.insert(item.id)
                }
            } else if item.isDirectory {
                manager.navigate(to: item.url)
            } else {
                previewURL = item.url
            }
        } label: {
            HStack(spacing: 12) {
                if isSelecting {
                    Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isChecked ? Color.primary : Color.secondary)
                }

                Image(systemName: item.systemIconName)
                    .font(.body)
                    .foregroundStyle(item.isJunk ? .orange : .primary)
                    .frame(width: 38, height: 38)
                    .background(.white.opacity(0.14), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        if item.isJunk {
                            Text(".xxxx 残留")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.orange)
                        }
                        Text(item.formattedSize)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if !isSelecting && item.isDirectory {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .contextMenu {
            if !item.isDirectory {
                Button {
                    previewURL = item.url
                } label: {
                    Label("预览", systemImage: "eye")
                }

                ShareLink(item: item.url) {
                    Label("导出 / 分享到 iPhone", systemImage: "square.and.arrow.up")
                }
            }

            Button {
                renameTarget = item
                renameText = item.name
            } label: {
                Label("重命名", systemImage: "pencil")
            }

            Button(role: .destructive) {
                Task { await manager.deleteItems([item]) }
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    private var multiSelectBottomBar: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    let allIDs = Set(manager.filteredEntries.map(\.id))
                    if selectedIDs.count == allIDs.count {
                        selectedIDs.removeAll()
                    } else {
                        selectedIDs = allIDs
                    }
                } label: {
                    Text(selectedIDs.count == manager.filteredEntries.count && !selectedIDs.isEmpty ? "取消全选" : "全选")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16)
                        .frame(height: 48)
                }
                .glassEffect(.regular.interactive(), in: .capsule)

                let junkInDir = manager.filteredEntries.filter(\.isJunk)
                if !junkInDir.isEmpty {
                    Button {
                        Task { await manager.deleteItems(junkInDir) }
                    } label: {
                        Text("清本页垃圾(\(junkInDir.count))")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .frame(height: 48)
                    }
                    .glassEffect(.regular.interactive(), in: .capsule)
                }

                Spacer()

                Button {
                    showDeleteSelectedConfirm = true
                } label: {
                    Text("删除(\(selectedIDs.count))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .frame(height: 48)
                        .background(selectedIDs.isEmpty ? Color.gray : Color.red, in: Capsule())
                }
                .disabled(selectedIDs.isEmpty)
                .glassEffect(.regular.interactive(), in: .capsule)
            }
        }
    }

    private func handlePhotoImports(_ items: [PhotosPickerItem]) async {
        manager.beginImportProgress(total: items.count)
        defer { manager.endImportProgress() }

        var successCount = 0
        for (idx, item) in items.enumerated() {
            let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
            let filename = "IMG_\(Int(Date().timeIntervalSince1970))_\(idx + 1).\(ext)"
            manager.updateImportProgress(current: idx + 1, fileName: filename)

            if let data = try? await item.loadTransferable(type: Data.self) {
                if await manager.importPhotoData(data, filename: filename) {
                    successCount += 1
                }
            }
        }
        await manager.refreshAll()
        if successCount > 0 {
            manager.statusMessage = "已成功导入 \(successCount) 张照片/视频到当前目录"
        }
    }
}
