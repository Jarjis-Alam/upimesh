import Foundation

/// Errors that can occur in the Mac companion's received packet store.
public enum MacReceivedPacketStoreError: LocalizedError, Equatable {
    case duplicatePacketId(String)
    case persistenceFailed(String)
    case readFailed(String)
    case invalidStatus(String)
    case packetNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .duplicatePacketId(let id):
            return "A received offline packet with payment ID '\(id)' is already stored in the Mac companion inbox."
        case .persistenceFailed(let msg):
            return "Failed to persist packet on Mac disk: \(msg)"
        case .readFailed(let msg):
            return "Failed to read packets from Mac disk: \(msg)"
        case .invalidStatus(let msg):
            return msg
        case .packetNotFound(let id):
            return "Received packet with payment ID '\(id)' was not found in the Mac companion inbox."
        }
    }
}

/// Persistent record for packets received on the Mac companion.
public struct MacReceivedPacketRecord: Sendable, Codable, Equatable, Identifiable {
    public let packet: OfflinePaymentPacket
    public let receivedAt: PaymentInstant
    public let receivedFromPeer: String
    public let isSignatureMathematicallyValid: Bool
    public let isSenderIdentityAuthenticated: Bool // strictly false offline
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
            throw MacReceivedPacketStoreError.invalidStatus("Packet stored in Mac companion must have status 'RECEIVED'")
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

    /// Returns a new `MacReceivedPacketRecord` with updated reconciliation status,
    /// preserving original packet contents, signature, canonical bytes, timestamps, and trust metadata.
    public func withReconciliationStatus(
        _ newStatus: ReceivedReconciliationStatus,
        failureReason: String? = nil,
        updatedAt: PaymentInstant = PaymentInstant.now()
    ) -> MacReceivedPacketRecord {
        try! MacReceivedPacketRecord(
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
            throw MacReceivedPacketStoreError.invalidStatus("Packet stored in Mac companion must have status 'RECEIVED'")
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

/// Isolated persistent store for the Mac companion.
///
/// Storage Characteristics:
/// - Stored at `~/Library/Application Support/UPIMeshCompanion/received_packets.json`.
/// - Completely separate from the iPhone's data directory.
/// - Duplicate-ID protection prevents duplicate imports.
public final class MacReceivedPacketStore: @unchecked Sendable {

    public static let shared: MacReceivedPacketStore = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("UPIMeshCompanion", isDirectory: true)
        let file = dir.appendingPathComponent("received_packets.json")
        return MacReceivedPacketStore(fileURL: file)
    }()

    private let fileURL: URL
    private let lock = NSLock()
    private var inMemoryCache: [String: MacReceivedPacketRecord] = [:]
    private var orderedIds: [String] = []

    public init(fileURL: URL) {
        self.fileURL = fileURL
        loadFromDisk()
    }

    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return orderedIds.count
    }

    public func save(_ record: MacReceivedPacketRecord) throws {
        lock.lock()
        defer { lock.unlock() }

        let pid = record.id
        if inMemoryCache[pid] != nil {
            throw MacReceivedPacketStoreError.duplicatePacketId(pid)
        }

        inMemoryCache[pid] = record
        orderedIds.append(pid)

        do {
            try persistToDiskInternal()
        } catch {
            inMemoryCache.removeValue(forKey: pid)
            orderedIds.removeAll { $0 == pid }
            throw MacReceivedPacketStoreError.persistenceFailed(error.localizedDescription)
        }
    }

    public func get(paymentId: String) -> MacReceivedPacketRecord? {
        lock.lock()
        defer { lock.unlock() }
        return inMemoryCache[paymentId]
    }

    public func contains(paymentId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return inMemoryCache[paymentId] != nil
    }

    public func getAll() -> [MacReceivedPacketRecord] {
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
    /// - Returns: The updated `MacReceivedPacketRecord`.
    /// - Throws: `MacReceivedPacketStoreError.packetNotFound` if the record does not exist,
    ///           or `MacReceivedPacketStoreError.persistenceFailed` if disk I/O fails.
    @discardableResult
    public func updateStatus(
        paymentId: String,
        status: ReceivedReconciliationStatus,
        failureReason: String? = nil
    ) throws -> MacReceivedPacketRecord {
        lock.lock()
        defer { lock.unlock() }

        guard let existing = inMemoryCache[paymentId] else {
            throw MacReceivedPacketStoreError.packetNotFound(paymentId)
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
            throw MacReceivedPacketStoreError.persistenceFailed(error.localizedDescription)
        }
    }

    public func clear() throws {
        lock.lock()
        defer { lock.unlock() }

        inMemoryCache.removeAll()
        orderedIds.removeAll()

        let fm = FileManager.default
        if fm.fileExists(atPath: fileURL.path) {
            try fm.removeItem(at: fileURL)
        }
    }

    private func loadFromDisk() {
        lock.lock()
        defer { lock.unlock() }

        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else {
            inMemoryCache = [:]
            orderedIds = []
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let records = try JSONDecoder().decode([MacReceivedPacketRecord].self, from: data)
            var newCache: [String: MacReceivedPacketRecord] = [:]
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
            try fm.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }

        let records = orderedIds.compactMap { inMemoryCache[$0] }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(records)
        try data.write(to: fileURL, options: .atomic)
    }
}
