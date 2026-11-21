# Tube2Vid Swift SDK

The official Swift package for the Tube2Vid YouTube, TikTok and Instagram video downloader API: download video, audio and images from 1,800+ sites in Swift on iOS, macOS and Linux, with async/await and Codable models.

[![CI](https://github.com/Tube2Vid/sdk-swift/actions/workflows/ci.yml/badge.svg)](https://github.com/Tube2Vid/sdk-swift/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/Tube2Vid/sdk-swift)](https://github.com/Tube2Vid/sdk-swift/releases)
[![Swift versions](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FTube2Vid%2Fsdk-swift%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/Tube2Vid/sdk-swift)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

[Tube2Vid](https://tube2vid.com) turns a link from YouTube, TikTok, Instagram, X, Reddit, Vimeo, SoundCloud and 1,800+ other sites into a downloadable MP4, MP3 or image file. This package wraps the [Tube2Vid REST API](https://tube2vid.com/docs) using only Foundation's `URLSession`.

## Install

In `Package.swift`:

```swift
.package(url: "https://github.com/Tube2Vid/sdk-swift.git", from: "0.1.0")
// and in your target:
.product(name: "Tube2Vid", package: "sdk-swift")
```

Or in Xcode: File > Add Package Dependencies, then paste `https://github.com/Tube2Vid/sdk-swift`. Needs Swift 5.10+, iOS 15 / macOS 12 / tvOS 15 / watchOS 8 / visionOS 1, or Linux. [Get an API key](https://tube2vid.com/pricing).

## Quickstart

```swift
import Tube2Vid

let client = Tube2VidClient() // reads TUBE2VID_API_KEY; or Tube2VidClient(apiKey: "tv_live_...")
let queued = try await client.submitJob(JobSubmitInput(
    url: "https://www.youtube.com/watch?v=dQw4w9WgXcQ", mode: .auto, format: "mp4", quality: "best"))
let job = try await client.waitForJob(queued.jobId) // polls every 2s, up to 15 min
guard job.status == .completed else { fatalError(job.errorMessage ?? "failed") }
let link = try await client.getDownloadLink(job.id) // short-lived signed URL, no auth needed
print(link)
```

`downloadJob(job.id)` returns the file as `Data` instead; for large files, hand the link to a `URLSession` download task. For audio only, use `mode: .audio, format: "mp3"`.

## Methods

| Method | Endpoint | Scope |
| --- | --- | --- |
| `submitJob`, `submitAuthenticatedJob` | `POST /v1/jobs` | `jobs:write` |
| `getJobStatus`, `waitForJob` | `GET /v1/jobs/{id}` | `jobs:read` |
| `getJobEvents` | `GET /v1/jobs/{id}/events` | `jobs:read` |
| `downloadJob`, `getDownloadLink`, `downloadURL` | `GET /v1/jobs/{id}/download` | `jobs:read` |
| `getUsage` | `GET /v1/usage` | `usage:read` |
| `listAPIKeys` / `createAPIKey` | `/v1/api-keys` | `keys:read` / `keys:write` |
| `createCheckout` | `POST /v1/billing/checkout` | `billing:write` |
| `getHealth`, `listPlatforms`, `getPlatformHealth`, `getStatusHistory`, `getOperationalMetrics` | public | none |
| `getPowChallenge`, `submitPublicJob`, `getPublicJobStatus`, `publicDownloadURL`, `publicThumbnailURL` | anonymous browser flow | none |

Without an API key, `submitJob` falls back to the anonymous `/v1/public/jobs` route, which needs a solved proof-of-work challenge. Apps that ship to users should call your own backend, which holds the key, rather than embedding a key in the app.

## Error handling

Every non-2xx response throws `Tube2VidAPIError` with `status`, `message`, `code` (when the API sends one), the raw `body` and the parsed JSON `data`.

```swift
do {
    let usage = try await client.getUsage()
    print("\(usage.creditBalance) credits left")
} catch let error as Tube2VidAPIError where error.status == 402 {
    print("Out of credits: \(error.message)") // top up at https://tube2vid.com/pricing
}
```

| Status | Meaning |
| --- | --- |
| 400 | Invalid body or `unsupported_platform` |
| 401 | Missing or invalid API key |
| 402 | Not enough credits |
| 403 | The key lacks the scope, or the job is not yours |
| 404 | Unknown job |
| 409 | The job has not completed yet |
| 410 | The file has expired |

`waitForJob` throws `Tube2VidTimeoutError` after its timeout and `CancellationError` if the task is cancelled. A failed job is not an error: check `job.status` and `job.errorMessage`. Its reserved credits are refunded.

## Configuration

```swift
let configuration = URLSessionConfiguration.default
configuration.timeoutIntervalForRequest = 60
let client = Tube2VidClient(
    apiKey: "tv_live_...",                               // nil reads TUBE2VID_API_KEY
    baseURL: URL(string: "https://staging.example.com")!, // default https://tube2vid.com
    configuration: configuration,
    headers: ["X-Request-Source": "my-app"])
let job = try await client.waitForJob(id, interval: 5, timeout: 1800) { print($0.progress ?? 0) }
```

## Links

- [Tube2Vid online video downloader](https://tube2vid.com)
- [Tube2Vid API documentation](https://tube2vid.com/docs)
- [Pricing and API keys](https://tube2vid.com/pricing)
- [Live platform status](https://tube2vid.com/status) for YouTube, TikTok, Instagram and every other supported site

Other languages: [TypeScript](https://github.com/Tube2Vid/sdk), [Python](https://github.com/Tube2Vid/sdk-python), [Go](https://github.com/Tube2Vid/sdk-go), [Java](https://github.com/Tube2Vid/sdk-java), [C#](https://github.com/Tube2Vid/sdk-dotnet), [PHP](https://github.com/Tube2Vid/sdk-php), [Ruby](https://github.com/Tube2Vid/sdk-ruby), [Rust](https://github.com/Tube2Vid/sdk-rust), [Swift](https://github.com/Tube2Vid/sdk-swift).

## License

[MIT](LICENSE). Copyright (c) 2026 Tube2Vid.
