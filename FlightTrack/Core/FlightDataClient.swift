import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum FlightAPIError: Error, LocalizedError, Sendable, Equatable {
    case invalidCoordinate
    case invalidRadius
    case invalidAircraftIdentifier
    case invalidCallsign
    case invalidResponse
    case httpStatus(Int)
    case rateLimited(retryAfterSeconds: Int?)

    public var errorDescription: String? {
        switch self {
        case .invalidCoordinate: "经纬度无效，请重新选择查询位置。"
        case .invalidRadius: "查询半径须在 1 至 463 公里之间。"
        case .invalidAircraftIdentifier: "暂不支持查询这架飞机的资料。"
        case .invalidCallsign: "航班呼号格式无效。"
        case .invalidResponse: "数据服务返回了无法识别的响应。"
        case .httpStatus(let status): "数据服务暂时无法使用（HTTP \(status)）。"
        case .rateLimited(let retry): retry.map { "查询过于频繁，请在 \($0) 秒后重试。" } ?? "查询过于频繁，请稍后重试。"
        }
    }
}

public actor FlightDataClient {
    private let session: URLSession
    private let clock = ContinuousClock()
    private var lastRequestStart: ContinuousClock.Instant?

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public static func makeNearbyURL(center: GeoCoordinate, radiusKilometers: Double) throws -> URL {
        guard center.isValid else { throw FlightAPIError.invalidCoordinate }
        guard radiusKilometers.isFinite, (1...463).contains(radiusKilometers) else { throw FlightAPIError.invalidRadius }
        let nauticalMiles = Int(ceil(radiusKilometers / 1.852))
        guard let url = URL(string: "https://opendata.adsb.fi/api/v3/lat/\(center.latitude)/lon/\(center.longitude)/dist/\(nauticalMiles)") else {
            throw FlightAPIError.invalidCoordinate
        }
        return url
    }

    public func fetchNearby(center: GeoCoordinate, radiusKilometers: Double) async throws -> FlightSnapshot {
        let url = try Self.makeNearbyURL(center: center, radiusKilometers: radiusKilometers)
        try await reserveRequestStart()
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("FlightTrack-iPad/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        try Self.validate(response)
        return try Self.decodeSnapshot(data, center: center, radiusKilometers: radiusKilometers)
    }

    /// Exposed for deterministic parser verification and replaying recorded snapshots.
    public static func decodeSnapshot(
        _ data: Data,
        center: GeoCoordinate,
        radiusKilometers: Double,
        receivedAt: Date = Date()
    ) throws -> FlightSnapshot {
        _ = try makeNearbyURL(center: center, radiusKilometers: radiusKilometers)
        let response = try JSONDecoder().decode(NearbyResponse.self, from: data)
        let capturedAt: Date
        if let now = response.now {
            // adsb.fi's ADSBexchange-compatible `now` is milliseconds since Unix epoch.
            capturedAt = Date(timeIntervalSince1970: now / 1_000)
        } else {
            capturedAt = receivedAt
        }
        let aircraft = (response.aircraft ?? []).filter { aircraft in
            guard let coordinate = aircraft.coordinate else { return false }
            return FlightGeometry.distanceKilometers(from: center, to: coordinate) <= radiusKilometers
        }
        return FlightSnapshot(aircraft: aircraft, capturedAt: capturedAt)
    }

    /// Actor reentrancy is intentional: every waiting caller rechecks the *actual*
    /// previous start time before claiming the next slot, even after device sleep.
    private func reserveRequestStart() async throws {
        while let lastRequestStart {
            let elapsed = lastRequestStart.duration(to: clock.now)
            guard elapsed < .seconds(1) else { break }
            try await Task.sleep(for: .seconds(1) - elapsed)
        }
        try Task.checkCancellation()
        lastRequestStart = clock.now
    }

    static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw FlightAPIError.invalidResponse }
        if http.statusCode == 429 {
            throw FlightAPIError.rateLimited(retryAfterSeconds: http.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init))
        }
        guard (200...299).contains(http.statusCode) else { throw FlightAPIError.httpStatus(http.statusCode) }
    }
}

private struct NearbyResponse: Decodable {
    let now: Double?
    let aircraft: [Aircraft]?

    private enum CodingKeys: String, CodingKey { case now, ac }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard values.contains(.ac) else {
            throw DecodingError.keyNotFound(CodingKeys.ac, .init(codingPath: values.codingPath, debugDescription: "Aircraft field missing from nearby response"))
        }
        now = values.doubleOrNil(forKey: .now)
        // A null `ac` is an observed empty area, not a decoder failure.
        aircraft = try values.decodeIfPresent([Aircraft].self, forKey: .ac)
    }
}
