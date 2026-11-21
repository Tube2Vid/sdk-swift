import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Any non-2xx API response.
public struct Tube2VidAPIError: Error, LocalizedError, Sendable {
    public let status: Int
    /// The API's `error` field, or the raw body.
    public let message: String
    /// Machine-readable error code when the API sent one (e.g. "turnstile_failed").
    public let code: String?
    /// Raw response body.
    public let body: String?
    /// Parsed JSON body, if the body was JSON.
    public let data: JSONValue?

    public init(status: Int, body: String?) {
        self.status = status
        self.body = body?.isEmpty == false ? body : nil
        data = body.flatMap { try? JSONDecoder().decode(JSONValue.self, from: Data($0.utf8)) }
        code = data?["code"]?.stringValue
        message = data?["error"]?.stringValue ?? self.body ?? "Tube2Vid API request failed with \(status)"
    }

    public var errorDescription: String? { "Tube2Vid API error \(status): \(message)" }
}

/// Thrown by `waitForJob` when the job is still running after the timeout.
public struct Tube2VidTimeoutError: Error, Sendable {
    public let jobId: String
}

/// Client for the Tube2Vid API (https://tube2vid.com/docs).
public final class Tube2VidClient: Sendable {
    public static let defaultBaseURL = URL(string: "https://tube2vid.com")!
    public static let version = "0.1.0"

    public let baseURL: URL
    public let apiKey: String?
    public let headers: [String: String]
    private let session: URLSession
    private let noRedirectSession: URLSession

    /// - Parameters:
    ///   - apiKey: A `tv_live_...` key. Nil or empty falls back to the `TUBE2VID_API_KEY` environment variable.
    ///   - baseURL: API origin, default https://tube2vid.com.
    ///   - configuration: URLSession configuration, e.g. for timeouts or a test URLProtocol.
    ///   - headers: Extra headers sent with every API request.
    public init(apiKey: String? = nil, baseURL: URL = Tube2VidClient.defaultBaseURL,
                configuration: URLSessionConfiguration = .default, headers: [String: String] = [:]) {
        let key = (apiKey?.isEmpty == false ? apiKey : ProcessInfo.processInfo.environment["TUBE2VID_API_KEY"])?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.apiKey = key?.isEmpty == false ? key : nil
        var base = baseURL.absoluteString
        while base.hasSuffix("/") { base.removeLast() }
        self.baseURL = URL(string: base) ?? baseURL
        self.headers = headers
        session = URLSession(configuration: configuration)
        noRedirectSession = URLSession(configuration: configuration, delegate: NoRedirect(), delegateQueue: nil)
    }

    deinit {
        session.finishTasksAndInvalidate()
        noRedirectSession.finishTasksAndInvalidate()
    }

    // MARK: Public, no API key needed

    public func getHealth() async throws -> ServiceHealth { try await get("/healthz") }

    public func listPlatforms() async throws -> [PlatformSummary] { try await get("/v1/platforms") }

    public func getPlatformHealth() async throws -> [PlatformHealthRow] { try await get("/v1/platforms/health") }

    public func getStatusHistory(limit: Int = 50, platform: String? = nil) async throws -> [StatusHistoryItem] {
        var query = [URLQueryItem(name: "limit", value: String(limit))]
        if let platform { query.append(URLQueryItem(name: "platform", value: platform)) }
        return try await get("/v1/status/history", query: query)
    }

    public func getOperationalMetrics() async throws -> OperationalMetrics { try await get("/v1/ops/metrics") }

    public func getPowChallenge() async throws -> PowChallenge { try await get("/v1/challenges/pow") }

    /// Anonymous submission, as the website does it. Needs `pow` (and `turnstileToken` where the human check is on).
    public func submitPublicJob(_ input: JobSubmitInput) async throws -> QueuedJobResponse {
        try await post("/v1/public/jobs", input)
    }

    public func getPublicJobStatus(_ jobId: String) async throws -> PublicJobStatus {
        try await get("/v1/public/jobs/\(segment(jobId))")
    }

    /// Direct link to an anonymous job's file; it redirects to a short-lived signed URL.
    public func publicDownloadURL(_ jobId: String) -> URL { url("/v1/public/jobs/\(segment(jobId))/download") }

    public func publicThumbnailURL(_ jobId: String) -> URL { url("/v1/public/jobs/\(segment(jobId))/thumbnail") }

    // MARK: Authenticated, needs an API key

    public func submitAuthenticatedJob(_ input: JobSubmitInput) async throws -> QueuedJobResponse {
        try await post("/v1/jobs", input)
    }

    /// Uses /v1/jobs with an API key, /v1/public/jobs without one.
    public func submitJob(_ input: JobSubmitInput) async throws -> QueuedJobResponse {
        apiKey != nil ? try await submitAuthenticatedJob(input) : try await submitPublicJob(input)
    }

