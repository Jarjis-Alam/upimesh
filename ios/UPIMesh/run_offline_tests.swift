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

        await MeshLedgerViewModelTests.runAllTests()

        exit(0)
    }
}
