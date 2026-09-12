import Foundation
import Darwin

/// Deliberately path-free errors: never leak machine paths in tool results.
enum WorkspaceReadError: Error, Equatable {
    case invalidRoot
    case registryFull
    case unknownWorkspace
    case revokedWorkspace
    case unboundSession
    case approvalRequired
    case unsupportedAction
    case invalidPath
    case protectedPath
    case inaccessible
    case unsafeFileType
    case multipleHardLinks
    case crossDevice
    case changedDuringAccess
    case tooLarge
    case notUTF8
}

/// Bounded read results contain relative names only. Rejected or omitted
/// entries are disclosed, not silently presented as a complete directory.
enum WorkspaceReadResult: Equatable, Sendable {
    case text(relativePath: String, content: String)
    case directory(relativePath: String, entries: [String], hasOmissions: Bool)
}

/// Conservative fixed deny rules for the first read-only executor. This is
/// not secret detection or a .gitignore parser. Hidden paths are denied even
/// when they contain benign source code, pending explicit product policy.
enum WorkspaceReadPathPolicy {
    static func permits(_ path: String) -> Bool {
        if path == "." { return true }
        return path.split(separator: "/").allSatisfy { component in
            let name = String(component).precomposedStringWithCanonicalMapping.lowercased()
            return !name.hasPrefix(".")
                && !["node_modules", "build", "deriveddata", "vendor", "dist", "credentials", "secrets"].contains(name)
                && !["pem", "key", "p12", "pfx", "mobileprovision"].contains((name as NSString).pathExtension)
        }
    }
}

/// Immutable RAII descriptor ownership. Cross-actor operations use only
/// fstat/openat; never seek/read the shared root descriptor itself. Child
/// file descriptors remain worker-local. Release closes exactly once.
final class WorkspaceFileHandle: @unchecked Sendable {
    let descriptor: Int32
    init(_ descriptor: Int32) { self.descriptor = descriptor }
    deinit { Darwin.close(descriptor) }
}

enum WorkspaceReadAccess {
    static let maxReadBytes = 200_000
    static let maxDirectoryEntries = 1_000
    static let maxListingBytes = 64_000
    private static let directoryFlags = O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK

    struct Root: Sendable {
        let handle: WorkspaceFileHandle
        let path: String
        let identity: stat
    }

    struct Step {
        let parent: WorkspaceFileHandle
        let name: String
        let child: WorkspaceFileHandle
        let identity: stat
    }

    /// Trusted human setup supplies an absolute, already selected root.
    /// Reject symlinks in *every* component rather than silently resolving a
    /// grant somewhere else. Callers may explain canonical aliases in UI.
    static func openRoot(_ url: URL) throws -> Root {
        guard url.isFileURL, url.host == nil || url.host == "" || url.host == "localhost",
              url.path.hasPrefix("/"), url.path != "/",
              WorkspaceRelativePath.isValid(String(url.path.dropFirst())) else { throw WorkspaceReadError.invalidRoot }
        let handle = try openAbsoluteDirectory(url.path)
        return Root(handle: handle, path: url.path, identity: try metadata(handle.descriptor))
    }

    private static func openAbsoluteDirectory(_ path: String) throws -> WorkspaceFileHandle {
        let initial = Darwin.open("/", directoryFlags)
        guard initial >= 0 else { throw WorkspaceReadError.inaccessible }
        var handle = WorkspaceFileHandle(initial)
        for component in path.split(separator: "/") {
            let fd = Darwin.openat(handle.descriptor, String(component), directoryFlags)
            guard fd >= 0 else { throw WorkspaceReadError.invalidRoot }
            handle = WorkspaceFileHandle(fd)
        }
        return handle
    }

    static func validateRoot(_ root: Root) throws {
        let current = try openAbsoluteDirectory(root.path)
        let info = try metadata(current.descriptor)
        guard sameIdentity(info, root.identity), sameIdentity(try metadata(root.handle.descriptor), root.identity) else {
            throw WorkspaceReadError.changedDuringAccess
        }
    }

