import Foundation

/// Simulated Preview Data Models
///
/// CAUTION / ARCHITECTURE NOTE:
/// The models and collections in this file represent standalone local UI preview data
/// derived from the Stitch UI visual mockups (`ios_ui/`).
///
/// These values are explicitly decoupled from live Spring Boot backend data and do not
/// represent certified cryptographic state, live settlement, or persistent ledger records.
public enum PreviewData {

    // MARK: - Mesh Peer Model
    public struct Peer: Identifiable {
        public let id: String
        public let name: String
        public let role: String
        public let roleTag: String
        public let hops: Int
        public let signalDbm: Int
        public let signalQuality: String
        public let batteryPct: Int
        public let isActive: Bool
        public let isBridge: Bool

        public init(
            id: String,
            name: String,
            role: String,
            roleTag: String,
            hops: Int,
            signalDbm: Int,
            signalQuality: String,
            batteryPct: Int,
            isActive: Bool,
            isBridge: Bool = false
        ) {
            self.id = id
            self.name = name
            self.role = role
            self.roleTag = roleTag
            self.hops = hops
            self.signalDbm = signalDbm
            self.signalQuality = signalQuality
            self.batteryPct = batteryPct
            self.isActive = isActive
            self.isBridge = isBridge
        }
    }

    public static let samplePeers: [Peer] = [
        Peer(
            id: "carol",
            name: "Carol Sharma",
            role: "Relay Node · 1 Hop",
            roleTag: "Relay",
            hops: 1,
            signalDbm: -42,
            signalQuality: "Excellent",
            batteryPct: 96,
            isActive: true
        ),
        Peer(
            id: "bob",
            name: "Bob's Artisan Cafe",
            role: "Merchant · 2 Hops via Carol",
            roleTag: "Payee",
            hops: 2,
            signalDbm: -68,
            signalQuality: "Moderate",
            batteryPct: 52,
            isActive: true
        ),
        Peer(
            id: "gateway",
            name: "NPCI Gateway Bridge",
            role: "Station Kiosk #409",
            roleTag: "Bridge",
            hops: 3,
            signalDbm: 0,
            signalQuality: "Online",
            batteryPct: 100,
            isActive: true,
            isBridge: true
        )
    ]

    // MARK: - Account / Wallet Node Model
    public struct WalletNode: Identifiable {
        public let id: String
        public let title: String
        public let subtitle: String
        public let roleTag: String
        public let balance: Double
        public let inTransit: Double?
        public let receivedOffline: Double?
        public let hops: Int?

        public init(
            id: String,
            title: String,
            subtitle: String,
            roleTag: String,
            balance: Double,
            inTransit: Double? = nil,
            receivedOffline: Double? = nil,
            hops: Int? = nil
        ) {
            self.id = id
            self.title = title
            self.subtitle = subtitle
            self.roleTag = roleTag
            self.balance = balance
            self.inTransit = inTransit
            self.receivedOffline = receivedOffline
            self.hops = hops
        }
    }

    public static let sampleWallets: [WalletNode] = [
        WalletNode(
            id: "alice",
            title: "Alice",
            subtitle: "Personal",
            roleTag: "ACTIVE NODE",
            balance: 4350.00,
            inTransit: 200.00
        ),
        WalletNode(
            id: "bob",
            title: "Bob",
            subtitle: "Merchant Store",
            roleTag: "VERIFIED POS",
            balance: 2650.00,
            receivedOffline: 1650.00
        ),
        WalletNode(
            id: "carol",
            title: "Carol",
            subtitle: "Relay Hub",
            roleTag: "HOP RELAY",
            balance: 1000.00,
            hops: 4
        )
    ]

    // MARK: - Transaction Item Model
    public struct TransactionItem: Identifiable {
        public enum Category: String {
            case settled = "settled"
            case inTransit = "transit"
            case blocked = "blocked"
        }

        public let id: String
        public let txCode: String
        public let title: String
        public let memo: String
        public let amount: Double
        public let timeFormatted: String
        public let category: Category
        public let statusLabel: String
        public let routeLabel: String
        public let iconName: String

        public init(
            id: String,
            txCode: String,
            title: String,
            memo: String,
            amount: Double,
            timeFormatted: String,
            category: Category,
            statusLabel: String,
            routeLabel: String,
            iconName: String
        ) {
            self.id = id
            self.txCode = txCode
            self.title = title
            self.memo = memo
            self.amount = amount
            self.timeFormatted = timeFormatted
            self.category = category
            self.statusLabel = statusLabel
            self.routeLabel = routeLabel
            self.iconName = iconName
        }
    }

    public static let sampleTransactions: [TransactionItem] = [
        TransactionItem(
            id: "tx-1",
            txCode: "TX#89B-2041",
            title: "Alice → Bob",
            memo: "Groceries Settlement",
            amount: 450.00,
            timeFormatted: "10:42 AM",
            category: .settled,
            statusLabel: "Settled",
            routeLabel: "Offline P2P",
            iconName: "bag.fill"
        ),
        TransactionItem(
            id: "tx-2",
            txCode: "TX#89B-2040",
            title: "Rahul → Elena",
            memo: "Books",
            amount: 200.00,
            timeFormatted: "10:38 AM",
            category: .inTransit,
            statusLabel: "In Transit",
            routeLabel: "1 Hop away",
            iconName: "book.fill"
        ),
        TransactionItem(
            id: "tx-3",
            txCode: "TX#89B-2039",
            title: "Dev → Maya",
            memo: "Coffee",
            amount: 280.00,
            timeFormatted: "09:15 AM",
            category: .settled,
            statusLabel: "Settled",
            routeLabel: "Direct NFC",
            iconName: "cup.and.saucer.fill"
        ),
        TransactionItem(
            id: "tx-4",
            txCode: "TX#89B-2038",
            title: "Bob → Dev",
            memo: "Failed Attempt (Duplicate Replay)",
            amount: 150.00,
            timeFormatted: "08:02 AM",
            category: .blocked,
            statusLabel: "Dropped",
            routeLabel: "Duplicate Nonce",
            iconName: "exclamationmark.shield.fill"
        )
    ]
}
