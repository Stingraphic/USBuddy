import CryptoKit
import Foundation
import Observation

@Observable
@MainActor
final class USBDriveManager {
    private static let bookmarkKey = "com.sting.usbkeeper.savedDriveBookmark"

    // MARK: - Connection State
    var rootURL: URL?
    var currentDirectoryURL: URL?
    var hasSavedBookmark: Bool {
        UserDefaults.standard.data(forKey: Self.bookmarkKey) != nil
    }

    // MARK: - Data State
    var driveStats = DriveStats()
    var junkItems: [USBFileItem] = []
    var currentEntries: [USBFileItem] = []
    var duplicateGroups: [DuplicateGroup] = []
    var scannedFileCountForDuplicates: Int = 0
    var hasScannedDuplicates: Bool = false
    var enabledCategories: Set<JunkCategory> = Set(JunkCategory.allCases)

    // MARK: - View Controls
    var searchText: String = ""
    var sortOption: FileSortOption = .name
    var showHiddenDotFiles: Bool = true

    // MARK: - UI Feedback State
    var activePickerRequest: PickerRequest?
    var isScanning: Bool = false
    var isScanningDuplicates: Bool = false
    var isProcessing: Bool = false
    var isImporting: Bool = false
    var importProgress: Double = 0
    var importCurrentIndex: Int = 0
    var importTotalCount: Int = 0
    var importCurrentFileName: String = ""
    var pendingImportConflicts: [ImportConflictItem] = []
    var showImportConflictSheet: Bool = false
    var lastImportSuccessCount: Int = 0
    var statusMessage: String?
    var errorMessage: String?
    var debugBanner: String?
    var cleanupSummary: CleanupSummary?

    private var activeSecurityURL: URL?
    private var didStartSecurityAccess: Bool = false

    var isConnected: Bool {
        rootURL != nil
    }

    var duplicateTotalCount: Int {
        duplicateGroups.reduce(0) { $0 + $1.duplicateCount }
    }

    var duplicateReclaimableBytes: Int64 {
        duplicateGroups.reduce(0) { $0 + $1.reclaimableBytes }
    }

    var formattedDuplicateReclaimableSize: String {
        ByteCountFormatter.string(fromByteCount: duplicateReclaimableBytes, countStyle: .file)
    }

    var filteredEntries: [USBFileItem] {
        let base = currentEntries.filter { item in
            if !showHiddenDotFiles && item.isHiddenDotFile {
                return false
            }
            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return true
            }
            return item.name.localizedCaseInsensitiveContains(searchText)
        }

