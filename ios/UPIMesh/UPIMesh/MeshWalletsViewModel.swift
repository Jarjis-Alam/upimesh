import Foundation
import Observation

/// Observable View Model managing live account data for MeshWalletsView.
///
/// Encapsulates the network lifecycle: idle, loading, liveConnected, and connectionFailed.
/// Keeps live backend state strictly separated from offline preview data.
@MainActor
@Observable
public final class MeshWalletsViewModel {

    public enum DataStatus: Equatable, Sendable {
        case idle
        case loading
        case liveConnected
        case connectionFailed(String)
    }

    public var status: DataStatus = .idle
    public var liveAccounts: [AccountDTO] = []
    public var lastErrorMessage: String? = nil
    public var lastUpdated: Date? = nil

    private let apiClient: UPIMeshAPIClient

    public init(apiClient: UPIMeshAPIClient = .shared) {
        self.apiClient = apiClient
    }

    /// Fetches live account balances from `GET /api/accounts`.
    @MainActor
    public func loadLiveAccounts() async {
        status = .loading
        lastErrorMessage = nil

        do {
            let fetched = try await apiClient.fetchAccounts()
            self.liveAccounts = fetched
            self.status = .liveConnected
            self.lastUpdated = Date()
        } catch {
            let message = error.localizedDescription
            self.lastErrorMessage = message
            self.status = .connectionFailed(message)
        }
    }

    /// Returns the live balance for a given account ID if loaded.
    public func liveBalance(for accountId: String) -> Double? {
        guard status == .liveConnected else { return nil }
        return liveAccounts.first { $0.id.caseInsensitiveCompare(accountId) == .orderedSame }?.balance
    }

    /// Returns the account version for concurrency verification.
    public func liveVersion(for accountId: String) -> Int? {
        guard status == .liveConnected else { return nil }
        return liveAccounts.first { $0.id.caseInsensitiveCompare(accountId) == .orderedSame }?.version
    }

    /// Total aggregate balance calculated strictly from live backend accounts when connected.
    public var totalLiveBalance: Double? {
        guard status == .liveConnected, !liveAccounts.isEmpty else { return nil }
        return liveAccounts.reduce(0.0) { $0 + $1.balance }
    }
}
