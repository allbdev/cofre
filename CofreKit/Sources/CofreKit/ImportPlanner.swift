import Foundation

/// What to do when an imported name matches one already in the vault (or earlier in the file).
public enum ImportConflictStrategy: String, Sendable, CaseIterable, Identifiable {
    case skip
    case replace
    case keepBoth

    public var id: String { rawValue }
}

/// The steps an import will take, worked out before touching the store.
public struct ImportPlan: Equatable, Sendable {
    public enum Step: Equatable, Sendable {
        /// Add incoming item `index` under `name` (which may be a "(2)" variant).
        case add(index: Int, name: String)
        /// Replace the value of the existing secret `id` with incoming item `index`.
        case replace(index: Int, id: UUID)
        /// Replace the value of a secret added earlier in this same import (step `stepIndex`).
        case replacePending(index: Int, stepIndex: Int)
        case skip(index: Int)
    }

    public var steps: [Step]

    public var addedCount: Int {
        steps.count { if case .add = $0 { true } else { false } }
    }

    public var replacedCount: Int {
        steps.count {
            switch $0 {
            case .replace, .replacePending: true
            default: false
            }
        }
    }

    public var skippedCount: Int {
        steps.count { if case .skip = $0 { true } else { false } }
    }
}

public enum ImportPlanner {
    /// Number of incoming names that clash with the vault or with an earlier incoming name.
    public static func conflictCount(incoming: [String], existing: [SecretSummary]) -> Int {
        var seen = Set(existing.map { SecretName.key($0.name) })
        var conflicts = 0
        for name in incoming {
            if !seen.insert(SecretName.key(name)).inserted { conflicts += 1 }
        }
        return conflicts
    }

    public static func plan(
        incoming: [String],
        existing: [SecretSummary],
        strategy: ImportConflictStrategy
    ) -> ImportPlan {
        enum Target {
            case existing(UUID)
            case pending(stepIndex: Int)
        }

        var targets: [String: Target] = [:]
        for summary in existing {
            targets[SecretName.key(summary.name)] = .existing(summary.id)
        }
        var steps: [ImportPlan.Step] = []

        for (index, name) in incoming.enumerated() {
            let key = SecretName.key(name)
            guard let target = targets[key] else {
                targets[key] = .pending(stepIndex: steps.count)
                steps.append(.add(index: index, name: name))
                continue
            }
            switch strategy {
            case .skip:
                steps.append(.skip(index: index))
            case .replace:
                switch target {
                case .existing(let id):
                    steps.append(.replace(index: index, id: id))
                case .pending(let stepIndex):
                    steps.append(.replacePending(index: index, stepIndex: stepIndex))
                }
            case .keepBoth:
                let variant = SecretName.uniqueVariant(of: name, takenKeys: Set(targets.keys))
                targets[SecretName.key(variant)] = .pending(stepIndex: steps.count)
                steps.append(.add(index: index, name: variant))
            }
        }
        return ImportPlan(steps: steps)
    }
}
