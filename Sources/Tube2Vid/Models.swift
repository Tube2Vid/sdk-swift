import Foundation

// Request and response shapes of the public Tube2Vid API (/v1/*).

/// What to extract from the source URL. Unknown values from newer API versions decode without error.
public struct JobMode: RawRepresentable, Codable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }
    public init(from decoder: Decoder) throws { rawValue = try decoder.singleValueContainer().decode(String.self) }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static let auto: JobMode = "auto"
    public static let video: JobMode = "video"
    public static let audio: JobMode = "audio"
    public static let gallery: JobMode = "gallery"
}

/// Lifecycle state of a download job. Unknown values from newer API versions decode without error.
public struct JobState: RawRepresentable, Codable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }
    public init(from decoder: Decoder) throws { rawValue = try decoder.singleValueContainer().decode(String.self) }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static let queued: JobState = "queued"
    public static let running: JobState = "running"
    public static let completed: JobState = "completed"
    public static let failed: JobState = "failed"

    /// True for `.completed` and `.failed`.
    public var isDone: Bool { self == .completed || self == .failed }
}

/// Any JSON value, for free-form fields such as event details.
public enum JSONValue: Codable, Hashable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }

    public subscript(key: String) -> JSONValue? {
        if case .object(let o) = self { return o[key] }
        return nil
    }

    public var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }
}

/// A solved challenge from `getPowChallenge()`. Only the anonymous browser flow needs it.
public struct ProofOfWork: Codable, Hashable, Sendable {
    public var nonce: String
    public var expiresAt: String
    public var difficulty: Int
    public var signature: String
    /// Any string such that sha256("nonce.expiresAt.difficulty.solution") starts with `difficulty` hex zeros.
    public var solution: String

    public init(nonce: String, expiresAt: String, difficulty: Int, signature: String, solution: String) {
        self.nonce = nonce; self.expiresAt = expiresAt; self.difficulty = difficulty; self.signature = signature; self.solution = solution
    }
}

public struct JobSubmitInput: Codable, Hashable, Sendable {
    public var url: String
    /// Force a platform slug instead of detecting it from the URL.
    public var platform: String?
    public var mode: JobMode?
    public var format: String?
    public var quality: String?
    /// Browser-only human check; not needed with an API key.
    public var turnstileToken: String?
    /// Browser-only work challenge; not needed with an API key.
    public var pow: ProofOfWork?

    public init(url: String, platform: String? = nil, mode: JobMode? = nil, format: String? = nil, quality: String? = nil,
                turnstileToken: String? = nil, pow: ProofOfWork? = nil) {
        self.url = url; self.platform = platform; self.mode = mode; self.format = format; self.quality = quality
        self.turnstileToken = turnstileToken; self.pow = pow
    }
}

public struct QueuedJobResponse: Codable, Hashable, Sendable {
    public var jobId: String
    public var status: JobState
    public var platform: String
    public var estimatedCredits: Int
    /// True when a public submission was folded into an identical recent job.
    public var deduped: Bool?
}

public struct PlatformProvider: Codable, Hashable, Sendable {
    public var id: String
    public var kind: String
    public var priority: Int
}

public struct PlatformSummary: Codable, Hashable, Sendable {
    public var slug: String
    public var name: String
    public var category: String
    public var supportLevel: String
    public var publicClaim: Bool
    public var capabilities: [String]
    public var providers: [PlatformProvider]
}

public struct PlatformHealthRow: Codable, Hashable, Sendable {
    public var platform: String
    public var name: String
    public var category: String
    public var supportLevel: String
    /// operational, degraded, partial_outage, down or beta.
    public var status: String
    public var auditCategory: String
    public var provider: String?
    public var providerKind: String?
    public var successRate: Double?
    public var medianExtractMs: Double?
    public var lastCheckedAt: String?
    public var note: String?
    public var reason: String?
    public var authNeeded: Bool?
    public var repaired: Bool?
}

public struct JobEvent: Codable, Hashable, Sendable {
    public var id: String
    public var jobId: String
    public var stage: String
    public var message: String
    public var details: JSONValue?
    public var createdAt: String
}

public struct LatestEvent: Codable, Hashable, Sendable {
    public var stage: String
    public var message: String?
    public var details: JSONValue?
    public var createdAt: String
}