    /// Needs the jobs:read scope.
    public func getJobStatus(_ jobId: String) async throws -> JobStatus { try await get("/v1/jobs/\(segment(jobId))") }

    public func getJobEvents(_ jobId: String) async throws -> [JobEvent] { try await get("/v1/jobs/\(segment(jobId))/events") }

    /// Polls `getJobStatus` until the job is completed or failed, and returns the final job either way.
    /// Throws `Tube2VidTimeoutError` after `timeout`, and `CancellationError` if the task is cancelled.
    public func waitForJob(_ jobId: String, interval: TimeInterval = 2, timeout: TimeInterval = 15 * 60,
                           onUpdate: (@Sendable (JobStatus) -> Void)? = nil) async throws -> JobStatus {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            try Task.checkCancellation()
            let job = try await getJobStatus(jobId)
            onUpdate?(job)
            if job.status.isDone { return job }
            if Date().addingTimeInterval(interval) > deadline { throw Tube2VidTimeoutError(jobId: jobId) }
            try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        }
    }

    /// The authenticated download endpoint. It needs the bearer header, so prefer `getDownloadLink` or `downloadJob`.
    public func downloadURL(_ jobId: String) -> URL { url("/v1/jobs/\(segment(jobId))/download") }

    /// Resolves a completed job to its short-lived signed file URL, which needs no auth.
    public func getDownloadLink(_ jobId: String) async throws -> URL {
        let (data, response, location) = try await downloadResponse(jobId)
        if let location { return location }
        guard (200..<300).contains(response.statusCode) else { throw apiError(response, data) }
        throw Tube2VidAPIError(status: response.statusCode, body: "This API serves the file directly; use downloadJob instead.")
    }

    /// Fetches a completed job's file into memory. For large files, pass `getDownloadLink`'s URL to a URLSession download task.
    public func downloadJob(_ jobId: String) async throws -> Data {
        let (data, response, location) = try await downloadResponse(jobId)
        guard let location else {
            guard (200..<300).contains(response.statusCode) else { throw apiError(response, data) }
            return data
        }
        // The signed URL carries its own auth; the API key must not be sent to the storage host.
        let (file, fileResponse) = try await send(URLRequest(url: location), on: session)
        guard (200..<300).contains(fileResponse.statusCode) else { throw apiError(fileResponse, file) }
        return file
    }

    /// Needs the usage:read scope.
    public func getUsage() async throws -> UsageSummary { try await get("/v1/usage") }

    /// Needs the keys:read scope.
    public func listAPIKeys() async throws -> [APIKeySummary] { try await get("/v1/api-keys") }

    /// Needs the keys:write scope. The returned `key` is shown only once.
    public func createAPIKey(_ input: APIKeyCreateInput) async throws -> CreatedAPIKey { try await post("/v1/api-keys", input) }

    /// Needs the billing:write scope. Open `checkoutUrl` to pay.
    public func createCheckout(_ input: CheckoutInput) async throws -> CheckoutSession {
        try await post("/v1/billing/checkout", input)
    }

    // MARK: Internals

    private func downloadResponse(_ jobId: String) async throws -> (Data, HTTPURLResponse, URL?) {
        let (data, response) = try await send(authorized(URLRequest(url: downloadURL(jobId))), on: noRedirectSession)
        if (300..<400).contains(response.statusCode),
           let location = response.value(forHTTPHeaderField: "Location"),
           let target = URL(string: location, relativeTo: baseURL)?.absoluteURL {
            return (data, response, target)
        }
        return (data, response, nil)
    }

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        var components = URLComponents(url: url(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        return try await decode(authorized(URLRequest(url: components.url!)))
    }

    private func post<T: Decodable, B: Encodable>(_ path: String, _ body: B) async throws -> T {
        var request = authorized(URLRequest(url: url(path)))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return try await decode(request)
    }

    private func decode<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await send(request, on: session)
        guard (200..<300).contains(response.statusCode) else { throw apiError(response, data) }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func send(_ request: URLRequest, on session: URLSession) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }

    private func authorized(_ request: URLRequest) -> URLRequest {
        var request = request
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("tube2vid-swift/\(Self.version)", forHTTPHeaderField: "User-Agent")
        if let apiKey { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        return request
    }

    private func apiError(_ response: HTTPURLResponse, _ data: Data) -> Tube2VidAPIError {
        Tube2VidAPIError(status: response.statusCode, body: String(decoding: data, as: UTF8.self))
    }

    private func url(_ path: String) -> URL { URL(string: baseURL.absoluteString + path)! }

    private func segment(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

/// Stops URLSession from following the download redirect so the signed URL can be read.
private final class NoRedirect: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
