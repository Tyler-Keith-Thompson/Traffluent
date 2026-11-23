internal import Events
internal import Generators
internal import Sampling
internal import SeedTrees

/// A tracker's samplers and the state their decisions have reached: each event sampler's
/// generator and each group sampler's latest group. The worker owns it and alone changes it.
struct SamplingStage {
    /// Where a sampler's next decision comes from.
    enum Draws {
        /// An event sampler's stream: one draw per record it applies to.
        case events(Xoshiro256StarStar)
        /// A group sampler's decisions.
        case groups(any GroupDecision)
    }

    private let samplers: [Sampler]
    private var draws: [Draws]

    /// The stage of `samplers`, drawing from `seed`.
    init(samplers: [Sampler], seed: UInt64) {
        self.samplers = samplers
        // A node per sampler, by its place in the list, so each has a stream of its own: a record
        // one sampler applies to takes no draw from another's, and appending a sampler shifts no
        // other's decisions.
        let tree = SeedTree(seed)
        draws = samplers.indices.map { index in
            let node = tree[index]
            guard let grouping = samplers[index].grouping else {
                return .events(node.generator(Xoshiro256StarStar.self))
            }
            return .groups(grouping(node, samplers[index].rate))
        }
    }

    /// Whether the stage has no samplers, and so keeps every record as it is.
    var isEmpty: Bool {
        samplers.isEmpty
    }

    /// Whether every sampler that applies to `record` keeps it; if so, and any applies, sets
    /// `record`'s ``SampleRateKey`` to the product of their rates.
    ///
    /// Every sampler that applies decides, even once another has dropped the record, so each
    /// one's stream moves the same whatever the others decide.
    mutating func keeps(_ record: inout EventRecord) -> Bool {
        var keeps = true
        var rate: SampleRate?
        for index in samplers.indices where samplers[index].selects(record) {
            guard let decision = decide(index, record) else { continue }
            keeps = keeps && decision
            rate = SampleRate((rate?.value ?? 1) * samplers[index].rate.value)
        }
        if keeps, let rate {
            record.context[SampleRateKey.self] = rate
        }
        return keeps
    }

    /// Sampler `index`'s decision on `record`; `nil` when the record is in none of its groups.
    private mutating func decide(_ index: Int, _ record: EventRecord) -> Bool? {
        switch draws[index] {
        case .events(var generator):
            let keeps = generator.bernoulli(samplers[index].rate.value)
            draws[index] = .events(generator)
            return keeps
        case .groups(var groups):
            let keeps = groups.keeps(record)
            draws[index] = .groups(groups)
            return keeps
        }
    }
}
