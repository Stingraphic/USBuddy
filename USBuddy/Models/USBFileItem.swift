import Foundation

enum JunkCategory: String, CaseIterable, Identifiable, Sendable {
    case appleDouble = "._*"
    case dsStore = ".DS_Store"
    case trashes = ".Trashes"
    case spotlight = ".Spotlight-V100"
    case fseventsd = ".fseventsd"
    case temporaryItems = ".TemporaryItems"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appleDouble: "AppleDouble 资源文件 (._*)"
        case .dsStore: "Finder 视图缓存 (.DS_Store)"
        case .trashes: "外接盘废纸篓 (.Trashes)"
        case .spotlight: "Spotlight 索引 (.Spotlight-V100)"
        case .fseventsd: "文件系统日志 (.fseventsd)"
        case .temporaryItems: "系统临时目录 (.TemporaryItems)"
        }
    }

    var subtitle: String {
        switch self {
        case .appleDouble: "iPhone/Mac 写入 exFAT U 盘时产生最多的 .xxxx 伴生文件"
        case .dsStore: "记录文件夹图标与排列方式的隐藏配置"
        case .trashes: "U 盘删除文件后残留的隐藏回收站"
        case .spotlight: "macOS 搜索索引缓存目录"
        case .fseventsd: "磁盘事件追踪日志目录"
        case .temporaryItems: "系统复制或编辑时生成的临时目录"
        }
    }

    func matches(fileName: String) -> Bool {
        switch self {
        case .appleDouble:
            return fileName.hasPrefix("._")
        case .dsStore:
            return fileName == ".DS_Store"
        case .trashes:
            return fileName == ".Trashes"
        case .spotlight:
            return fileName == ".Spotlight-V100"
        case .fseventsd:
            return fileName == ".fseventsd"
        case .temporaryItems:
            return fileName == ".TemporaryItems"
        }
    }
}

struct USBFileItem: Identifiable, Hashable, Sendable {
    let id: URL
    let url: URL
    let name: String
    let isDirectory: Bool
    let size: Int64
    let modifiedDate: Date?
    let junkCategory: JunkCategory?

    var isHiddenDotFile: Bool {
        name.hasPrefix(".")
    }

    var isJunk: Bool {
        junkCategory != nil
    }

    var formattedSize: String {
        if isDirectory {
            return "文件夹"
        }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    var systemIconName: String {
        if isDirectory {
            return isJunk ? "folder.badge.minus" : "folder.fill"
        }
        if isJunk {
            return "doc.badge.gearshape"
        }
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg", "png", "heic", "gif", "webp":
            return "photo.fill"
        case "mp4", "mov", "mkv", "avi":
            return "film.fill"
        case "mp3", "wav", "m4a", "flac":
            return "music.note"
        case "pdf":
            return "doc.richtext.fill"
        case "zip", "rar", "7z", "tar", "gz":
            return "archivebox.fill"
        case "txt", "md", "json", "swift":
            return "doc.text.fill"
        default:
            return "doc.fill"
        }
    }
}

enum FileSortOption: String, CaseIterable, Identifiable {
    case name = "名称"
    case size = "大小"
    case date = "修改时间"

    var id: String { rawValue }
}

struct DriveStats: Sendable {
    var driveName: String = "未连接 U 盘"
    var totalCapacity: Int64 = 0
    var availableCapacity: Int64 = 0
    var totalFileCount: Int = 0
    var junkCount: Int = 0
    var junkBytes: Int64 = 0

    var usedCapacity: Int64 {
        max(0, totalCapacity - availableCapacity)
    }

    var usedRatio: Double {
        guard totalCapacity > 0 else { return 0 }
        return min(1.0, max(0.0, Double(usedCapacity) / Double(totalCapacity)))
    }

    var formattedJunkSize: String {
        ByteCountFormatter.string(fromByteCount: junkBytes, countStyle: .file)
    }

    var formattedAvailable: String {
        guard totalCapacity > 0 else { return "剩余空间未知" }
        return "剩余 " + ByteCountFormatter.string(fromByteCount: availableCapacity, countStyle: .file)
    }

    var formattedRemainingShort: String {
        guard totalCapacity > 0 else { return "未知" }
        return ByteCountFormatter.string(fromByteCount: availableCapacity, countStyle: .file)
    }

    var formattedUsed: String {
        guard totalCapacity > 0 else { return "未知" }
        return ByteCountFormatter.string(fromByteCount: usedCapacity, countStyle: .file)
    }

    var formattedTotal: String {
        guard totalCapacity > 0 else { return "外接存储" }
        return ByteCountFormatter.string(fromByteCount: totalCapacity, countStyle: .file)
    }
}

struct CleanupSummary: Identifiable, Sendable {
    let id = UUID()
    let deletedCount: Int
    let freedBytes: Int64
    let actionTitle: String

    var formattedFreedSize: String {
        ByteCountFormatter.string(fromByteCount: freedBytes, countStyle: .file)
    }
}

enum DuplicateMatchType: String, Sendable {
    case similarName = "相似文件名"
    case exactHash = "内容相同"
}

struct DuplicateGroup: Identifiable, Sendable {
    let id: String
    let matchType: DuplicateMatchType
    let items: [USBFileItem]

    var duplicateCount: Int {
        max(0, items.count - 1)
    }

    var reclaimableBytes: Int64 {
        items.dropFirst().reduce(0) { $0 + $1.size }
    }

    var formattedFileSize: String {
        items.first?.formattedSize ?? ByteCountFormatter.string(fromByteCount: 0, countStyle: .file)
    }

    var formattedReclaimableSize: String {
        ByteCountFormatter.string(fromByteCount: reclaimableBytes, countStyle: .file)
    }
}

enum ImportConflictChoice: String, CaseIterable, Identifiable, Sendable {
    case keepExisting = "保留原文件"
    case keepNew = "保留新文件"
    case keepBoth = "两个都保留"

    var id: String { rawValue }
}

struct ImportConflictItem: Identifiable, Sendable {
    let id = UUID()
    let fileName: String
    let existingURL: URL
    let existingSize: Int64
    let existingDate: Date?
    let stagedNewURL: URL
    let newSize: Int64
    let newDate: Date?
    var choice: ImportConflictChoice = .keepNew

    var formattedExistingSize: String {
        ByteCountFormatter.string(fromByteCount: existingSize, countStyle: .file)
    }

    var formattedNewSize: String {
        ByteCountFormatter.string(fromByteCount: newSize, countStyle: .file)
    }
}

struct CleanupLogEntry: Identifiable, Sendable {
    let id = UUID()
    let name: String
    let path: String
    let size: Int64
    let succeeded: Bool

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}