        return base.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory && !rhs.isDirectory
            }
            switch sortOption {
            case .name:
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            case .size:
                return lhs.size > rhs.size
            case .date:
                return (lhs.modifiedDate ?? .distantPast) > (rhs.modifiedDate ?? .distantPast)
            }
        }
    }

    var breadcrumbs: [URL] {
        guard let root = rootURL, let current = currentDirectoryURL else { return [] }
        let rootComponents = root.standardizedFileURL.pathComponents
        let currentComponents = current.standardizedFileURL.pathComponents
        guard currentComponents.count >= rootComponents.count else { return [root] }

        var trail: [URL] = [root]
        var running = root
        for idx in rootComponents.count..<currentComponents.count {
            running = running.appendingPathComponent(currentComponents[idx], isDirectory: true)
            trail.append(running)
        }
        return trail
    }

    // MARK: - Connection & Bookmarks

    func openDrivePicker() {
        debugBanner = "已打开目录选择器，请选择 U 盘文件夹后点「打开」"
        activePickerRequest = .folder
    }

    func openDirectFileCleaner() {
        debugBanner = "已打开多选文件清理，请选择要删除的文件"
        activePickerRequest = .multiFiles
    }

    func handlePickerResult(request: PickerRequest, urls: [URL]) {
        switch request {
        case .folder:
            if let url = urls.first {
                debugBanner = "选择器已返回路径：\(url.lastPathComponent)"
                connectDrive(url: url)
            }
        case .multiFiles:
            debugBanner = "已选中 \(urls.count) 个文件，准备清理..."
            Task {
                await deletePickedRawFiles(urls)
            }
        }
    }

    func connectDrive(url: URL) {
        releaseSecurityScope()

        let started = url.startAccessingSecurityScopedResource()
        didStartSecurityAccess = started

        var readError: Error?
        var canRead = false

        do {
            _ = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: nil,
                options: []
            )
            canRead = true
        } catch {
            readError = error
            var coordError: NSError?
            NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordError) { coordinatedURL in
                do {
                    _ = try FileManager.default.contentsOfDirectory(
                        at: coordinatedURL,
                        includingPropertiesForKeys: nil,
                        options: []
                    )
                    canRead = true
                } catch {
                    readError = error
                }
            }
            if let coordError {
                readError = coordError
            }
        }

        guard canRead else {
            if started {
                url.stopAccessingSecurityScopedResource()
            }
            didStartSecurityAccess = false
            let detail = readError?.localizedDescription ?? "未知读取错误"
            debugBanner = "打开失败：\(detail)"
            errorMessage = "无法读取「\(url.lastPathComponent)」：\(detail)"
            return
        }

        activeSecurityURL = url
        rootURL = url
        currentDirectoryURL = url
        duplicateGroups = []
        scannedFileCountForDuplicates = 0
        hasScannedDuplicates = false
        driveStats.driveName = url.lastPathComponent.isEmpty ? "USB 外接盘" : url.lastPathComponent
        debugBanner = "已成功连接：\(url.lastPathComponent)"

        if let bookmarkData = try? url.bookmarkData(
            options: .minimalBookmark,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            UserDefaults.standard.set(bookmarkData, forKey: Self.bookmarkKey)
        }

        Task {
            await refreshAll()
        }
    }

    func restoreSavedDrive() {
        guard let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) else {
            errorMessage = "没有找到上次连接的 U 盘记录。"
            return
        }

        var isStale = false
        do {
            let resolvedURL = try URL(
                resolvingBookmarkData: data,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            connectDrive(url: resolvedURL)
        } catch {
            errorMessage = "U 盘可能尚未插入或卷标已变更，请重新选择目录。"
        }
    }

    func disconnectDrive() {
        releaseSecurityScope()
        rootURL = nil
        currentDirectoryURL = nil
        junkItems = []
        currentEntries = []
        duplicateGroups = []
        scannedFileCountForDuplicates = 0
        hasScannedDuplicates = false
        driveStats = DriveStats()
        debugBanner = "已退出挂载"
    }

    private func releaseSecurityScope() {
        if didStartSecurityAccess {
            activeSecurityURL?.stopAccessingSecurityScopedResource()
        }
        didStartSecurityAccess = false
        activeSecurityURL = nil
    }

    // MARK: - Scanning & Listing

    func refreshAll() async {
        await scanDrive()
        if let dir = currentDirectoryURL {
            await loadDirectory(dir)
        }
    }

    func scanDrive() async {
        guard let root = rootURL else { return }
        isScanning = true
        defer { isScanning = false }

        let categories = enabledCategories
        let result = await Task.detached(priority: .userInitiated) {
            Self.performDriveScan(root: root, enabledCategories: categories)
        }.value

        driveStats = result.stats
        junkItems = result.junkItems
    }

    func scanDuplicates() async {
        guard let root = rootURL else { return }
        isScanningDuplicates = true
        defer { isScanningDuplicates = false }

        let categories = enabledCategories
        let scanResult = await Task.detached(priority: .userInitiated) {
            Self.performDuplicateScan(root: root, enabledCategories: categories)
        }.value

        duplicateGroups = scanResult.groups
        scannedFileCountForDuplicates = scanResult.scannedCount
        hasScannedDuplicates = true
    }

    func cleanDuplicateFiles(_ items: [USBFileItem]) async {
        guard !items.isEmpty else { return }
        isProcessing = true
        defer { isProcessing = false }

        let result = await Task.detached(priority: .userInitiated) {
            Self.removeItemsOnDisk(items)
        }.value

        await refreshAll()
        await scanDuplicates()

        if result.deletedCount > 0 {
            cleanupSummary = CleanupSummary(
                deletedCount: result.deletedCount,
                freedBytes: result.freedBytes,
                actionTitle: "重复文件清理完成！"
            )
        } else {
            errorMessage = "部分重复文件无法删除，请检查 U 盘是否为只读格式。"
        }
    }

    func navigate(to directory: URL) {
        currentDirectoryURL = directory
        Task {
            await loadDirectory(directory)
        }
    }

    func loadDirectory(_ directory: URL) async {
        let categories = enabledCategories
        let entries = await Task.detached(priority: .userInitiated) {
            Self.readDirectory(directory, enabledCategories: categories)
        }.value
        currentEntries = entries
    }

    func listAllFolders() async -> [URL] {
        guard let root = rootURL else { return [] }
        let categories = enabledCategories
        return await Task.detached(priority: .userInitiated) {
            [root] + Self.collectAllDirectories(in: root, enabledCategories: categories)
        }.value
    }

    // MARK: - Cleanup & Delete

    func cleanAllJunk() async {
        guard !junkItems.isEmpty else {
            statusMessage = "当前没有检测到需要清理的 .xxxx 垃圾文件。"
            return
        }

        isProcessing = true
        defer { isProcessing = false }

        let targets = junkItems
        let result = await Task.detached(priority: .userInitiated) {
            Self.removeItemsOnDisk(targets)
        }.value

        await refreshAll()

        if result.deletedCount > 0 {
            cleanupSummary = CleanupSummary(
                deletedCount: result.deletedCount,
                freedBytes: result.freedBytes,
                actionTitle: "隐形垃圾清理完成！"
            )
        } else {
            errorMessage = "部分系统保护文件无法删除，请检查 U 盘是否为只读格式（如 NTFS）。"
        }
    }

    func deleteItems(_ items: [USBFileItem]) async {
        guard !items.isEmpty else { return }
        isProcessing = true
        defer { isProcessing = false }

        let result = await Task.detached(priority: .userInitiated) {
            Self.removeItemsOnDisk(items)
        }.value

        await refreshAll()

        if result.deletedCount > 0 {
            cleanupSummary = CleanupSummary(
                deletedCount: result.deletedCount,
                freedBytes: result.freedBytes,
                actionTitle: "文件删除成功！"
            )
        } else {
            errorMessage = "删除失败，请确认 U 盘可写。"
        }
    }

    func deletePickedRawFiles(_ urls: [URL]) async {
        guard !urls.isEmpty else { return }
        isProcessing = true
        defer { isProcessing = false }

        let result = await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            var deleted = 0
            var freed: Int64 = 0

            for url in urls {
                let accessed = url.startAccessingSecurityScopedResource()
                defer {
                    if accessed { url.stopAccessingSecurityScopedResource() }
                }
                let size = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                do {
                    try fm.removeItem(at: url)
                    deleted += 1
                    freed += size
                } catch {
                    continue
                }
            }
            return (deleted, freed)
        }.value

        if result.0 > 0 {
            cleanupSummary = CleanupSummary(
                deletedCount: result.0,
                freedBytes: result.1,
                actionTitle: "已清理选中文件！"
            )
        } else {
            errorMessage = "无法删除选中的文件，请确认 U 盘可写。"
        }
    }

    // MARK: - Import & Basic File Operations

    func beginImportProgress(total: Int) {
        isImporting = true
        importTotalCount = max(1, total)
        importCurrentIndex = 0
        importProgress = 0
        importCurrentFileName = ""
    }

    func updateImportProgress(current: Int, fileName: String) {
        importCurrentIndex = current
        importCurrentFileName = fileName
        importProgress = min(1.0, max(0.0, Double(current) / Double(max(1, importTotalCount))))
    }

    func endImportProgress() {
        isImporting = false
        importProgress = 0
        importCurrentIndex = 0
        importTotalCount = 0
        importCurrentFileName = ""
    }

    func importFiles(urls: [URL], to destinationDirectory: URL? = nil) async {
        guard let targetDir = destinationDirectory ?? currentDirectoryURL, !urls.isEmpty else { return }
        clearImportConflicts()
        isProcessing = true
        beginImportProgress(total: urls.count)
        defer {
            isProcessing = false
            endImportProgress()
        }

        var importedCount = 0
        var conflicts: [ImportConflictItem] = []

        for (index, sourceURL) in urls.enumerated() {
            let fileName = sourceURL.lastPathComponent
            updateImportProgress(current: index + 1, fileName: fileName)

            let outcome = await Task.detached(priority: .userInitiated) { () -> (imported: Bool, conflict: ImportConflictItem?) in
                let fm = FileManager.default
                let accessed = sourceURL.startAccessingSecurityScopedResource()
                defer {
                    if accessed { sourceURL.stopAccessingSecurityScopedResource() }
                }

                let directDestURL = targetDir.appendingPathComponent(fileName)

                if fm.fileExists(atPath: directDestURL.path) {
                    let stageURL = fm.temporaryDirectory
                        .appendingPathComponent("USBuddyImport_\(UUID().uuidString)_\(fileName)")
                    guard Self.writeFileCleanly(from: sourceURL, to: stageURL, fileManager: fm) else {
                        return (false, nil)
                    }

                    let existingValues = try? directDestURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                    let newValues = try? stageURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])

                    let item = ImportConflictItem(
                        fileName: fileName,
                        existingURL: directDestURL,
                        existingSize: Int64(existingValues?.fileSize ?? 0),
                        existingDate: existingValues?.contentModificationDate,
                        stagedNewURL: stageURL,
                        newSize: Int64(newValues?.fileSize ?? 0),
                        newDate: newValues?.contentModificationDate
                    )
                    return (false, item)
                } else {
                    let ok = Self.writeFileCleanly(from: sourceURL, to: directDestURL, fileManager: fm)
                    return (ok, nil)
                }
            }.value

            if outcome.imported {
                importedCount += 1
            } else if let conflict = outcome.conflict {
                conflicts.append(conflict)
            }
        }

        await refreshAll()
        lastImportSuccessCount = importedCount

        if !conflicts.isEmpty {
            pendingImportConflicts = conflicts
            showImportConflictSheet = true
        } else if importedCount > 0 {
            statusMessage = "已成功导入 \(importedCount) 个文件到 U 盘"
        } else {
            errorMessage = "导入文件失败，请检查 U 盘空间或写入权限。"
        }
    }

    func importPhotoData(_ data: Data, filename: String, to destinationDirectory: URL? = nil) async -> Bool {
        guard let targetDir = destinationDirectory ?? currentDirectoryURL else { return false }
        let fm = FileManager.default
        let directDestURL = targetDir.appendingPathComponent(filename)

        if fm.fileExists(atPath: directDestURL.path) {
            let stageURL = fm.temporaryDirectory
                .appendingPathComponent("USBuddyImport_\(UUID().uuidString)_\(filename)")
            do {
                try data.write(to: stageURL, options: .atomic)
                let existingValues = try? directDestURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                pendingImportConflicts.append(
                    ImportConflictItem(
                        fileName: filename,
                        existingURL: directDestURL,
                        existingSize: Int64(existingValues?.fileSize ?? 0),
                        existingDate: existingValues?.contentModificationDate,
                        stagedNewURL: stageURL,
                        newSize: Int64(data.count),
                        newDate: Date()
                    )
                )
                showImportConflictSheet = true
                return true
            } catch {
                return false
            }
        }

        do {
            try data.write(to: directDestURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    func resolveImportConflicts() async {
        let items = pendingImportConflicts
        guard !items.isEmpty else {
            showImportConflictSheet = false
            return
        }

        isProcessing = true
        defer { isProcessing = false }

        let summary = await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            var replacedCount = 0
            var keptBothCount = 0
            var keptExistingCount = 0

            for item in items {
                defer { try? fm.removeItem(at: item.stagedNewURL) }

                switch item.choice {
                case .keepExisting:
                    keptExistingCount += 1
                case .keepNew:
                    try? fm.removeItem(at: item.existingURL)
                    if Self.writeFileCleanly(from: item.stagedNewURL, to: item.existingURL, fileManager: fm) {
                        replacedCount += 1
                    }
                case .keepBoth:
                    let parentDir = item.existingURL.deletingLastPathComponent()
                    let uniqueURL = Self.uniqueDestinationURL(
                        for: item.fileName,
                        in: parentDir,
                        fileManager: fm
                    )
                    if Self.writeFileCleanly(from: item.stagedNewURL, to: uniqueURL, fileManager: fm) {
                        keptBothCount += 1
                    }
                }
            }
            return (replacedCount, keptBothCount, keptExistingCount)
        }.value

        pendingImportConflicts = []
        showImportConflictSheet = false
        await refreshAll()

        let totalImported = lastImportSuccessCount + summary.0 + summary.1
        lastImportSuccessCount = 0
        statusMessage = "导入完成：成功写入 \(totalImported) 个（覆盖 \(summary.0)，保留副本 \(summary.1)，跳过 \(summary.2)）"
    }

    func clearImportConflicts() {
        let fm = FileManager.default
        for item in pendingImportConflicts {
            try? fm.removeItem(at: item.stagedNewURL)
        }
        pendingImportConflicts = []
        showImportConflictSheet = false
    }

    nonisolated private static func writeFileCleanly(
        from sourceURL: URL,
        to destURL: URL,
        fileManager: FileManager
    ) -> Bool {
        do {
            let data = try Data(contentsOf: sourceURL)
            try data.write(to: destURL, options: .atomic)
            let dotURL = destURL.deletingLastPathComponent().appendingPathComponent("._" + destURL.lastPathComponent)
            try? fileManager.removeItem(at: dotURL)
            return true
        } catch {
            do {
                try fileManager.copyItem(at: sourceURL, to: destURL)
                let dotURL = destURL.deletingLastPathComponent().appendingPathComponent("._" + destURL.lastPathComponent)
                try? fileManager.removeItem(at: dotURL)
                return true
            } catch {
                return false
            }
        }
    }

    func createFolder(named name: String, in directory: URL? = nil) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let targetDir = directory ?? currentDirectoryURL else { return }

        let folderURL = Self.uniqueDestinationURL(for: trimmed, in: targetDir, fileManager: FileManager.default)
        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: false)
            await refreshAll()
            statusMessage = "已创建文件夹「\(folderURL.lastPathComponent)」"
        } catch {
            errorMessage = "创建文件夹失败：\(error.localizedDescription)"
        }
    }

    func renameItem(_ item: USBFileItem, to newName: String) async {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != item.name else { return }

        let parent = item.url.deletingLastPathComponent()
        let destURL = parent.appendingPathComponent(trimmed, isDirectory: item.isDirectory)
        do {
            try FileManager.default.moveItem(at: item.url, to: destURL)
            await refreshAll()
            statusMessage = "已重命名为「\(trimmed)」"
        } catch {
            errorMessage = "重命名失败：\(error.localizedDescription)"
        }
    }

    // MARK: - Non-isolated File Helpers

    nonisolated private static func matchJunkCategory(
        fileName: String,
        enabledCategories: Set<JunkCategory>
    ) -> JunkCategory? {
        for category in enabledCategories where category.matches(fileName: fileName) {
            return category
        }
        return nil
    }

    nonisolated private static func buildFileItem(
        from url: URL,
        enabledCategories: Set<JunkCategory>
    ) -> USBFileItem? {
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .fileSizeKey,
            .contentModificationDateKey,
            .nameKey
        ]
        guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
        let name = values.name ?? url.lastPathComponent
        let isDir = values.isDirectory ?? false
        let size = Int64(values.fileSize ?? 0)
        let modDate = values.contentModificationDate
        let junk = matchJunkCategory(fileName: name, enabledCategories: enabledCategories)

        return USBFileItem(
            id: url,
            url: url,
            name: name,
            isDirectory: isDir,
            size: size,
            modifiedDate: modDate,
            junkCategory: junk
        )
    }

    nonisolated private static func readDirectory(
        _ directory: URL,
        enabledCategories: Set<JunkCategory>
    ) -> [USBFileItem] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .nameKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys,
            options: []
        ) else {
            return []
        }

        return urls.compactMap { buildFileItem(from: $0, enabledCategories: enabledCategories) }
    }

    nonisolated private static func performDriveScan(
        root: URL,
        enabledCategories: Set<JunkCategory>
    ) -> (stats: DriveStats, junkItems: [USBFileItem]) {
        var stats = DriveStats()
        stats.driveName = root.lastPathComponent.isEmpty ? "USB 外接盘" : root.lastPathComponent

        if let volValues = try? root.resourceValues(forKeys: [
            .volumeNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ]) {
            let systemVolumeNames: Set<String> = ["User", "Data", "Preboot", "VM", "Update"]
            if let volName = volValues.volumeName,
               !volName.isEmpty,
               !systemVolumeNames.contains(volName) {
                stats.driveName = volName
            }
            stats.totalCapacity = Int64(volValues.volumeTotalCapacity ?? 0)
            let importantAvail = volValues.volumeAvailableCapacityForImportantUsage ?? 0
            let standardAvail = Int64(volValues.volumeAvailableCapacity ?? 0)
            stats.availableCapacity = importantAvail > 0 ? importantAvail : standardAvail
        }

        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .nameKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { _, _ in true }
        ) else {
            return (stats, [])
        }

        var foundJunk: [USBFileItem] = []
        var totalFiles = 0

        for case let fileURL as URL in enumerator {
            guard let item = buildFileItem(from: fileURL, enabledCategories: enabledCategories) else {
                continue
            }
            if !item.isDirectory {
                totalFiles += 1
            }
            if item.isJunk {
                foundJunk.append(item)
                stats.junkCount += 1
                stats.junkBytes += item.size
                if item.isDirectory {
                    enumerator.skipDescendants()
                }
            }
        }

        stats.totalFileCount = totalFiles
        return (stats, foundJunk)
    }

    nonisolated private static func removeItemsOnDisk(_ items: [USBFileItem]) -> (deletedCount: Int, freedBytes: Int64) {
        let fm = FileManager.default
        var deleted = 0
        var freed: Int64 = 0

        for item in items {
            do {
                try fm.removeItem(at: item.url)
                deleted += 1
                freed += item.size
            } catch {
                continue
            }
        }
        return (deleted, freed)
    }

    nonisolated private static func uniqueDestinationURL(
        for filename: String,
        in directory: URL,
        fileManager: FileManager
    ) -> URL {
        var candidate = directory.appendingPathComponent(filename)
        if !fileManager.fileExists(atPath: candidate.path) {
            return candidate
        }

        let base = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        var index = 1
        while fileManager.fileExists(atPath: candidate.path) {
            let nextName = ext.isEmpty ? "\(base) (\(index))" : "\(base) (\(index)).\(ext)"
            candidate = directory.appendingPathComponent(nextName)
            index += 1
        }
        return candidate
    }

    nonisolated private static func collectAllDirectories(
        in directory: URL,
        enabledCategories: Set<JunkCategory>
    ) -> [URL] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .nameKey]
        var childURLs: [URL] = []

        if let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys,
            options: []
        ) {
            childURLs = urls
        } else {
            var coordError: NSError?
            NSFileCoordinator().coordinate(readingItemAt: directory, options: [], error: &coordError) { coordinatedURL in
                if let urls = try? FileManager.default.contentsOfDirectory(
                    at: coordinatedURL,
                    includingPropertiesForKeys: keys,
                    options: []
                ) {
                    childURLs = urls
                }
            }
        }

        var collected: [URL] = []
        for url in childURLs {
            guard let item = buildFileItem(from: url, enabledCategories: enabledCategories),
                  item.isDirectory,
                  !item.isJunk else {
                continue
            }
            collected.append(url)
            collected.append(contentsOf: collectAllDirectories(in: url, enabledCategories: enabledCategories))
        }
        return collected.sorted {
            $0.path.localizedStandardCompare($1.path) == .orderedAscending
        }
    }

    // MARK: - Duplicate Detection (Size -> Partial Sample -> Full SHA256)

    nonisolated private static func performDuplicateScan(
        root: URL,
        enabledCategories: Set<JunkCategory>
    ) -> (groups: [DuplicateGroup], scannedCount: Int) {
        let allFiles = collectAllRegularFiles(in: root, enabledCategories: enabledCategories)
        var sizeBuckets: [Int64: [USBFileItem]] = [:]

        for item in allFiles where item.size > 0 {
            sizeBuckets[item.size, default: []].append(item)
        }

        var groups: [DuplicateGroup] = []
        var exactGroupMemberSets: [Set<URL>] = []

        for (fileSize, sameSizeItems) in sizeBuckets where sameSizeItems.count > 1 {
            var sampleBuckets: [String: [USBFileItem]] = [:]

            if fileSize > 131_072 {
                for item in sameSizeItems {
                    if let sample = quickSampleDigest(for: item.url, fileSize: fileSize) {
                        sampleBuckets[sample, default: []].append(item)
                    }
                }
            } else {
                sampleBuckets["small", default: []] = sameSizeItems
            }

            for (_, candidates) in sampleBuckets where candidates.count > 1 {
                var hashBuckets: [String: [USBFileItem]] = [:]
                for item in candidates {
                    if let fullHash = fullSHA256Digest(for: item.url) {
                        hashBuckets[fullHash, default: []].append(item)
                    }
                }

                for (digest, dupItems) in hashBuckets where dupItems.count > 1 {
                    let sorted = dupItems.sorted { lhs, rhs in
                        if lhs.name.count != rhs.name.count {
                            return lhs.name.count < rhs.name.count
                        }
                        return lhs.url.path.localizedStandardCompare(rhs.url.path) == .orderedAscending
                    }
                    exactGroupMemberSets.append(Set(sorted.map(\.id)))
                    groups.append(DuplicateGroup(id: "hash_\(digest)", matchType: .exactHash, items: sorted))
                }
            }
        }

        // 2. 相似文件名（如 "歌曲.mp3" 与 "歌曲 2.mp3" / "歌曲2.mp3" / "歌曲 (1).mp3" / "歌曲 副本.mp3"）
        let exactStemKeys: Set<String> = Set(allFiles.map { item in
            let stem = (item.name as NSString).deletingPathExtension.lowercased()
            let ext = item.url.pathExtension.lowercased()
            return "\(stem)|\(ext)"
        })

        var similarBuckets: [String: [USBFileItem]] = [:]
        for item in allFiles {
            let ext = item.url.pathExtension.lowercased()
            let rawStem = (item.name as NSString).deletingPathExtension
            let normalized = normalizedDuplicateStem(rawStem, ext: ext, exactStemKeys: exactStemKeys)
            let key = "\(normalized.lowercased())|\(ext)"
            similarBuckets[key, default: []].append(item)
        }

        for (key, matchedItems) in similarBuckets where matchedItems.count > 1 {
            let memberSet = Set(matchedItems.map(\.id))
            let alreadyCoveredByExact = exactGroupMemberSets.contains { exactSet in
                memberSet.isSubset(of: exactSet)
            }
            if alreadyCoveredByExact { continue }

            let sorted = matchedItems.sorted { lhs, rhs in
                let lhsStem = (lhs.name as NSString).deletingPathExtension
                let rhsStem = (rhs.name as NSString).deletingPathExtension
                if lhsStem.count != rhsStem.count {
                    return lhsStem.count < rhsStem.count
                }
                return lhs.url.path.localizedStandardCompare(rhs.url.path) == .orderedAscending
            }
            groups.append(DuplicateGroup(id: "name_\(key)", matchType: .similarName, items: sorted))
        }

        let sortedGroups = groups.sorted { lhs, rhs in
            if lhs.matchType != rhs.matchType {
                return lhs.matchType == .similarName
            }
            if lhs.reclaimableBytes != rhs.reclaimableBytes {
                return lhs.reclaimableBytes > rhs.reclaimableBytes
            }
            return (lhs.items.first?.name ?? "") < (rhs.items.first?.name ?? "")
        }
        return (sortedGroups, allFiles.count)
    }

    nonisolated private static func collectAllRegularFiles(
        in directory: URL,
        enabledCategories: Set<JunkCategory>
    ) -> [USBFileItem] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .nameKey]
        var childURLs: [URL] = []

        if let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys,
            options: []
        ) {
            childURLs = urls
        } else {
            var coordError: NSError?
            NSFileCoordinator().coordinate(readingItemAt: directory, options: [], error: &coordError) { coordinatedURL in
                if let urls = try? FileManager.default.contentsOfDirectory(
                    at: coordinatedURL,
                    includingPropertiesForKeys: keys,
                    options: []
                ) {
                    childURLs = urls
                }
            }
        }

        var collected: [USBFileItem] = []
        for url in childURLs {
            guard let item = buildFileItem(from: url, enabledCategories: enabledCategories) else {
                continue
            }
            if item.isJunk {
                continue
            }
            if item.isDirectory {
                collected.append(contentsOf: collectAllRegularFiles(in: url, enabledCategories: enabledCategories))
            } else {
                collected.append(item)
            }
        }
        return collected
    }

    nonisolated private static func normalizedDuplicateStem(
        _ stem: String,
        ext: String,
        exactStemKeys: Set<String>
    ) -> String {
        var current = stem
            .precomposedStringWithCanonicalMapping
            .replacingOccurrences(of: "\u{3000}", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let suffixPatterns = [
            #"(?i)[\s_-]*(?:副本|拷贝)(?:\s*\d{1,2})?$"#,
            #"(?i)[\s_-]*copy(?:\s*\d{1,2})?$"#,
            #"\s*[\(\[（【]\d{1,2}[\)\]）】]$"#,
            #"[\s_.-]+\d{1,2}$"#
        ]

        var changed = true
        while changed {
            changed = false
            for pattern in suffixPatterns {
                if let range = current.range(of: pattern, options: .regularExpression) {
                    let candidate = String(current[..<range.lowerBound])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !candidate.isEmpty {
                        current = candidate
                        changed = true
                    }
                }
            }
        }

        if let range = current.range(of: #"\d{1,2}$"#, options: .regularExpression) {
            let withoutTrailingDigits = String(current[..<range.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedExactKeys = Set(exactStemKeys.map { $0.precomposedStringWithCanonicalMapping })
            if !withoutTrailingDigits.isEmpty,
               normalizedExactKeys.contains("\(withoutTrailingDigits.lowercased())|\(ext)") {
                current = withoutTrailingDigits
            }
        }

        return current
    }

    nonisolated private static func quickSampleDigest(for url: URL, fileSize: Int64) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        let chunkSize = 65_536
        var hasher = SHA256()

        guard let head = try? handle.read(upToCount: chunkSize) else { return nil }
        hasher.update(data: head)

        if fileSize > Int64(chunkSize * 2) {
            do {
                try handle.seek(toOffset: UInt64(fileSize - Int64(chunkSize)))
                if let tail = try? handle.read(upToCount: chunkSize) {
                    hasher.update(data: tail)
                }
            } catch {
                return nil
            }
        }

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    nonisolated private static func fullSHA256Digest(for url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        let bufferSize = 262_144
        var hasher = SHA256()

        while true {
            guard let data = try? handle.read(upToCount: bufferSize) else { return nil }
            if data.isEmpty { break }
            hasher.update(data: data)
        }

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