    static func read(_ path: String, root: Root, beforeIO: (() throws -> Void)? = nil) throws -> WorkspaceReadResult {
        let steps = try traverse(path, root: root, directory: false)
        guard let file = steps.last else { throw WorkspaceReadError.invalidPath }
        let before = try metadata(file.child.descriptor)
        try checkRegular(before, device: root.identity.st_dev)
        guard before.st_size >= 0, before.st_size <= maxReadBytes else { throw WorkspaceReadError.tooLarge }
        try beforeIO?() // Injected only in tests; production never passes a hook.
        try validate(steps, root: root)
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 8192)
        while data.count <= maxReadBytes {
            try Task.checkCancellation()
            let requested = min(buffer.count, maxReadBytes + 1 - data.count)
            let count = Darwin.read(file.child.descriptor, &buffer, requested)
            if count == 0 { break }
            if count < 0 {
                if errno == EINTR { continue }
                throw WorkspaceReadError.inaccessible
            }
            data.append(contentsOf: buffer.prefix(count))
        }
        guard data.count <= maxReadBytes else { throw WorkspaceReadError.tooLarge }
        let after = try metadata(file.child.descriptor)
        try checkRegular(after, device: root.identity.st_dev)
        guard unchanged(before, after), data.count == Int(after.st_size) else { throw WorkspaceReadError.changedDuringAccess }
        try validate(steps, root: root)
        try Task.checkCancellation()
        guard let text = String(data: data, encoding: .utf8), !text.contains("\0") else { throw WorkspaceReadError.notUTF8 }
        return .text(relativePath: path, content: text)
    }

    static func list(_ path: String, root: Root, beforeIO: (() throws -> Void)? = nil) throws -> WorkspaceReadResult {
        let steps = try traverse(path, root: root, directory: true)
        let directory = steps.last?.child ?? root.handle
        let before = try metadata(directory.descriptor)
        try beforeIO?()
        try validate(steps, root: root)
        // Open a distinct file description so repeated listings do not share
        // the root descriptor's directory offset. fdopendir owns this FD.
        let fd = Darwin.openat(directory.descriptor, ".", directoryFlags)
        guard fd >= 0 else { throw WorkspaceReadError.inaccessible }
        guard let stream = fdopendir(fd) else { Darwin.close(fd); throw WorkspaceReadError.inaccessible }
        defer { closedir(stream) }
        var names: [String] = []
        var visited = 0
        var bytes = 0
        var omitted = false
        while true {
            try Task.checkCancellation()
            errno = 0
            guard let entry = readdir(stream) else {
                guard errno == 0 else { throw WorkspaceReadError.inaccessible }
                break
            }
            let name: String? = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen) + 1) { String(validatingCString: $0) }
            }
            if name == "." || name == ".." { continue }
            visited += 1
            guard visited <= maxDirectoryEntries else { omitted = true; break }
            guard let name, WorkspaceRelativePath.isValid(name), WorkspaceReadPathPolicy.permits(name) else { omitted = true; continue }
            var info = stat()
            guard fstatat(directory.descriptor, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else { throw WorkspaceReadError.changedDuringAccess }
            let type = info.st_mode & S_IFMT
            guard info.st_dev == root.identity.st_dev,
                  type == S_IFDIR || (type == S_IFREG && info.st_nlink == 1) else { omitted = true; continue }
            let displayed = name + (type == S_IFDIR ? "/" : "")
            bytes += displayed.utf8.count + 1
            guard bytes <= maxListingBytes else { omitted = true; break }
            names.append(displayed)
        }
        guard unchanged(before, try metadata(directory.descriptor)) else { throw WorkspaceReadError.changedDuringAccess }
        try validate(steps, root: root)
        return .directory(relativePath: path, entries: names.sorted(), hasOmissions: omitted)
    }

    private static func traverse(_ path: String, root: Root, directory: Bool) throws -> [Step] {
        guard WorkspaceRelativePath.isValid(path, allowsRoot: directory) else { throw WorkspaceReadError.invalidPath }
        guard WorkspaceReadPathPolicy.permits(path) else { throw WorkspaceReadError.protectedPath }
        try validateRoot(root)
        if path == "." { return [] }
        let components = path.split(separator: "/").map(String.init)
        guard components.count <= 64 else { throw WorkspaceReadError.invalidPath }
        var parent = root.handle
        var steps: [Step] = []
        for (index, name) in components.enumerated() {
            try Task.checkCancellation()
            let wantsDirectory = directory || index < components.count - 1
            var before = stat()
            guard fstatat(parent.descriptor, name, &before, AT_SYMLINK_NOFOLLOW) == 0 else { throw WorkspaceReadError.inaccessible }
            if wantsDirectory {
                guard before.st_mode & S_IFMT == S_IFDIR else { throw WorkspaceReadError.unsafeFileType }
                guard before.st_dev == root.identity.st_dev else { throw WorkspaceReadError.crossDevice }
            } else {
                try checkRegular(before, device: root.identity.st_dev)
            }
            let flags = wantsDirectory ? directoryFlags : O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK
            let fd = Darwin.openat(parent.descriptor, name, flags)
            guard fd >= 0 else { throw WorkspaceReadError.inaccessible }
            let child = WorkspaceFileHandle(fd)
            let after = try metadata(fd)
            guard sameIdentity(before, after) else { throw WorkspaceReadError.changedDuringAccess }
            if wantsDirectory {
                guard after.st_mode & S_IFMT == S_IFDIR else { throw WorkspaceReadError.unsafeFileType }
            } else { try checkRegular(after, device: root.identity.st_dev) }
            steps.append(Step(parent: parent, name: name, child: child, identity: after))
            parent = child
        }
        try validate(steps, root: root)
        return steps
    }

    private static func validate(_ steps: [Step], root: Root) throws {
        try validateRoot(root)
        let rootPath = try pathForHandle(root.handle)
        for step in steps {
            var current = stat()
            guard fstatat(step.parent.descriptor, step.name, &current, AT_SYMLINK_NOFOLLOW) == 0,
                  sameIdentity(current, step.identity), current.st_dev == root.identity.st_dev else {
                throw WorkspaceReadError.changedDuringAccess
            }
            // Check the filesystem's spelling too (case/normalization aliases
            // may resolve despite differing from the requested components).
            let actual = try pathForHandle(step.child)
            let prefix = rootPath + "/"
            guard actual.hasPrefix(prefix) else { throw WorkspaceReadError.changedDuringAccess }
            guard WorkspaceReadPathPolicy.permits(String(actual.dropFirst(prefix.count))) else {
                throw WorkspaceReadError.protectedPath
            }
        }
    }

    private static func pathForHandle(_ handle: WorkspaceFileHandle) throws -> String {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard fcntl(handle.descriptor, F_GETPATH, &buffer) == 0,
              let end = buffer.firstIndex(of: 0),
              let path = String(bytes: buffer[..<end].map { UInt8(bitPattern: $0) }, encoding: .utf8) else {
            throw WorkspaceReadError.inaccessible
        }
        return path.precomposedStringWithCanonicalMapping
    }

    private static func checkRegular(_ info: stat, device: dev_t) throws {
        guard info.st_mode & S_IFMT == S_IFREG else { throw WorkspaceReadError.unsafeFileType }
        guard info.st_nlink == 1 else { throw WorkspaceReadError.multipleHardLinks }
        guard info.st_dev == device else { throw WorkspaceReadError.crossDevice }
    }

    private static func metadata(_ fd: Int32) throws -> stat {
        var info = stat()
        guard fstat(fd, &info) == 0 else { throw WorkspaceReadError.inaccessible }
        return info
    }

    private static func sameIdentity(_ lhs: stat, _ rhs: stat) -> Bool {
        lhs.st_dev == rhs.st_dev && lhs.st_ino == rhs.st_ino && lhs.st_mode & S_IFMT == rhs.st_mode & S_IFMT
    }

    private static func unchanged(_ lhs: stat, _ rhs: stat) -> Bool {
        sameIdentity(lhs, rhs) && lhs.st_size == rhs.st_size && lhs.st_nlink == rhs.st_nlink
            && lhs.st_mtimespec.tv_sec == rhs.st_mtimespec.tv_sec && lhs.st_mtimespec.tv_nsec == rhs.st_mtimespec.tv_nsec
            && lhs.st_ctimespec.tv_sec == rhs.st_ctimespec.tv_sec && lhs.st_ctimespec.tv_nsec == rhs.st_ctimespec.tv_nsec
    }
}