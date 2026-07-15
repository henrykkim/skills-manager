import Foundation

/// Collapses a burst of call() invocations into a single action after `delay`.
/// Thread-safe; the action runs on `queue`.
public final class Debouncer: @unchecked Sendable {
    private let delay: TimeInterval
    private let queue: DispatchQueue
    private let action: @Sendable () -> Void
    private let lock = NSLock()
    private var pending: DispatchWorkItem?

    public init(delay: TimeInterval, queue: DispatchQueue = .main,
                action: @escaping @Sendable () -> Void) {
        self.delay = delay
        self.queue = queue
        self.action = action
    }

    public func call() {
        lock.lock()
        defer { lock.unlock() }
        pending?.cancel()
        let item = DispatchWorkItem(block: action)
        pending = item
        queue.asyncAfter(deadline: .now() + delay, execute: item)
    }
}
