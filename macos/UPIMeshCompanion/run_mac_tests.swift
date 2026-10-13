import Foundation

@main
struct MacCompanionTestRunner {
    static func main() async {
        do {
            try await MacCompanionTests.runAllTests()
            exit(0)
        } catch {
            print("MacCompanionTests failed: \(error)")
            exit(1)
        }
    }
}
