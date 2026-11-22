import Foundation
import Synchronization

/// One recorded call to a `FakeLanguageModel`.
public struct FakeLanguageModelCall: Sendable, Hashable {
    public enum Kind: Sendable, Hashable { case generate, respond }
    public var kind: Kind
    /// `String(describing: Output.self)` for `generate`; nil for `respond`.
    public var typeName: String?
    public var prompt: AIPrompt
    public var options: AICallOptions
}

/// A deterministic, scripted `LanguageModeling` for tests (this module's and other modules'). Not for production use.
///
/// Answers come from, in order: the one-shot queue (`enqueue...`), a per-type scripted value (`script`), then the
/// handler. With none of those it throws `AIError.generation`. Structured answers are validated against the output
/// type's `AISchema` before decoding, so out-of-schema JSON fails with `.decoding` like the real model's would.
public final class FakeLanguageModel: LanguageModeling {
    public typealias GenerateHandler = @Sendable (_ typeName: String, _ prompt: AIPrompt) throws -> Data
    public typealias RespondHandler = @Sendable (_ prompt: AIPrompt) throws -> String

    private enum Step: Sendable {
        case json(Data)
        case text(String)
        case failure(AIError)
    }

    private struct State: Sendable {
        var availability: AIAvailability
        var delay: Duration?
        var queue: [Step] = []
        var typed: [String: Data] = [:]
        var calls: [FakeLanguageModelCall] = []
        var generateHandler: GenerateHandler?
        var respondHandler: RespondHandler?
    }

    private let state: Mutex<State>

    public init(availability: AIAvailability = .available, delay: Duration? = nil,
                generateHandler: GenerateHandler? = nil, respondHandler: RespondHandler? = nil) {
        state = Mutex(State(availability: availability, delay: delay, generateHandler: generateHandler, respondHandler: respondHandler))
    }

    // MARK: Scripting

    public func setAvailability(_ value: AIAvailability) { state.withLock { $0.availability = value } }
    public func setDelay(_ value: Duration?) { state.withLock { $0.delay = value } }

    /// The next `generate` answers with this raw JSON.
    public func enqueue(json: String) { state.withLock { $0.queue.append(.json(Data(json.utf8))) } }
    /// The next `generate` answers with this value encoded as JSON.
    public func enqueue<Value: Encodable>(_ value: Value) throws {
        let data = try JSONEncoder().encode(value)
        state.withLock { $0.queue.append(.json(data)) }
    }
    /// The next `respond` answers with this text.
    public func enqueue(text: String) { state.withLock { $0.queue.append(.text(text)) } }
    /// The next call (either kind) throws this error.
    public func enqueue(error: AIError) { state.withLock { $0.queue.append(.failure(error)) } }

    /// Every `generate` of `type` answers with this value (after the queue is empty).
    public func script<Output: AIGenerable>(_ value: Output, for type: Output.Type = Output.self) throws {
        let data = try JSONEncoder().encode(value)
        state.withLock { $0.typed[String(describing: type)] = data }
    }

    // MARK: Record

    public var calls: [FakeLanguageModelCall] { state.withLock { $0.calls } }
    public var callCount: Int { state.withLock { $0.calls.count } }

    // MARK: LanguageModeling

    public func availability() async -> AIAvailability { state.withLock { $0.availability } }

    public func generate<Output: AIGenerable>(_ type: Output.Type, prompt: AIPrompt, options: AICallOptions) async throws -> Output {
        let name = String(describing: type)
        let call = FakeLanguageModelCall(kind: .generate, typeName: name, prompt: prompt, options: options)
        let (delay, step, typed, handler) = state.withLock { s -> (Duration?, Step?, Data?, GenerateHandler?) in
            s.calls.append(call)
            let step = s.queue.isEmpty ? nil : s.queue.removeFirst()
            return (s.delay, step, s.typed[name], s.generateHandler)
        }
        try await wait(delay)
        let data: Data
        switch step {
        case .failure(let e): throw e
        case .json(let d): data = d
        case .text: throw AIError.generation("fake: a text answer was queued for a structured call")
        case nil:
            if let typed { data = typed }
            else if let handler {
                do { data = try handler(name, prompt) } catch { throw Self.asAIError(error) }
            } else { throw AIError.generation("fake: no scripted answer for \(name)") }
        }
        return try AISchemaValidation.decode(type, from: data)
    }

    public func respond(prompt: AIPrompt, options: AICallOptions) async throws -> String {
        let call = FakeLanguageModelCall(kind: .respond, typeName: nil, prompt: prompt, options: options)
        let (delay, step, handler) = state.withLock { s -> (Duration?, Step?, RespondHandler?) in
            s.calls.append(call)
            let step = s.queue.isEmpty ? nil : s.queue.removeFirst()
            return (s.delay, step, s.respondHandler)
        }
        try await wait(delay)
        switch step {
        case .failure(let e): throw e
        case .text(let t): return t
        case .json: throw AIError.generation("fake: a JSON answer was queued for a text call")
        case nil:
            guard let handler else { throw AIError.generation("fake: no scripted answer for respond") }
            do { return try handler(prompt) } catch { throw Self.asAIError(error) }
        }
    }

    private func wait(_ delay: Duration?) async throws {
        if Task.isCancelled { throw AIError.cancelled }
        guard let delay else { return }
        do { try await Task.sleep(for: delay) } catch { throw AIError.cancelled }
    }

    private static func asAIError(_ error: any Error) -> AIError {
        if let e = error as? AIError { return e }
        if error is CancellationError { return .cancelled }
        return .generation(error.localizedDescription)
    }
}
