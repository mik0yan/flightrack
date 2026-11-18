import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// On-demand aircraft and route reference data, not current timetable or flight-status evidence.
public actor DetailsDataClient {
    private let session: URLSession
    private var cache: [String: AircraftDetails] = [:]
    private let cacheLifetime: TimeInterval = 3_600
    private let cacheCapacity = 128

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func fetchDetails(hex: String, callsign: String?) async throws -> AircraftDetails {
        let identifier = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard identifier.count == 6, identifier.allSatisfy({ $0.isASCII && $0.isHexDigit }) else {
            throw FlightAPIError.invalidAircraftIdentifier
        }
        let cleanedCallsign = callsign?.nilIfBlank?.uppercased()
        if let cleanedCallsign {
            guard (1...16).contains(cleanedCallsign.count), cleanedCallsign.allSatisfy({
                $0.isASCII && ($0.isLetter || $0.isNumber)
            }) else { throw FlightAPIError.invalidCallsign }
        }
        let key = identifier + ":" + (cleanedCallsign ?? "")
        if let details = cache[key], Date().timeIntervalSince(details.fetchedAt) < cacheLifetime { return details }

        var components = URLComponents(string: "https://api.adsbdb.com/v0/aircraft/\(identifier)")!
        if let cleanedCallsign { components.queryItems = [URLQueryItem(name: "callsign", value: cleanedCallsign)] }
        guard let url = components.url else { throw FlightAPIError.invalidResponse }
        var details = try await fetch(url: url)
        // An unknown aircraft can still have a known flight route.
        if details.aircraft == nil, details.route == nil, let cleanedCallsign,
           let callsignURL = URL(string: "https://api.adsbdb.com/v0/callsign/\(cleanedCallsign)") {
            details = try await fetch(url: callsignURL)
        }
        cache = cache.filter { Date().timeIntervalSince($0.value.fetchedAt) < cacheLifetime }
        if cache.count >= cacheCapacity, let oldest = cache.min(by: { $0.value.fetchedAt < $1.value.fetchedAt })?.key {
            cache.removeValue(forKey: oldest)
        }
        cache[key] = details
        return details
    }

    public static func decodeDetails(_ data: Data, fetchedAt: Date = Date()) throws -> AircraftDetails {
        let envelope = try JSONDecoder().decode(DetailsEnvelope.self, from: data)
        return AircraftDetails(aircraft: envelope.response.aircraft, route: envelope.response.flightroute, fetchedAt: fetchedAt)
    }

    private func fetch(url: URL) async throws -> AircraftDetails {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("FlightTrack-iPad/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        if (response as? HTTPURLResponse)?.statusCode == 404 {
            return AircraftDetails(aircraft: nil, route: nil)
        }
        try FlightDataClient.validate(response)
        return try Self.decodeDetails(data)
    }
}

private struct DetailsEnvelope: Decodable {
    let response: Payload

    struct Payload: Decodable {
        let aircraft: AircraftMetadata?
        let flightroute: FlightRoute?
    }
}
