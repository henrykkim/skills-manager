import Foundation
import Testing
@testable import SkillsManagerCore

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = 0
    var value: Int { lock.lock(); defer { lock.unlock() }; return _value }
    func increment() { lock.lock(); defer { lock.unlock() }; _value += 1 }
}

@Test func collapsesBurstIntoOneCall() async throws {
    let counter = Counter()
    let debouncer = Debouncer(delay: 0.1, queue: DispatchQueue(label: "test")) { counter.increment() }
    debouncer.call()
    debouncer.call()
    debouncer.call()
    try await Task.sleep(for: .milliseconds(400))
    #expect(counter.value == 1)
}

@Test func separateBurstsEachFire() async throws {
    let counter = Counter()
    let debouncer = Debouncer(delay: 0.05, queue: DispatchQueue(label: "test")) { counter.increment() }
    debouncer.call()
    try await Task.sleep(for: .milliseconds(200))
    debouncer.call()
    try await Task.sleep(for: .milliseconds(200))
    #expect(counter.value == 2)
}
