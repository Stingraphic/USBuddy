import SwiftUI

struct FolderPickerSheet: View {
    @Bindable var manager: USBDriveManager
    @Environment(\.dismiss) private var dismiss

    @State private var browsingURL: URL?
    @State private var subfolders: [URL] = []
    @State private var isLoading = true
    @State private var showNewFolderAlert = false
    @State private var newFolderName = ""

    private var breadcrumbTrail: [URL] {
        guard let root = manager.rootURL, let current = browsingURL ?? manager.rootURL else { return [] }
        let rootParts = root.standardizedFileURL.pathComponents
        let currentParts = current.standardizedFileURL.pathComponents
        guard currentParts.count >= rootParts.count else { return [root] }

        var trail: [URL] = [root]
        var running = root
        for idx in rootParts.count..<currentParts.count {
            running = running.appendingPathComponent(currentParts[idx], isDirectory: true)
            trail.append(running)
        }
        return trail
    }

    private var currentFolderTitle: String {
        guard let url = browsingURL ?? manager.rootURL else { return "根目录" }
        if url.standardizedFileURL == manager.rootURL?.standardizedFileURL {
            return "\(manager.driveStats.driveName)（根目录）"
        }
        return url.lastPathComponent
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                MeshGlassBackground()

                VStack(spacing: 12) {
                    breadcrumbBar

                    if isLoading {
                        Spacer()
                        ProgressView("正在读取子文件夹...")
                            .tint(.white)
                        Spacer()
                    } else if subfolders.isEmpty {
                        Spacer()
                        VStack(spacing: 10) {
                            Image(systemName: "folder")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                            Text("当前目录下没有子文件夹")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("可直接点击下方按钮选择「\(currentFolderTitle)」")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                    } else {
                        ScrollView {
                            VStack(spacing: 8) {
                                ForEach(subfolders, id: \.self) { folderURL in
                                    Button {
                                        Task { await openFolder(folderURL) }
                                    } label: {
                                        HStack(spacing: 12) {
                                            Image(systemName: "folder.fill")
                                                .font(.body)
                                                .foregroundStyle(.primary)
                                                .frame(width: 36, height: 36)
                                                .background(.white.opacity(0.12), in: Circle())

                                            Text(folderURL.lastPathComponent)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(.primary)
                                                .lineLimit(1)

                                            Spacer()

                                            Image(systemName: "chevron.right")
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(.tertiary)
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 11)
                                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 18)
                            .padding(.bottom, 92)
                        }
                    }
                }
                .padding(.top, 8)

                if let activeURL = browsingURL ?? manager.rootURL {
                    Button {
                        manager.navigate(to: activeURL)
                        dismiss()
                    } label: {
                        Text("选择当前文件夹「\(currentFolderTitle)」")
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
            let initial = manager.currentDirectoryURL ?? manager.rootURL
            if let initial {
                await openFolder(initial)
            } else {
                isLoading = false
            }
        }
        .alert("在当前目录新建文件夹", isPresented: $showNewFolderAlert) {
            TextField("文件夹名称", text: $newFolderName)
            Button("取消", role: .cancel) { newFolderName = "" }
            Button("创建") {
                let name = newFolderName
                newFolderName = ""
                let target = browsingURL ?? manager.rootURL
                Task {
                    await manager.createFolder(named: name, in: target)
                    if let target {
                        await openFolder(target)
                    }
                }
            }
        }
    }

    private var breadcrumbBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(breadcrumbTrail.enumerated()), id: \.element) { index, url in
                    Button {
                        Task { await openFolder(url) }
                    } label: {
                        Text(index == 0 ? "根目录" : url.lastPathComponent)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(url == browsingURL ? .primary : .secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                    }
                    .glassEffect(.regular.interactive(), in: .capsule)

                    if index < breadcrumbTrail.count - 1 {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 18)
        }
    }

    private func openFolder(_ url: URL) async {
        browsingURL = url
        isLoading = true
        subfolders = await manager.listImmediateSubfolders(in: url)
        isLoading = false
    }
}
