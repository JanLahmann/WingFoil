#if DEV
import CryptoKit
import DeviceCheck
import Foundation

/// **Ask CleanJibe's line to the assistant** — dev only (docs/channels.md).
///
/// The assistant is the shared Worker the Fun with Quantum site runs (site `cleanjibe`,
/// JanLahmann/Fun-with-Quantum `assistant/src/app-auth.ts`). A native app has no Origin to be
/// allow-listed by, so it proves it is this app with App Attest instead:
///
///   1. once per install: a Secure Enclave key, attested against a one-time challenge
///      (`/attest/challenge`, `/attest`) — Apple vouches that the key belongs to this bundle;
///   2. every hour: an assertion with that key over a fresh challenge (`/token`);
///   3. `/chat` and `/feedback` carry the hour's token in `X-CleanJibe-Token`, and no Origin.
///
/// The key id is not a secret (the key never leaves the Secure Enclave), so it lives in
/// UserDefaults. A key that stops working — a restore onto another phone, a key the Worker
/// purged after 30 unused days — is thrown away and a new one attested, once.
actor AskClient {
    static let shared = AskClient()

    static let base = URL(string: "https://fwq-assistant.jan-35c.workers.dev")!
    static let site = "cleanjibe"
    private static let keyDefault = "ask.appAttestKeyId"

    enum Context: String, Sendable { case help, session }

    enum Event: Sendable {
        case delta(String)
        /// The answer is complete; `id` is what a thumbs vote refers to.
        case done(id: String)
    }

    enum Failure: Error, Equatable {
        case unsupported        // simulator, or a device without App Attest
        case limit              // 20 questions today
        case busy               // the shared daily budget is spent
        case attest             // the Worker refused this app's key
        case network
        case server

        var message: String {
            switch self {
            case .unsupported: "Ask CleanJibe needs a real iPhone or iPad."
            case .limit: "That was today's 20 questions. Ask again tomorrow."
            case .busy: "Ask CleanJibe has answered all it can today. Try again tomorrow."
            case .attest: "This iPhone could not be confirmed as CleanJibe. Try again later."
            case .network: "No connection. Check your internet and try again."
            case .server: "No answer this time. Try again."
            }
        }
    }

    struct Turn: Sendable { var role: String; var content: String }

    private var token: String?
    private var tokenExpires = Date.distantPast
    private let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.httpCookieStorage = nil
        c.timeoutIntervalForRequest = 60
        return URLSession(configuration: c)
    }()

    static var isSupported: Bool { DCAppAttestService.shared.isSupported }

    // MARK: - Asking

    /// One question, answered as a stream of text pieces and then `done`.
    func ask(_ question: String, context: Context, state: Data,
             history: [Turn]) -> AsyncThrowingStream<Event, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.stream(question, context: context, state: state,
                                          history: history, into: continuation, retry: true)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// A thumbs up (1) or down (-1) on an answer. Best effort: a lost vote is not an error.
    func vote(_ id: String, _ vote: Int) async {
        guard let token = try? await validToken() else { return }
        var req = Self.request("/feedback", token: token)
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["id": id, "vote": vote])
        _ = try? await session.data(for: req)
    }

    private func stream(_ question: String, context: Context, state: Data, history: [Turn],
                        into out: AsyncThrowingStream<Event, Error>.Continuation,
                        retry: Bool) async throws {
        let token = try await validToken()
        var req = Self.request("/chat", token: token)
        let stateObject = (try? JSONSerialization.jsonObject(with: state)) ?? [String: Any]()
        let body: [String: Any] = [
            "site": Self.site,
            "context": context.rawValue,
            "locale": Self.locale,
            "question": question,
            "state": stateObject,
            "history": history.map { ["role": $0.role, "content": $0.content] },
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        let (bytes, response): (URLSession.AsyncBytes, URLResponse)
        do { (bytes, response) = try await session.bytes(for: req) } catch { throw Failure.network }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            var data = Data()
            for try await b in bytes { data.append(b) }
            let error = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            if status == 401, error == "token", retry {
                self.token = nil
                return try await stream(question, context: context, state: state,
                                        history: history, into: out, retry: false)
            }
            throw Self.failure(status: status)
        }

        // Server-sent events: `event: delta|done|error`, then `data: {json}`, then a blank line.
        var event = ""
        for try await line in bytes.lines {
            if line.hasPrefix("event:") {
                event = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("data:") {
                let json = Data(line.dropFirst(5).trimmingCharacters(in: .whitespaces).utf8)
                let data = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any] ?? [:]
                switch event {
                case "delta": if let t = data["t"] as? String { out.yield(.delta(t)) }
                case "done": out.yield(.done(id: data["id"] as? String ?? "")); return
                case "error": throw Failure.server
                default: break
                }
            }
        }
        throw Failure.server     // the stream ended without `done`
    }

    // MARK: - App Attest

    private func validToken() async throws -> String {
        if let token, tokenExpires.timeIntervalSinceNow > 60 { return token }
        guard Self.isSupported else { throw Failure.unsupported }
        if let keyId = UserDefaults.standard.string(forKey: Self.keyDefault) {
            do { return try await refresh(keyId) } catch Failure.attest {
                UserDefaults.standard.removeObject(forKey: Self.keyDefault)
            }
        }
        return try await attestNewKey()
    }

    private func attestNewKey() async throws -> String {
        let service = DCAppAttestService.shared
        let keyId: String
        do { keyId = try await service.generateKey() } catch { throw Failure.attest }
        let challenge = try await self.challenge()
        let attestation: Data
        do {
            attestation = try await service.attestKey(keyId, clientDataHash: Self.hash(challenge))
        } catch {
            throw Self.isNetworkish(error) ? Failure.network : Failure.attest
        }
        let reply = try await post("/attest", [
            "site": Self.site, "keyId": keyId, "challenge": challenge,
            "attestation": attestation.base64EncodedString(),
            "bundleId": Bundle.main.bundleIdentifier ?? "",
        ])
        UserDefaults.standard.set(keyId, forKey: Self.keyDefault)
        return try keep(reply)
    }

    private func refresh(_ keyId: String) async throws -> String {
        let challenge = try await self.challenge()
        let assertion: Data
        do {
            assertion = try await DCAppAttestService.shared
                .generateAssertion(keyId, clientDataHash: Self.hash(challenge))
        } catch {
            throw Self.isNetworkish(error) ? Failure.network : Failure.attest
        }
        let reply = try await post("/token", [
            "site": Self.site, "keyId": keyId, "challenge": challenge,
            "assertion": assertion.base64EncodedString(),
        ])
        return try keep(reply)
    }

    private func challenge() async throws -> String {
        let reply = try await post("/attest/challenge", ["site": Self.site])
        guard let c = reply["challenge"] as? String else { throw Failure.server }
        return c
    }

    private func keep(_ reply: [String: Any]) throws -> String {
        guard let t = reply["token"] as? String else { throw Failure.server }
        token = t
        let expires = (reply["expires"] as? String).flatMap { try? Date($0, strategy: .iso8601) }
        tokenExpires = expires ?? Date(timeIntervalSinceNow: 50 * 60)
        return t
    }

    private func post(_ path: String, _ body: [String: Any]) async throws -> [String: Any] {
        var req = Self.request(path, token: nil)
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data: Data, response: URLResponse
        do { (data, response) = try await session.data(for: req) } catch { throw Failure.network }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard status == 200 else {
            throw status == 401 ? Failure.attest : Self.failure(status: status)
        }
        return json
    }

    // MARK: - Pieces

    private static func request(_ path: String, token: String?) -> URLRequest {
        var req = URLRequest(url: base.appending(path: path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { req.setValue(token, forHTTPHeaderField: "X-CleanJibe-Token") }
        return req
    }

    /// What the app signs: SHA-256 of the challenge string's UTF-8 bytes (app-auth.ts).
    private static func hash(_ challenge: String) -> Data {
        Data(SHA256.hash(data: Data(challenge.utf8)))
    }

    private static func failure(status: Int) -> Failure {
        switch status {
        case 429: .limit
        case 503: .busy
        case 401, 403: .attest
        default: .server
        }
    }

    private static func isNetworkish(_ error: Error) -> Bool {
        (error as? DCError)?.code == .serverUnavailable || error is URLError
    }

    /// The question's language, so the answer comes back in it (the Worker takes `xx` or `xx-YY`).
    private static var locale: String {
        Locale.current.language.languageCode?.identifier ?? "en"
    }
}
#endif
