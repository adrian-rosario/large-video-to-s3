import Testing
import Foundation
@testable import TransferKit

@Suite struct PartPlannerTests {
    @Test func splitsEvenly() {
        let parts = PartPlanner.plan(totalSize: 20, partSize: 5)
        #expect(parts.count == 4)
        #expect(parts.map(\.size) == [5, 5, 5, 5])
        #expect(parts.map(\.number) == [1, 2, 3, 4])
    }

    @Test func lastPartIsRemainder() {
        let parts = PartPlanner.plan(totalSize: 23, partSize: 10)
        #expect(parts.map(\.size) == [10, 10, 3])
        #expect(parts.map(\.offset) == [0, 10, 20])
    }

    @Test func zeroSizeYieldsNoParts() {
        #expect(PartPlanner.plan(totalSize: 0, partSize: 5).isEmpty)
    }
}
