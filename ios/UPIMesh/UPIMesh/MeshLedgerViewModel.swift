import Foundation
import Observation

/// Observable View Model managing live ledger transaction data for MeshLedgerView.
///
/// Follows the architecture of `MeshWalletsViewModel`:
/// - Fetches authoritative ledger transactions from `GET /api/transactions`.
/// - Encapsulates network lifecycle states: `.idle`, `.loading`, `.liveConnected`, `.connectionFailed`.
/// - Derives dynamic transaction counts, settled amounts, in-transit totals, and blocked counts from actual data.
/// - Derives in-transit items strictly from locally received packets in `ReceivedPacketStore`.
/// - Strictly prevents locally received unsettled packets from being labeled as settled ledger records.
/// - Preserves sample preview data solely as an explicitly labeled fallback when the backend is unreachable.
@MainActor
@Observable
public final class MeshLedgerViewModel {

    public enum DataStatus: Equatable, Sendable {
        case idle
        case loading
        case liveConnected
        case connectionFailed(String)
    }

    public var status: DataStatus = .idle
    public var liveTransactions: [TransactionDTO] = []
    public var inTransitPackets: [ReceivedPacketRecord] = []
    public var lastErrorMessage: String? = nil
    public var lastUpdated: Date? = nil

    private let transactionFetcher: MeshTransactionFetching
    private let packetStore: ReceivedPacketStore

    public init(
        transactionFetcher: MeshTransactionFetching = UPIMeshAPIClient.shared,
        packetStore: ReceivedPacketStore = .shared
    ) {
        self.transactionFetcher = transactionFetcher
        self.packetStore = packetStore
    }

    /// Indicates whether the view model is actively connected to the authoritative backend ledger.
    public var isLive: Bool {
        status == .liveConnected
    }

    /// Loads live ledger transactions from the backend and refreshes local in-transit inbox records.
    @MainActor
    public func loadLiveTransactions() async {
        status = .loading
        lastErrorMessage = nil

        // Always refresh local in-transit packet store records
        self.inTransitPackets = packetStore.getAll()

        do {
            let fetched = try await transactionFetcher.fetchTransactions()
            self.liveTransactions = fetched
            self.status = .liveConnected
            self.lastUpdated = Date()
        } catch {
            let message = error.localizedDescription
            self.lastErrorMessage = message
            self.status = .connectionFailed(message)
        }
    }

    // MARK: - Derived Metric Counts & Totals

    /// Total number of authoritative ledger transactions from backend when live,
    /// or demo fallback count when connection failed.
    public var totalCount: Int {
        switch status {
        case .liveConnected:
            return liveTransactions.count
        case .connectionFailed, .idle, .loading:
            return liveTransactions.isEmpty ? PreviewData.sampleTransactions.count : liveTransactions.count
        }
    }

    /// Sum total amount of settled transactions strictly derived from authoritative backend results.
    public var settledTotalAmount: Double {
        switch status {
        case .liveConnected:
            return liveTransactions
                .filter { $0.status.uppercased() == "SETTLED" }
                .reduce(0.0) { $0 + $1.amount }
        case .connectionFailed, .idle, .loading:
            if liveTransactions.isEmpty {
                return PreviewData.sampleTransactions
                    .filter { $0.category == .settled }
                    .reduce(0.0) { $0 + $1.amount }
            }
            return liveTransactions
                .filter { $0.status.uppercased() == "SETTLED" }
                .reduce(0.0) { $0 + $1.amount }
        }
    }

    /// Count of settled transactions.
    public var settledCount: Int {
        switch status {
        case .liveConnected:
            return liveTransactions.filter { $0.status.uppercased() == "SETTLED" }.count
        case .connectionFailed, .idle, .loading:
            return liveTransactions.isEmpty
                ? PreviewData.sampleTransactions.filter { $0.category == .settled }.count
                : liveTransactions.filter { $0.status.uppercased() == "SETTLED" }.count
        }
    }

    /// Count of locally received, unsettled packets waiting in the inbox or actively settling.
    public var inTransitCount: Int {
        switch status {
        case .liveConnected:
            return inTransitPackets
                .filter { $0.reconciliationStatus == .received || $0.reconciliationStatus == .pendingReconciliation || $0.reconciliationStatus == .settling }
                .count
        case .connectionFailed, .idle, .loading:
            if inTransitPackets.isEmpty && liveTransactions.isEmpty {
                return PreviewData.sampleTransactions.filter { $0.category == .inTransit }.count
            }
            return inTransitPackets
                .filter { $0.reconciliationStatus == .received || $0.reconciliationStatus == .pendingReconciliation || $0.reconciliationStatus == .settling }
                .count
        }
    }

