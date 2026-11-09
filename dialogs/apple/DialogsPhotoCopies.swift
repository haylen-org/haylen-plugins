#if os(iOS) || os(visionOS)
import Foundation

// The copies of the photos of one pick, which the queues of the providers fill in any order.
final class DialogsPhotoCopies: @unchecked Sendable {
    private let lock = NSLock()
    private var results: [Result<[String: String], any Error>?]

    init(count: Int) {
        results = Array(repeating: nil, count: count)
    }

    func store(_ index: Int, _ result: Result<[String: String], any Error>) {
        lock.lock()
        results[index] = result
        lock.unlock()
    }

    // The first failure, in the order of the pick.
    var failure: String? {
        lock.lock()
        defer { lock.unlock() }
        for case .failure(let error)? in results {
            return error.localizedDescription
        }
        return nil
    }

    var files: [[String: String]] {
        lock.lock()
        defer { lock.unlock() }
        return results.compactMap { try? $0?.get() }
    }
}
#endif
