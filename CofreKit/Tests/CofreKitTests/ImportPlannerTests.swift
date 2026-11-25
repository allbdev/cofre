import Foundation
import Testing

@testable import CofreKit

struct ImportPlannerTests {
    let stripeID = UUID()
    let awsID = UUID()

    private var existing: [SecretSummary] {
        [
            SecretSummary(id: stripeID, name: "Stripe key", createdAt: .now, updatedAt: .now),
            SecretSummary(id: awsID, name: "AWS", createdAt: .now, updatedAt: .now),
        ]
    }

    @Test func newNamesAreAlwaysAdded() {
        for strategy in ImportConflictStrategy.allCases {
            let plan = ImportPlanner.plan(incoming: ["GitHub", "Sentry"], existing: existing, strategy: strategy)
            #expect(plan.steps == [.add(index: 0, name: "GitHub"), .add(index: 1, name: "Sentry")])
        }
    }

    @Test func skipLeavesClashesAlone() {
        let plan = ImportPlanner.plan(incoming: ["stripe KEY", "New"], existing: existing, strategy: .skip)
        #expect(plan.steps == [.skip(index: 0), .add(index: 1, name: "New")])
        #expect((plan.addedCount, plan.replacedCount, plan.skippedCount) == (1, 0, 1))
    }

    @Test func replaceTargetsTheExistingSecret() {
        let plan = ImportPlanner.plan(incoming: ["Stripe Key", "aws"], existing: existing, strategy: .replace)
        #expect(plan.steps == [.replace(index: 0, id: stripeID), .replace(index: 1, id: awsID)])
    }

    @Test func keepBothRenames() {
        let plan = ImportPlanner.plan(incoming: ["Stripe key", "Stripe key"], existing: existing, strategy: .keepBoth)
        #expect(plan.steps == [.add(index: 0, name: "Stripe key (2)"), .add(index: 1, name: "Stripe key (3)")])
    }

    @Test func duplicatesInsideTheFileClashWithEachOther() {
        let incoming = ["Token", "token"]
        #expect(
            ImportPlanner.plan(incoming: incoming, existing: [], strategy: .skip).steps == [
                .add(index: 0, name: "Token"), .skip(index: 1),
            ])
        #expect(
            ImportPlanner.plan(incoming: incoming, existing: [], strategy: .replace).steps == [
                .add(index: 0, name: "Token"), .replacePending(index: 1, stepIndex: 0),
            ]
        )
        #expect(ImportPlanner.conflictCount(incoming: incoming, existing: []) == 1)
    }

    @Test func conflictCountCountsVaultAndFileClashes() {
        #expect(ImportPlanner.conflictCount(incoming: ["aws", "New", "new", "x"], existing: existing) == 2)
    }

    @Test func keepBothNeverProducesAClash() {
        var generator = SeededGenerator(seed: 11)
        let pool = ["Key", "key", "KEY (2)", "Token", "Café", "cafe", "A", "a (2)"]
        for _ in 0..<200 {
            let existingNames = (0..<Int.random(in: 0...4, using: &generator)).map { _ in
                pool.randomElement(using: &generator)!
            }
            let existing = Dictionary(grouping: existingNames, by: SecretName.key).values.map {
                SecretSummary(id: UUID(), name: $0[0], createdAt: .now, updatedAt: .now)
            }
            let incoming = (0..<Int.random(in: 1...6, using: &generator)).map { _ in
                pool.randomElement(using: &generator)!
            }
            let plan = ImportPlanner.plan(incoming: incoming, existing: existing, strategy: .keepBoth)
            var keys = Set(existing.map { SecretName.key($0.name) })
            for case .add(_, let name) in plan.steps {
                #expect(keys.insert(SecretName.key(name)).inserted, "\(name) clashes in \(plan.steps)")
            }
            #expect(plan.addedCount == incoming.count)
        }
    }
}