    /// Sum total amount of unsettled offline packets in local inbox.
    public var inTransitTotalAmount: Double {
        switch status {
        case .liveConnected:
            return inTransitPackets
                .filter { $0.reconciliationStatus == .received || $0.reconciliationStatus == .pendingReconciliation || $0.reconciliationStatus == .settling }
                .reduce(0.0) { $0 + NSDecimalNumber(decimal: $1.packet.instruction.amount).doubleValue }
        case .connectionFailed, .idle, .loading:
            if inTransitPackets.isEmpty && liveTransactions.isEmpty {
                return PreviewData.sampleTransactions
                    .filter { $0.category == .inTransit }
                    .reduce(0.0) { $0 + $1.amount }
            }
            return inTransitPackets
                .filter { $0.reconciliationStatus == .received || $0.reconciliationStatus == .pendingReconciliation || $0.reconciliationStatus == .settling }
                .reduce(0.0) { $0 + NSDecimalNumber(decimal: $1.packet.instruction.amount).doubleValue }
        }
    }

    /// Count of blocked/failed transactions (backend rejected or failed local packets).
    public var blockedCount: Int {
        switch status {
        case .liveConnected:
            let backendBlocked = liveTransactions
                .filter { $0.status.uppercased() == "FAILED" || $0.status.uppercased() == "BLOCKED" || $0.status.uppercased() == "REJECTED" }
                .count
            let localFailed = inTransitPackets
                .filter { $0.reconciliationStatus == .failed }
                .count
            return backendBlocked + localFailed
        case .connectionFailed, .idle, .loading:
            return liveTransactions.isEmpty
                ? PreviewData.sampleTransactions.filter { $0.category == .blocked }.count
                : liveTransactions.filter { $0.status.uppercased() == "FAILED" || $0.status.uppercased() == "BLOCKED" }.count
        }
    }

    // MARK: - Carousel Metric Formatted Strings

    public var totalMetricString: String {
        "\(totalCount) Tx"
    }

    public var settledMetricString: String {
        Self.formatCurrency(settledTotalAmount)
    }

    public var inTransitMetricString: String {
        Self.formatCurrency(inTransitTotalAmount)
    }

    public var blockedMetricString: String {
        "\(blockedCount)"
    }

    // MARK: - Display Items Filter

