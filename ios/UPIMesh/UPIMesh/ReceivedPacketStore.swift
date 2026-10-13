import Foundation

/// Errors that can occur during received packet inbox operations.
public enum ReceivedPacketStoreError: LocalizedError, Equatable {
    case duplicatePacketId(String)
    case persistenceFailed(String)
    case readFailed(String)
    case packetNotFound(String)
    case invalidStatus(String)

    public var errorDescription: String? {
        switch self {
        case .duplicatePacketId(let id):
            return "A received offline packet with payment ID '\(id)' is already stored in the inbox."
        case .persistenceFailed(let msg):
            return "Failed to persist received packet to disk: \(msg)"
        case .readFailed(let msg):
            return "Failed to read received packets from disk: \(msg)"
        case .packetNotFound(let id):
            return "Received packet with payment ID '\(id)' was not found."
        case .invalidStatus(let msg):
            return msg
        }
    }
}

/// A persistent record representing an offline payment packet received from a nearby peer.
///
/// Under the prototype trust boundary:
/// - `isSignatureMathematicallyValid`: Indicates whether the RSASSA-PSS signature verified against the sender's public key.
/// - `isSenderIdentityAuthenticated`: Explicitly `false` offline. Trusting a public key merely because the peer transmitted it
///   does NOT authenticate that the key belongs to the bank account holder. Identity authorization is enforced by the backend bridge.
/// - `packet.status`: Must be `.received` (`RECEIVED — NOT SETTLED`). It is never settled upon transfer.
public struct ReceivedPacketRecord: Sendable, Codable, Equatable, Identifiable {
    public let packet: OfflinePaymentPacket
    public let receivedAt: PaymentInstant
    public let receivedFromPeer: String
    public let isSignatureMathematicallyValid: Bool
    public let isSenderIdentityAuthenticated: Bool
    public let trustStatusNote: String
    public let reconciliationStatus: ReceivedReconciliationStatus
    public let failureReason: String?
    public let updatedAt: PaymentInstant?

    public var id: String {
        packet.paymentId
    }

    public init(
        packet: OfflinePaymentPacket,
        receivedAt: PaymentInstant = PaymentInstant.now(),
        receivedFromPeer: String,
        isSignatureMathematicallyValid: Bool,
        isSenderIdentityAuthenticated: Bool = false,
        trustStatusNote: String,
        reconciliationStatus: ReceivedReconciliationStatus = .received,
        failureReason: String? = nil,
        updatedAt: PaymentInstant? = nil
    ) throws {
        guard packet.status == .received else {
            throw ReceivedPacketStoreError.invalidStatus("Packet stored in ReceivedPacketStore must have status 'RECEIVED'")
        }
        self.packet = packet
        self.receivedAt = receivedAt
        self.receivedFromPeer = receivedFromPeer
        self.isSignatureMathematicallyValid = isSignatureMathematicallyValid
        self.isSenderIdentityAuthenticated = isSenderIdentityAuthenticated
        self.trustStatusNote = trustStatusNote
        self.reconciliationStatus = reconciliationStatus
        self.failureReason = failureReason
        self.updatedAt = updatedAt
    }

    /// Returns a new `ReceivedPacketRecord` with updated reconciliation status,
    /// preserving original packet contents, signature, canonical bytes, timestamps, and trust metadata.
    public func withReconciliationStatus(
        _ newStatus: ReceivedReconciliationStatus,
        failureReason: String? = nil,
        updatedAt: PaymentInstant = PaymentInstant.now()
    ) -> ReceivedPacketRecord {
        try! ReceivedPacketRecord(
            packet: self.packet,
            receivedAt: self.receivedAt,
            receivedFromPeer: self.receivedFromPeer,
            isSignatureMathematicallyValid: self.isSignatureMathematicallyValid,
            isSenderIdentityAuthenticated: self.isSenderIdentityAuthenticated,
            trustStatusNote: self.trustStatusNote,
            reconciliationStatus: newStatus,
            failureReason: failureReason,
            updatedAt: updatedAt
        )
    }

    private enum CodingKeys: String, CodingKey {
        case packet
        case receivedAt
        case receivedFromPeer
        case isSignatureMathematicallyValid
        case isSenderIdentityAuthenticated
        case trustStatusNote
        case reconciliationStatus
        case failureReason
        case updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.packet = try container.decode(OfflinePaymentPacket.self, forKey: .packet)
        self.receivedAt = try container.decode(PaymentInstant.self, forKey: .receivedAt)
        self.receivedFromPeer = try container.decode(String.self, forKey: .receivedFromPeer)
        self.isSignatureMathematicallyValid = try container.decode(Bool.self, forKey: .isSignatureMathematicallyValid)
        self.isSenderIdentityAuthenticated = try container.decodeIfPresent(Bool.self, forKey: .isSenderIdentityAuthenticated) ?? false
        self.trustStatusNote = try container.decode(String.self, forKey: .trustStatusNote)
        self.reconciliationStatus = try container.decodeIfPresent(ReceivedReconciliationStatus.self, forKey: .reconciliationStatus) ?? .received
        self.failureReason = try container.decodeIfPresent(String.self, forKey: .failureReason)
        self.updatedAt = try container.decodeIfPresent(PaymentInstant.self, forKey: .updatedAt)

