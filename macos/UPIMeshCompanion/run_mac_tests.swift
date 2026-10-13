import Foundation

@main
struct MacCompanionTestRunner {
    static func main() {
        do {
            try MacCompanionTests.runAllTests()
            exit(0)
        } catch {
            print("MacCompanionTests failed: \(error)")
            exit(1)
        }
    }
}