    /// Returns display-ready transaction items according to the selected category filter.
    ///
    /// When connected to live backend:
    /// - Live backend records are mapped faithfully without inventing data.
    /// - In-transit packets from `ReceivedPacketStore` are marked distinctly as `.inTransit` / `In Transit (Unsettled)`.
    /// - Locally received unsettled packets are NEVER labeled as settled.
    public func displayTransactions(for filter: String) -> [PreviewData.TransactionItem] {
        switch status {
        case .liveConnected:
            let liveItems: [PreviewData.TransactionItem] = liveTransactions.map { dto in
                let isSettled = dto.status.uppercased() == "SETTLED"
                let isBlocked = dto.status.uppercased() == "FAILED" || dto.status.uppercased() == "BLOCKED" || dto.status.uppercased() == "REJECTED"
                let cat: PreviewData.TransactionItem.Category = isBlocked ? .blocked : .settled
                let timeStr = Self.formatTimestamp(dto.timestamp)
                let txCode = "TX#" + dto.id.prefix(8).uppercased()
                let title = "\(dto.fromAccount.capitalized) → \(dto.toAccount.capitalized)"
                let memo = isSettled ? "Authoritative Ledger Settlement" : "Ledger Status: \(dto.status)"
                let route = isSettled ? "UPI Gateway" : "Core Ledger"
                let icon = isBlocked ? "exclamationmark.shield.fill" : "checkmark.circle.fill"

                return PreviewData.TransactionItem(
                    id: dto.id,
                    txCode: txCode,
                    title: title,
                    memo: memo,
                    amount: dto.amount,
                    timeFormatted: timeStr,
                    category: cat,
                    statusLabel: isSettled ? "Settled" : dto.status,
                    routeLabel: route,
                    iconName: icon
                )
            }

            let pendingPackets = inTransitPackets.filter {
                $0.reconciliationStatus == .received || $0.reconciliationStatus == .settling
            }
            let transitItems: [PreviewData.TransactionItem] = pendingPackets.map { record in
                let inst = record.packet.instruction
                let isSettling = record.reconciliationStatus == .settling
                let timeStr = Self.formatTimestamp(inst.createdAt.isoString)
                let txCode = "PKT#" + record.packet.paymentId.prefix(8).uppercased()
                let title = "\(inst.fromAccount.capitalized) → \(inst.toAccount.capitalized)"
                let memo = "Offline Mesh Packet (Unsettled Inbox)"
                let status = isSettling ? "Settling..." : "In Transit (Unsettled)"
                let route = "Via \(record.receivedFromPeer)"
                let doubleAmount = NSDecimalNumber(decimal: inst.amount).doubleValue

                return PreviewData.TransactionItem(
                    id: "pkt-" + record.packet.paymentId,
                    txCode: txCode,
                    title: title,
                    memo: memo,
                    amount: doubleAmount,
                    timeFormatted: timeStr,
                    category: .inTransit,
                    statusLabel: status,
                    routeLabel: route,
                    iconName: "arrow.triangle.swap"
                )
            }

            switch filter {
            case "settled":
                return liveItems.filter { $0.category == .settled }
            case "transit":
                return transitItems
            case "blocked":
                return liveItems.filter { $0.category == .blocked }
            default:
                return liveItems + transitItems
            }

        case .connectionFailed, .idle, .loading:
            if !liveTransactions.isEmpty {
                // If we previously loaded transactions, display them
                let liveItems: [PreviewData.TransactionItem] = liveTransactions.map { dto in
                    let isSettled = dto.status.uppercased() == "SETTLED"
                    let cat: PreviewData.TransactionItem.Category = isSettled ? .settled : .blocked
                    return PreviewData.TransactionItem(
                        id: dto.id,
                        txCode: "TX#" + dto.id.prefix(8).uppercased(),
                        title: "\(dto.fromAccount.capitalized) → \(dto.toAccount.capitalized)",
                        memo: isSettled ? "Authoritative Ledger Settlement" : "Ledger Status: \(dto.status)",
                        amount: dto.amount,
                        timeFormatted: Self.formatTimestamp(dto.timestamp),
                        category: cat,
                        statusLabel: isSettled ? "Settled" : dto.status,
                        routeLabel: isSettled ? "UPI Gateway" : "Core Ledger",
                        iconName: isSettled ? "checkmark.circle.fill" : "exclamationmark.shield.fill"
                    )
                }
                switch filter {
                case "settled": return liveItems.filter { $0.category == .settled }
                case "transit": return []
                case "blocked": return liveItems.filter { $0.category == .blocked }
                default: return liveItems
                }
            }

            // Explicit demo fallback when backend is unavailable
            switch filter {
            case "settled":
                return PreviewData.sampleTransactions.filter { $0.category == .settled }
            case "transit":
                return PreviewData.sampleTransactions.filter { $0.category == .inTransit }
            case "blocked":
                return PreviewData.sampleTransactions.filter { $0.category == .blocked }
            default:
                return PreviewData.sampleTransactions
            }
        }
    }

    // MARK: - Formatters

    /// Formats an ISO-8601 UTC timestamp string to localized time (e.g., "1:23 PM").
    nonisolated public static func formatTimestamp(_ timestampString: String) -> String {
        if let instant = try? PaymentInstant.parse(timestampString) {
            let date = Date(timeIntervalSince1970: Double(instant.epochSecond))
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone.current
            formatter.dateFormat = "h:mm a"
            return formatter.string(from: date)
        }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFormatter.date(from: timestampString) {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone.current
            formatter.dateFormat = "h:mm a"
            return formatter.string(from: date)
        }

        if timestampString.contains("T") {
            let timePart = timestampString.split(separator: "T").last ?? ""
            return String(timePart.prefix(5))
        }
        return timestampString
    }

    /// Formats currency to standard Indian Rupee format matching Stitch mockups (e.g., "₹14,250", "₹30", "₹10.50").
    nonisolated public static func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "₹"
        if amount.truncatingRemainder(dividingBy: 1) == 0 {
            formatter.maximumFractionDigits = 0
            formatter.minimumFractionDigits = 0
        } else {
            formatter.maximumFractionDigits = 2
            formatter.minimumFractionDigits = 2
        }
        return formatter.string(from: NSNumber(value: amount)) ?? String(format: "₹%.2f", amount)
    }
}
