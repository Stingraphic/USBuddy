import SwiftUI

enum AppTab: Hashable {
    case home
    case files
    case imports
    case rules
}

struct ContentView: View {
    @State private var manager = USBDriveManager()
    @State private var selectedTab: AppTab = .home
    @State private var filesNavPath = NavigationPath()

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("清理", systemImage: "sparkles", value: .home) {
                NavigationStack {
                    DashboardView(manager: manager, selectedTab: $selectedTab)
                }
            }

            Tab("文件", systemImage: "folder.fill", value: .files) {
                NavigationStack(path: $filesNavPath) {
                    Group {
                        if manager.isConnected {
                            FileBrowserView(manager: manager, navigationPath: $filesNavPath)
                        } else {
                            disconnectedFilesView
                        }
                    }
                }
            }

            Tab("导入", systemImage: "square.and.arrow.down", value: .imports) {
                NavigationStack {
                    ImportHubView(manager: manager)
                }
            }

            Tab("规则", systemImage: "slider.horizontal.3", value: .rules) {
                JunkRulesSheet(manager: manager, showDoneButton: false)
            }
        }
        .preferredColorScheme(.dark)
        .safeAreaInset(edge: .top) {
            if manager.isImporting {
                importProgressBanner
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: manager.isImporting)
        .sheet(item: $manager.activePickerRequest) { request in
            SystemDocumentPicker(request: request) { urls in
                manager.handlePickerResult(request: request, urls: urls)
            } onCancel: {
                manager.debugBanner = "已取消选择"
            }
            .ignoresSafeArea()
        }
        .sheet(item: $manager.cleanupSummary) { summary in
            CleanupSuccessSheet(summary: summary) {
                manager.cleanupSummary = nil
            }
        }
        .sheet(isPresented: $manager.showImportConflictSheet) {
            ImportConflictSheet(manager: manager)
        }
        .sheet(isPresented: $manager.showCleanupProgressSheet) {
            CleanupProgressSheet(manager: manager)
        }
        .alert("提示", isPresented: Binding(
            get: { manager.statusMessage != nil },
            set: { if !$0 { manager.statusMessage = nil } }
        )) {
            Button("好的", role: .cancel) { manager.statusMessage = nil }
        } message: {
            Text(manager.statusMessage ?? "")
        }
        .alert("操作提醒", isPresented: Binding(
            get: { manager.errorMessage != nil },
            set: { if !$0 { manager.errorMessage = nil } }
        )) {
            Button("知道了", role: .cancel) { manager.errorMessage = nil }
        } message: {
            Text(manager.errorMessage ?? "")
        }
    }

    private var importProgressBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(0.8)

                Text("正在导入到 U 盘（\(manager.importCurrentIndex)/\(manager.importTotalCount)）")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)

                Spacer()

                Text("\(Int((manager.importProgress * 100).rounded()))%")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: manager.importProgress, total: 1.0)
                .tint(.white)

            if !manager.importCurrentFileName.isEmpty {
                Text(manager.importCurrentFileName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }

    private var disconnectedFilesView: some View {
        ZStack {
            MeshGlassBackground()

            VStack(spacing: 18) {
                Image("USBMascot")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 110, height: 110)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                Text("尚未选择 U 盘")
                    .font(.title3.bold())

                Text("选择你的 C 口 U 盘目录后，即可在这里浏览、搜索、预览与批量删除文件")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Button {
                    manager.openDrivePicker()
                } label: {
                    Text("选择 U 盘目录")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.white, in: Capsule())
                }
            }
        }
        .navigationTitle("U 盘文件")
        .navigationBarTitleDisplayMode(.inline)
    }
}
