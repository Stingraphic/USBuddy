import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ImportHubView: View {
    @Bindable var manager: USBDriveManager

    @State private var showFileImporter = false
    @State private var showPhotoPicker = false
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var showNewFolderAlert = false
    @State private var newFolderName = ""
    @State private var showFolderPicker = false

    var body: some View {
        ZStack {
            MeshGlassBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !manager.isConnected {
                        connectPromptCard
                    } else {
                        targetDirectoryCard
                    }

                    importActionCard(
                        icon: "photo.on.rectangle.angled",
                        title: "从相册导入照片 / 视频",
                        subtitle: "批量选取 iPhone 相册媒体直接写入 U 盘当前目录",
                        buttonTitle: "选择照片或视频"
                    ) {
                        if manager.isConnected {
                            showPhotoPicker = true
                        } else {
                            manager.openDrivePicker()
                        }
                    }

                    importActionCard(
                        icon: "doc.badge.plus",
                        title: "从「文件」App 导入文档",
                        subtitle: "支持导入音乐、压缩包、PDF、文档等任意格式到 U 盘",
                        buttonTitle: "选择文件"
                    ) {
                        if manager.isConnected {
                            showFileImporter = true
                        } else {
                            manager.openDrivePicker()
                        }
                    }

                    importActionCard(
                        icon: "folder.badge.plus",
                        title: "在 U 盘中新建文件夹",
                        subtitle: "整理分类目录，方便归档照片、音乐与工作文档",
                        buttonTitle: "新建文件夹"
                    ) {
                        if manager.isConnected {
                            showNewFolderAlert = true
                        } else {
                            manager.openDrivePicker()
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("导入到 U 盘")
        .navigationBarTitleDisplayMode(.large)
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
        .sheet(isPresented: $showFolderPicker) {
            FolderPickerSheet(manager: manager)
        }
    }

    private var connectPromptCard: some View {
        HStack(spacing: 14) {
            Image("USBMascot")
                .resizable()
                .scaledToFit()
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text("尚未选择 U 盘")
                    .font(.headline)
                Text("请先选择你的 C 口 U 盘目录后再导入")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("选择") {
                manager.openDrivePicker()
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.white, in: Capsule())
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }

    private var targetDirectoryCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .font(.title3)
                .frame(width: 40, height: 40)
                .background(.white.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text("导入目标 · \(manager.driveStats.formattedAvailable)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(targetFolderDisplayPath)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button {
                showFolderPicker = true
            } label: {
                Text("选择文件夹")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.white, in: Capsule())
            }
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }

    private var targetFolderDisplayPath: String {
        guard let root = manager.rootURL?.standardizedFileURL,
              let current = manager.currentDirectoryURL?.standardizedFileURL else {
            return manager.driveStats.driveName
        }
        if root == current {
            return "\(manager.driveStats.driveName)（根目录）"
        }
        if current.path.hasPrefix(root.path) {
            let suffix = String(current.path.dropFirst(root.path.count))
            return suffix.isEmpty ? manager.driveStats.driveName : suffix
        }
        return current.lastPathComponent
    }

    private func importActionCard(
        icon: String,
        title: String,
        subtitle: String,
        buttonTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                    .frame(width: 42, height: 42)
                    .background(.white.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Button(action: action) {
                Text(manager.isConnected ? buttonTitle : "先选择 U 盘")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color.white, in: Capsule())
            }
            .disabled(manager.isProcessing)
        }
        .padding(18)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
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
            manager.statusMessage = "已成功导入 \(successCount) 张照片/视频到 U 盘"
        }
    }
}
