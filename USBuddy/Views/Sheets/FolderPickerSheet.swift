import SwiftUI

struct FolderPickerSheet: View {
    @Bindable var manager: USBDriveManager
    @Environment(\.dismiss) private var dismiss

    @State private var folders: [URL] = []
    @State private var isLoading = true
    @State private var showNewFolderAlert = false
    @State private var newFolderName = ""

    var body: some View {
        NavigationStack {
            ZStack {
                MeshGlassBackground()

                if isLoading {
                    ProgressView("正在读取 U 盘目录...")
                        .tint(.white)
                } else {
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(folders, id: \.self) { folderURL in
                                let isSelected = folderURL.standardizedFileURL == manager.currentDirectoryURL?.standardizedFileURL
                                Button {
                                    manager.navigate(to: folderURL)
                                    dismiss()
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: folderURL == manager.rootURL ? "externaldrive.fill" : "folder.fill")
                                            .font(.body)
                                            .foregroundStyle(isSelected ? .black : .primary)
                                            .frame(width: 36, height: 36)
                                            .background(isSelected ? Color.white : Color.white.opacity(0.12), in: Circle())

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(displayName(for: folderURL))
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(.primary)
                                                .lineLimit(1)

                                            Text(relativePath(for: folderURL))
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                        }

                                        Spacer()

                                        if isSelected {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.title3)
                                                .foregroundStyle(.white)
                                        }
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 11)
                                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(18)
                    }
                }
            }
            .navigationTitle("选择导入文件夹")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showNewFolderAlert = true
                    } label: {
                        Image(systemName: "folder.badge.plus")
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .task {
            await loadFolders()
        }
        .alert("在当前目录新建文件夹", isPresented: $showNewFolderAlert) {
            TextField("文件夹名称", text: $newFolderName)
            Button("取消", role: .cancel) { newFolderName = "" }
            Button("创建") {
                let name = newFolderName
                newFolderName = ""
                Task {
                    await manager.createFolder(named: name)
                    await loadFolders()
                }
            }
        }
    }

    private func loadFolders() async {
        isLoading = true
        folders = await manager.listAllFolders()
        isLoading = false
    }

    private func displayName(for url: URL) -> String {
        if url.standardizedFileURL == manager.rootURL?.standardizedFileURL {
            return "\(manager.driveStats.driveName)（根目录）"
        }
        return url.lastPathComponent
    }

    private func relativePath(for url: URL) -> String {
        guard let rootPath = manager.rootURL?.standardizedFileURL.path else {
            return url.path
        }
        let targetPath = url.standardizedFileURL.path
        if targetPath == rootPath {
            return "/"
        }
        if targetPath.hasPrefix(rootPath) {
            let suffix = String(targetPath.dropFirst(rootPath.count))
            return suffix.isEmpty ? "/" : suffix
        }
        return targetPath
    }
}
