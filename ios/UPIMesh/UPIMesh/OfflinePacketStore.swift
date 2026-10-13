import Foundation

/// Errors that can occur during offline packet persistence operations.
public enum OfflinePacketStoreError: LocalizedError, Equatable {
    case duplicatePacketId(String)
    case persistenceFailed(String)
    case readFailed(String)
    case packetNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .duplicatePacketId(let id):
            return "An offline packet with payment ID '\(id)' is already stored."
        case .persistenceFailed(let msg):
            return "Failed to persist offline packet to disk: \(msg)"
        case .readFailed(let msg):
            return "Failed to read offline packets from disk: \(msg)"
        case .packetNotFound(let id):
            return "Offline packet with payment ID '\(id)' was not found."
        }
    }
}

/// A thread-safe, file-backed persistent store for offline payment packets.
///
/// Storage Characteristics:
/// - Uses standard iOS `Application Support` directory (`UPIMesh/offline_packets.json`).
/// - Survives application termination, backgrounding, and cold launches.
/// - Performs atomic file writes (`.atomic`) to prevent data corruption.
/// - Enforces strict duplicate-ID protection preventing duplicate packet records.
/// - Stores NO private keys or cryptographic secrets. Only signed public packet records.
public final class OfflinePacketStore: @unchecked Sendable {

    /// Shared default singleton instance using standard Application Support directory.
    public static let shared: OfflinePacketStore = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("UPIMesh", isDirectory: true)
        let file = dir.appendingPathComponent("offline_packets.json")
        return OfflinePacketStore(fileURL: file)
    }()

    private let fileURL: URL
    private let lock = NSLock()
    private var inMemoryCache: [String: OfflinePaymentPacket] = [:]
    private var orderedIds: [String] = []

    /// Initializes the store with a specific target file URL.
    ///
    /// Allows dependency injection of isolated temporary file URLs for unit tests.
    public init(fileURL: URL) {
        self.fileURL = fileURL
        loadFromDisk()
    }

    /// The active file URL where packets are stored on disk.
    public var storageURL: URL {
        fileURL
    }

    /// Returns the total count of stored offline packets.
    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return orderedIds.count
    }

    // MARK: - CRUD Operations

    /// Persists a new signed offline payment packet.
    ///
    /// - Parameter packet: The `OfflinePaymentPacket` to store.
    /// - Throws: `OfflinePacketStoreError.duplicatePacketId` if the payment ID already exists,
    ///           or `OfflinePacketStoreError.persistenceFailed` if disk I/O fails.
    public func save(_ packet: OfflinePaymentPacket) throws {
        lock.lock()
        defer { lock.unlock() }

        let pid = packet.paymentId
        if inMemoryCache[pid] != nil {
            throw OfflinePacketStoreError.duplicatePacketId(pid)
        }

        inMemoryCache[pid] = packet
        orderedIds.append(pid)

        do {
            try persistToDiskInternal()
        } catch {
            // Roll back in-memory state on persistence failure
            inMemoryCache.removeValue(forKey: pid)
            orderedIds.removeAll { $0 == pid }
            throw OfflinePacketStoreError.persistenceFailed(error.localizedDescription)
        }
    }

    /// Retrieves an offline packet by its unique payment ID.
    public func get(paymentId: String) -> OfflinePaymentPacket? {
        lock.lock()
        defer { lock.unlock() }
        return inMemoryCache[paymentId]
    }

    /// Checks whether an offline packet with the given payment ID exists in the store.
    public func contains(paymentId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return inMemoryCache[paymentId] != nil
    }

    /// Returns all stored offline payment packets in insertion order.
    public func getAll() -> [OfflinePaymentPacket] {
        lock.lock()
        defer { lock.unlock() }
        return orderedIds.compactMap { inMemoryCache[$0] }
    }

    /// Returns all stored packets matching the specified status.
    public func getPackets(withStatus status: OfflinePacketStatus) -> [OfflinePaymentPacket] {
        lock.lock()
        defer { lock.unlock() }
        return orderedIds.compactMap { inMemoryCache[$0] }.filter { $0.status == status }
    }

    /// Clears all stored packets from memory and deletes the backing file.
    /// Primarily used for test teardown and cleanup.
    public func clear() throws {
        lock.lock()
        defer { lock.unlock() }

        inMemoryCache.removeAll()
        orderedIds.removeAll()

        let fm = FileManager.default
        if fm.fileExists(atPath: fileURL.path) {
            do {
                try fm.removeItem(at: fileURL)
            } catch {
                throw OfflinePacketStoreError.persistenceFailed("Failed to delete store file: \(error.localizedDescription)")
            }
        }
    }

    /// Re-reads the store contents from disk, updating the in-memory cache.
    public func reload() throws {
        lock.lock()
        defer { lock.unlock() }
        loadFromDiskInternal()
    }

    // MARK: - Internal Disk I/O

    private func loadFromDisk() {
        lock.lock()
        defer { lock.unlock() }
        loadFromDiskInternal()
    }

    private func loadFromDiskInternal() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else {
            inMemoryCache = [:]
            orderedIds = []
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            let packets = try decoder.decode([OfflinePaymentPacket].self, from: data)

            var newCache: [String: OfflinePaymentPacket] = [:]
            var newOrdered: [String] = []

            for p in packets {
                if newCache[p.paymentId] == nil {
                    newCache[p.paymentId] = p
                    newOrdered.append(p.paymentId)
                }
            }

            inMemoryCache = newCache
            orderedIds = newOrdered
        } catch {
            // If the file exists but fails to decode, preserve inMemory state and log
            inMemoryCache = [:]
            orderedIds = []
        }
    }

    private func persistToDiskInternal() throws {
        let parentDir = fileURL.deletingLastPathComponent()
        let fm = FileManager.default
        if !fm.fileExists(atPath: parentDir.path) {
            try fm.createDirectory(at: parentDir, withIntermediateDirectories: true, attributes: nil)
        }

        let packets = orderedIds.compactMap { inMemoryCache[$0] }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(packets)
        try data.write(to: fileURL, options: .atomic)
    }
}