        guard packet.status == .received else {
            throw ReceivedPacketStoreError.invalidStatus("Packet stored in ReceivedPacketStore must have status 'RECEIVED'")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(packet, forKey: .packet)
        try container.encode(receivedAt, forKey: .receivedAt)
        try container.encode(receivedFromPeer, forKey: .receivedFromPeer)
        try container.encode(isSignatureMathematicallyValid, forKey: .isSignatureMathematicallyValid)
        try container.encode(isSenderIdentityAuthenticated, forKey: .isSenderIdentityAuthenticated)
        try container.encode(trustStatusNote, forKey: .trustStatusNote)
        try container.encode(reconciliationStatus, forKey: .reconciliationStatus)
        try container.encodeIfPresent(failureReason, forKey: .failureReason)
        try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
    }
}

/// A dedicated, file-backed persistent inbox for offline payment packets received from nearby peers.
///
/// Storage Characteristics:
/// - Physically isolated in `Application Support/UPIMesh/received_packets.json` (completely separate from outgoing queued packets).
/// - Atomic file writes prevent partial file corruption.
/// - Duplicate-ID protection prevents duplicate imports.
/// - Stores NO private keys or Keychain data.
public final class ReceivedPacketStore: @unchecked Sendable {

    /// Shared default singleton instance using standard Application Support directory.
    public static let shared: ReceivedPacketStore = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("UPIMesh", isDirectory: true)
        let file = dir.appendingPathComponent("received_packets.json")
        return ReceivedPacketStore(fileURL: file)
    }()

    private let fileURL: URL
    private let lock = NSLock()
    private var inMemoryCache: [String: ReceivedPacketRecord] = [:]
    private var orderedIds: [String] = []

    public init(fileURL: URL) {
        self.fileURL = fileURL
        loadFromDisk()
    }

    public var storageURL: URL {
        fileURL
    }

    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return orderedIds.count
    }

    // MARK: - CRUD Operations

    /// Persists a new received offline payment record.
    ///
    /// - Parameter record: The `ReceivedPacketRecord` to store.
    /// - Throws: `ReceivedPacketStoreError.duplicatePacketId` if the payment ID already exists,
    ///           or `ReceivedPacketStoreError.persistenceFailed` if disk I/O fails.
    public func save(_ record: ReceivedPacketRecord) throws {
        lock.lock()
        defer { lock.unlock() }

        let pid = record.id
        if inMemoryCache[pid] != nil {
            throw ReceivedPacketStoreError.duplicatePacketId(pid)
        }

        inMemoryCache[pid] = record
        orderedIds.append(pid)

        do {
            try persistToDiskInternal()
        } catch {
            inMemoryCache.removeValue(forKey: pid)
            orderedIds.removeAll { $0 == pid }
            throw ReceivedPacketStoreError.persistenceFailed(error.localizedDescription)
        }
    }

    /// Retrieves a received packet record by its unique payment ID.
    public func get(paymentId: String) -> ReceivedPacketRecord? {
        lock.lock()
        defer { lock.unlock() }
        return inMemoryCache[paymentId]
    }

    /// Checks whether a received packet with the given payment ID exists in the store.
    public func contains(paymentId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return inMemoryCache[paymentId] != nil
    }

    /// Returns all stored received packet records in insertion order.
    public func getAll() -> [ReceivedPacketRecord] {
        lock.lock()
        defer { lock.unlock() }
        return orderedIds.compactMap { inMemoryCache[$0] }
    }

    /// Updates the reconciliation status of a received packet by its unique payment ID.
    ///
    /// Preserves packet contents, original signature, canonical instruction bytes,
    /// sender device ID, timestamps, and trust metadata without mutation or re-signing.
    /// Atomically persists the updated record to disk.
    ///
    /// - Parameters:
    ///   - paymentId: The unique payment ID of the received packet.
    ///   - status: The new `ReceivedReconciliationStatus` (`.received`, `.settling`, `.settled`, `.failed`).
    ///   - failureReason: Optional error message or explanation if the status is `.failed`.
    /// - Returns: The updated `ReceivedPacketRecord`.
    /// - Throws: `ReceivedPacketStoreError.packetNotFound` if the record does not exist,
    ///           or `ReceivedPacketStoreError.persistenceFailed` if disk I/O fails.
    @discardableResult
    public func updateStatus(
        paymentId: String,
        status: ReceivedReconciliationStatus,
        failureReason: String? = nil
    ) throws -> ReceivedPacketRecord {
        lock.lock()
        defer { lock.unlock() }

        guard let existing = inMemoryCache[paymentId] else {
            throw ReceivedPacketStoreError.packetNotFound(paymentId)
        }

        let updated = existing.withReconciliationStatus(
            status,
            failureReason: failureReason,
            updatedAt: PaymentInstant.now()
        )

        inMemoryCache[paymentId] = updated

        do {
            try persistToDiskInternal()
            return updated
        } catch {
            inMemoryCache[paymentId] = existing
            throw ReceivedPacketStoreError.persistenceFailed(error.localizedDescription)
        }
    }

    /// Clears all received packets from memory and deletes the backing file.
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
                throw ReceivedPacketStoreError.persistenceFailed("Failed to delete store file: \(error.localizedDescription)")
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
            let records = try decoder.decode([ReceivedPacketRecord].self, from: data)

            var newCache: [String: ReceivedPacketRecord] = [:]
            var newOrdered: [String] = []

            for r in records {
                if newCache[r.id] == nil {
                    newCache[r.id] = r
                    newOrdered.append(r.id)
                }
            }

            inMemoryCache = newCache
            orderedIds = newOrdered
        } catch {
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

        let records = orderedIds.compactMap { inMemoryCache[$0] }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(records)
        try data.write(to: fileURL, options: .atomic)
    }
}
