import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import Tube2Vid

/// Serves canned responses in order and records each request. No network.
final class StubProtocol: URLProtocol {
    struct Canned { var status: Int; var headers: [String: String] = [:]; var body: String = "" }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var queue: [Canned] = []
    nonisolated(unsafe) private(set) static var requests: [URLRequest] = []

    static func reset(_ responses: [Canned]) {
        lock.lock(); defer { lock.unlock() }
        queue = responses
        requests = []
    }

    static func recorded() -> [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return requests
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        Self.lock.lock()
        Self.requests.append(request)
        let canned = Self.queue.isEmpty ? Canned(status: 599, body: "unexpected request") : Self.queue.removeFirst()
        Self.lock.unlock()
        let response = HTTPURLResponse(url: request.url!, statusCode: canned.status, httpVersion: "HTTP/1.1", headerFields: canned.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(canned.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

final class Tube2VidClientTests: XCTestCase {
    private func client(apiKey: String?) -> Tube2VidClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return Tube2VidClient(apiKey: apiKey, baseURL: URL(string: "https://example.test/")!, configuration: configuration)
    }

    func testSendsTheAPIKeyAndParsesAPIErrors() async throws {
        StubProtocol.reset([.init(status: 402, body: #"{"error":"Insufficient credits","code":"no_credits"}"#)])
        do {
            _ = try await client(apiKey: "tv_live_x").submitJob(JobSubmitInput(url: "https://youtu.be/x"))
            XCTFail("expected an error")
        } catch let error as Tube2VidAPIError {
            XCTAssertEqual(error.status, 402)
            XCTAssertEqual(error.message, "Insufficient credits")
            XCTAssertEqual(error.code, "no_credits")
        }
        let request = try XCTUnwrap(StubProtocol.recorded().first)
        XCTAssertEqual(request.url?.absoluteString, "https://example.test/v1/jobs")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tv_live_x")
    }

    func testWithoutAKeySubmitJobUsesThePublicRoute() async throws {
        let client = client(apiKey: nil)
        try XCTSkipIf(client.apiKey != nil, "TUBE2VID_API_KEY is set in this environment")
        StubProtocol.reset([.init(status: 200, body: #"{"jobId":"j","status":"queued","platform":"youtube","estimatedCredits":0}"#)])
        let queued = try await client.submitJob(JobSubmitInput(url: "https://youtu.be/x"))
        XCTAssertEqual(queued.jobId, "j")
        XCTAssertEqual(queued.status, .queued)
        let request = try XCTUnwrap(StubProtocol.recorded().first)
        XCTAssertEqual(request.url?.absoluteString, "https://example.test/v1/public/jobs")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }

    func testDownloadJobFollowsTheSignedRedirectWithoutTheAPIKey() async throws {
        StubProtocol.reset([
            .init(status: 302, headers: ["Location": "https://cdn.test/file.mp4?sig=1"]),
            .init(status: 200, body: "bytes"),
        ])
        let data = try await client(apiKey: "tv_live_x").downloadJob("job 1")
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "bytes")
        let requests = StubProtocol.recorded()
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].url?.absoluteString, "https://example.test/v1/jobs/job%201/download")
        XCTAssertEqual(requests[1].url?.absoluteString, "https://cdn.test/file.mp4?sig=1")
        XCTAssertNil(requests[1].value(forHTTPHeaderField: "Authorization"))
    }

    func testWaitForJobPollsUntilATerminalState() async throws {
        let job = { (status: String) in StubProtocol.Canned(status: 200, body: #"{"id":"j","status":"\#(status)","progress":0}"#) }
        StubProtocol.reset([job("queued"), job("running"), job("completed")])
        let final = try await client(apiKey: "tv_live_x").waitForJob("j", interval: 0.001)
        XCTAssertEqual(final.status, .completed)
        XCTAssertEqual(StubProtocol.recorded().count, 3)
    }
}
