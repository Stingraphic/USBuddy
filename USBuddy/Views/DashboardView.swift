import PhotosUI
import QuickLook
import SwiftUI
import UniformTypeIdentifiers

struct DashboardView: View {
    @Bindable var manager: USBDriveManager
    @Binding var selectedTab: AppTab

    @State private var showCleanConfirm = false
    @State private var showDuplicateSheet = false
    @State private var previewURL: URL?

    var body: some View {
        ZStack {
            MeshGlassBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    topBar

                    if let banner = manager.debugBanner {
                        HStack(spacing: 10) {
                            Image(systemName: "info.circle.fill")
                                .foregroundStyle(.white)
                            Text(banner)
                                .font(.caption)
                                .foregroundStyle(.white)
                                .lineLimit(3)
                            Spacer()
                            Button {
                                manager.debugBanner = nil
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(12)
                        .glassEffect(.regular, in: .rect(cornerRadius: 16))
                    }

                    heroUSBCard

                    if manager.isConnected {
                        storageOverviewCard

                        cleanupActionCard

                        duplicateActionCard

                        rootFilesSection
                    } else {
                        allFeaturesPreviewGrid
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, manager.isConnected ? 32 : 16)
            }
            .refreshable {
                await manager.refreshAll()
            }
        }
        .navigationBarHidden(true)
        .safeAreaInset(edge: .bottom) {
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.3"
            let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "4"
            VStack(spacing: 3) {
                Text("版本号：v\(version) (\(build))")
                Text("Made with ❤️ by @Sting")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 22)
        }
        .quickLookPreview($previewURL)
        .sheet(isPresented: $showDuplicateSheet) {
            DuplicateFilesSheet(manager: manager)
        }
        .confirmationDialog(
            "确认一键清理隐藏文件？",
            isPresented: $showCleanConfirm,
            titleVisibility: .visible
        ) {
            Button("清理 \(manager.driveStats.junkCount) 个 .xxxx 文件", role: .destructive) {
                Task { await manager.cleanAllJunk() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将永久删除 U 盘内所有匹配的 ._*、.DS_Store 等隐藏残留文件，共可释放 \(manager.driveStats.formattedJunkSize)。")
        }
    }

    // MARK: - 顶部状态栏

    private var topBar: some View {
        HStack {
            HStack(spacing: 10) {
                Circle()
                    .fill(manager.isConnected ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(manager.isConnected ? manager.driveStats.driveName : "未连接 U 盘")
                    .font(.headline)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .glassEffect(.regular, in: .capsule)

            Spacer()

            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    if manager.isConnected {
                        Button {
                            Task { await manager.refreshAll() }
                        } label: {
                            Image(systemName: manager.isScanning ? "arrow.trianglehead.2.clockwise" : "arrow.clockwise")
                                .font(.subheadline.weight(.semibold))
                                .frame(width: 40, height: 40)
                        }
                        .glassEffect(.regular.interactive(), in: .circle)
                    }

                    Button {
                        manager.openDrivePicker()
                    } label: {
                        Image(systemName: "externaldrive.badge.plus")
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 40, height: 40)
                    }
                    .glassEffect(.regular.interactive(), in: .circle)
                }
            }
        }
    }

    // MARK: - 首页 USB 主视觉区（无背景框，连接前后保持一致）

    private var heroUSBCard: some View {
        VStack(spacing: 14) {
            Image("USBMascot")
                .resizable()
                .scaledToFit()
                .frame(width: manager.isConnected ? 108 : 132, height: manager.isConnected ? 108 : 132)
                .clipShape(RoundedRectangle(cornerRadius: manager.isConnected ? 24 : 28, style: .continuous))

            VStack(spacing: 6) {
                Text(manager.isConnected ? "已挂载：\(manager.driveStats.driveName)" : "请插入 Type C U盘")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                Text(
                    manager.isConnected
                    ? "可随时一键清理隐藏文件，或直接管理 U 盘目录"
                    : "插入 U 盘后点击下方按钮，进入 U 盘内子文件夹再点「打开」"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.horizontal, 12)
            }

            HStack(spacing: 12) {
                Button {
                    manager.openDrivePicker()
                } label: {
                    Text(manager.isConnected ? "切换目录" : "连接 Type-C U盘")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.white, in: Capsule())
                }

                if manager.isConnected {
                    Button {
                        manager.disconnectDrive()
                    } label: {
                        Text("退出挂载")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .glassEffect(.regular.interactive(), in: .capsule)
                } else {
                    Button {
                        manager.openDirectFileCleaner()
                    } label: {
                        Text("多选文件清理")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .glassEffect(.regular.interactive(), in: .capsule)
                }
            }

            if !manager.isConnected && manager.hasSavedBookmark {
                Button {
                    manager.restoreSavedDrive()
                } label: {
                    Text("连接上次使用的 U 盘")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: - 未连接时展示所有功能概览

    private var allFeaturesPreviewGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("全部功能")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                featureNavCard(
                    icon: "sparkles",
                    title: "一键清理隐藏文件",
                    subtitle: "清理 ._*、.DS_Store 等隐藏残留"
                ) {
                    manager.openDrivePicker()
                }

                featureNavCard(
                    icon: "folder.fill",
                    title: "浏览与删除文件",
                    subtitle: "查看 U 盘目录、多选删除、Preview"
                ) {
                    selectedTab = .files
                }

                featureNavCard(
                    icon: "square.and.arrow.down",
                    title: "导入到 U 盘",
                    subtitle: "从相册或 iPhone 文件导入"
                ) {
                    selectedTab = .imports
                }

                featureNavCard(
                    icon: "slider.horizontal.3",
                    title: "自定义清理规则",
                    subtitle: "已启用 \(manager.enabledCategories.count) 项规则"
                ) {
                    selectedTab = .rules
                }
            }
        }
    }

    private func featureNavCard(
        icon: String,
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon)
                    .font(.body.weight(.semibold))
                    .frame(width: 34, height: 34)
                    .background(.white.opacity(0.12), in: Circle())

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
            .padding(13)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 已连接：存储空间概览

    private var storageOverviewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("存储空间", systemImage: "internaldrive")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(manager.driveStats.totalFileCount) 个文件")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                        .frame(height: 8)

                    Capsule()
                        .fill(Color.white)
                        .frame(
                            width: max(8, geo.size.width * manager.driveStats.usedRatio),
                            height: 8
                        )
                }
            }
            .frame(height: 8)

            HStack {
                Text(manager.driveStats.formattedAvailable)
                    .font(.caption.weight(.medium))
                Spacer()
                Text("总容量 \(manager.driveStats.formattedTotal)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }

    // MARK: - 已连接：一键清理卡片

    private var cleanupActionCard: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(manager.driveStats.junkCount > 0 ? "发现 \(manager.driveStats.junkCount) 个 .xxxx 残留" : "U 盘非常干净")
                    .font(.headline)

                Text(
                    manager.driveStats.junkCount > 0
                    ? "预计可释放 \(manager.driveStats.formattedJunkSize)"
                    : "未检测到 ._* 或 .DS_Store 隐藏垃圾"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                if manager.driveStats.junkCount > 0 {
                    showCleanConfirm = true
                } else {
                    Task { await manager.scanDrive() }
                }
            } label: {
                HStack(spacing: 6) {
                    if manager.isProcessing || manager.isScanning {
                        ProgressView()
                            .tint(.black)
                            .scaleEffect(0.8)
                    }
                    Text(manager.driveStats.junkCount > 0 ? "一键清理隐藏文件" : "重新扫描")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.black)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(Color.white, in: Capsule())
            }
            .disabled(manager.isProcessing || manager.isScanning)
        }
        .padding(18)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }

    // MARK: - 已连接：重复文件识别卡片

    private var duplicateActionCard: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(
                    !manager.hasScannedDuplicates
                    ? "重复文件识别"
                    : (manager.duplicateTotalCount > 0
                       ? "发现 \(manager.duplicateTotalCount) 个重复副本"
                       : "未发现重复文件")
                )
                .font(.headline)

                Text(
                    !manager.hasScannedDuplicates
                    ? "识别相似文件名（如 xxx 2）与相同内容文件"
                    : (manager.duplicateTotalCount > 0
                       ? "共 \(manager.duplicateGroups.count) 组，可释放 \(manager.formattedDuplicateReclaimableSize)"
                       : "当前挂载目录未发现重复文件")
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                showDuplicateSheet = true
            } label: {
                HStack(spacing: 6) {
                    if manager.isScanningDuplicates {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.8)
                    }
                    Text(manager.duplicateTotalCount > 0 ? "查看清理" : "扫描重复")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .glassEffect(.regular.interactive(), in: .capsule)
            .disabled(manager.isProcessing)
        }
        .padding(18)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }

    // MARK: - 已连接：根目录文件直达

    private var rootFilesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("U 盘文件")
                    .font(.headline)
                Spacer()
                Button("进入文件管理器") {
                    selectedTab = .files
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            }

            if let rootPath = manager.rootURL?.path {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                        .font(.caption2)
                    Text(rootPath)
                        .font(.caption2)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                .foregroundStyle(.secondary)
            }

            if manager.filteredEntries.isEmpty {
                HStack {
                    Spacer()
                    Text("当前目录暂无可见文件")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 24)
                    Spacer()
                }
                .glassEffect(.regular, in: .rect(cornerRadius: 20))
            } else {
                VStack(spacing: 8) {
                    ForEach(manager.filteredEntries.prefix(8)) { item in
                        Button {
                            if item.isDirectory {
                                manager.navigate(to: item.url)
                                selectedTab = .files
                            } else {
                                previewURL = item.url
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: item.systemIconName)
                                    .font(.body)
                                    .foregroundStyle(item.isJunk ? .orange : .primary)
                                    .frame(width: 36, height: 36)
                                    .background(.white.opacity(0.12), in: Circle())

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text(item.isJunk ? "可清理残留 · \(item.formattedSize)" : item.formattedSize)
                                        .font(.caption2)
                                        .foregroundStyle(item.isJunk ? .orange : .secondary)
                                }

                                Spacer()

                                if item.isDirectory {
                                    Image(systemName: "chevron.right")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