/// Status of an anonymous job.
public struct PublicJobStatus: Codable, Hashable, Sendable {
    public var jobId: String
    public var platform: String
    public var status: JobState
    public var progress: Double
    public var provider: String?
    /// True when the file came from a reduced-quality last-resort provider.
    public var fallback: Bool?
    public var title: String?
    public var errorCode: String?
    public var errorMessage: String?
    public var completedAt: String?
    public var createdAt: String
    public var updatedAt: String
    public var latestEvent: LatestEvent?
}

/// Full status of an authenticated job.
public struct JobStatus: Codable, Hashable, Sendable {
    public var id: String
    public var jobId: String?
    public var userId: String?
    public var apiKeyId: String?
    public var url: String?
    public var platform: String?
    public var mode: JobMode?
    public var format: String?
    public var quality: String?
    public var creditsReserved: Int?
    public var status: JobState
    public var progress: Double?
    public var creditsCharged: Int?
    public var provider: String?
    public var title: String?
    public var outputPath: String?
    public var outputStorageKey: String?
    public var outputSize: Int?
    public var thumbnailUrl: String?
    public var errorCode: String?
    public var errorMessage: String?
    public var completedAt: String?
    public var createdAt: String?
    public var updatedAt: String?
}

public struct UsageSummary: Codable, Hashable, Sendable {
    public var creditBalance: Int
    public var jobsTotal: Int
    public var jobsCompleted: Int
    public var jobsFailed: Int
}

public struct StatusHistoryItem: Codable, Hashable, Sendable {
    public var id: String
    public var platform: String
    public var provider: String
    public var status: String
    public var durationMs: Double?
    public var errorCode: String?
    public var errorMessage: String?
    public var createdAt: String
}

public struct ProviderFailureRate: Codable, Hashable, Sendable {
    public var provider: String
    public var total: Int
    public var failed: Int
    public var failureRate: Double
}

public struct OpsAlert: Codable, Hashable, Sendable {
    /// info, warn or critical.
    public var level: String
    public var code: String
    public var message: String
}

public struct OperationalMetrics: Codable, Hashable, Sendable {
    public var generatedAt: String
    public var queueDepth: Int
    public var queuedJobs: Int
    public var runningJobs: Int
    public var completedJobs24h: Int
    public var failedJobs24h: Int
    public var p95JobDurationMs: Double?
    public var providerFailureRates: [ProviderFailureRate]
    public var alerts: [OpsAlert]
}

public struct ServiceHealth: Codable, Hashable, Sendable {
    public var ok: Bool
    public var service: String
    public var time: String
}

public struct PowChallenge: Codable, Hashable, Sendable {
    public var nonce: String
    public var expiresAt: String
    public var difficulty: Int
    public var signature: String
}

public struct APIKeyCreateInput: Codable, Hashable, Sendable {
    public var name: String
    /// jobs:write, jobs:read, usage:read, keys:read, keys:write or billing:write.
    /// Defaults to jobs:write, jobs:read and usage:read.
    public var scopes: [String]?
    /// 1-1000, defaults to 60.
    public var rateLimitPerMinute: Int?

    public init(name: String, scopes: [String]? = nil, rateLimitPerMinute: Int? = nil) {
        self.name = name; self.scopes = scopes; self.rateLimitPerMinute = rateLimitPerMinute
    }
}

public struct CreatedAPIKey: Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    /// The plaintext key. It is only ever returned once.
    public var key: String
    public var prefix: String
    public var scopes: [String]
}

public struct APIKeySummary: Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var prefix: String
    public var scopes: [String]
    public var rateLimitPerMinute: Int
    public var revokedAt: String?
    public var createdAt: String
}

public struct CheckoutInput: Codable, Hashable, Sendable {
    /// 1,000-250,000 credits.
    public var credits: Int?
    /// Legacy fixed pack: starter, builder or scale.
    public var pack: String?

    public init(credits: Int? = nil, pack: String? = nil) { self.credits = credits; self.pack = pack }
}

public struct CheckoutSession: Codable, Hashable, Sendable {
    /// Nil in placeholder mode.
    public var checkoutUrl: String?
    /// stripe or placeholder.
    public var mode: String
    public var sessionId: String?
    public var credits: Int
    public var amountCents: Int
    public var message: String?
}
