import Foundation

/// A Sendable container for a cancellable Task, safe to use from deinit.
///
/// Use this instead of storing `Task<Void, Never>?` directly on `@MainActor`
/// classes that need to cancel tasks in deinit. The handle is a `let` constant
/// (allocated once), so deinit can call `cancel()` without actor isolation.
public final class TaskHandle: Sendable {
    private let storage = TaskStorage()

    public init() {}

    /// The managed task. Setting a new task cancels the previous one.
    public var task: Task<Void, Never>? {
        get { storage.get() }
        set {
            storage.get()?.cancel()
            storage.set(newValue)
        }
    }

    /// Cancels the current task and clears the handle.
    public func cancel() {
        storage.get()?.cancel()
        storage.set(nil)
    }
}

/// Lock-protected storage for the task reference.
private final class TaskStorage: Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var _task: Task<Void, Never>?

    func get() -> Task<Void, Never>? {
        lock.lock()
        defer { lock.unlock() }
        return _task
    }

    func set(_ newValue: Task<Void, Never>?) {
        lock.lock()
        defer { lock.unlock() }
        _task = newValue
    }
}
