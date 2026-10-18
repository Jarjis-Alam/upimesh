import Foundation

@main
struct OfflinePaymentTestRunner {
    static func main() async {
        let success = OfflinePaymentPacketTests.runAllTests()
        guard success else { exit(1) }

        do {
            try PeerTransportTests.runAllTests()
        } catch {
            print("PeerTransportTests failed: \(error)")
            exit(1)
        }

        do {
            try await ReconciliationServiceTests.runAllTests()
        } catch {
            print("ReconciliationServiceTests failed: \(error)")
            exit(1)
        }

        do {
            try await OfflineAllowanceTests.runAllTests()
        } catch {
            print("OfflineAllowanceTests failed: \(error)")
            exit(1)
        }

        await MeshLedgerViewModelTests.runAllTests()

        do {
            try await TrueOfflineStoreAndForwardTests.runAllTests()
        } catch {
            print("TrueOfflineStoreAndForwardTests failed: \(error)")
            exit(1)
        }

        exit(0)
    }
}
