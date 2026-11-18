import Foundation
import XCTest
@testable import FlightTrackCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor
final class FlightTrackCoreTests: XCTestCase {
    private let center = GeoCoordinate(latitude: 0, longitude: 0)

    func testNearbyURLRoundsNauticalMilesUpAndRejectsInvalidInput() throws {
        let point = GeoCoordinate(latitude: 30.17284, longitude: 120.264387)
        let url = try FlightDataClient.makeNearbyURL(center: point, radiusKilometers: 50)
        XCTAssertEqual(url.absoluteString, "https://opendata.adsb.fi/api/v3/lat/30.17284/lon/120.264387/dist/27")
        XCTAssertEqual(try FlightDataClient.makeNearbyURL(center: point, radiusKilometers: 20).lastPathComponent, "11")
        XCTAssertEqual(try FlightDataClient.makeNearbyURL(center: point, radiusKilometers: 463).lastPathComponent, "250")
        XCTAssertThrowsError(try FlightDataClient.makeNearbyURL(center: point, radiusKilometers: .nan))
        XCTAssertThrowsError(try FlightDataClient.makeNearbyURL(center: point, radiusKilometers: 464))
        XCTAssertThrowsError(try FlightDataClient.makeNearbyURL(center: GeoCoordinate(latitude: 100, longitude: 0), radiusKilometers: 50))
    }

    func testAircraftDecodesMixedNumbersAndTrimsCallsign() throws {
        let data = Data(#"{"hex":"781159","flight":" CCA9815 ","r":"B-8583","t":"A321","lat":"30.070418","lon":120.415265,"alt_baro":8600,"alt_geom":"9000","gs":290.7,"track":224.02,"baro_rate":3136,"seen_pos":38.907,"seen":38.9}"#.utf8)
        let aircraft = try JSONDecoder().decode(Aircraft.self, from: data)
        XCTAssertEqual(aircraft.callsign, "CCA9815")
        XCTAssertEqual(aircraft.coordinate?.latitude, 30.070418)
        XCTAssertEqual(aircraft.altitudeMeters!, 2_743.2, accuracy: 0.001)
        XCTAssertEqual(aircraft.groundSpeedKilometersPerHour!, 538.3764, accuracy: 0.001)
        XCTAssertEqual(aircraft.positionAgeSeconds, 38.907)
        XCTAssertEqual(aircraft.verticalRateFeetPerMinute, 3136)
        XCTAssertFalse(aircraft.isOnGround)
    }

    func testGroundAndMissingValuesNeverInventAltitudeOrAge() throws {
        let aircraft = try JSONDecoder().decode(Aircraft.self, from: Data(#"{"hex":"ABC123","flight":"   ","r":null,"alt_baro":"ground","lat":91,"lon":0,"seen_pos":null,"gs":"unknown"}"#.utf8))
        XCTAssertEqual(aircraft.hex, "abc123")
        XCTAssertTrue(aircraft.isOnGround)
        XCTAssertNil(aircraft.altitudeMeters)
        XCTAssertNil(aircraft.positionAgeSeconds)
        XCTAssertNil(aircraft.lastMessageAgeSeconds)
        XCTAssertNil(aircraft.groundSpeedKnots)
        XCTAssertNil(aircraft.callsign)
        XCTAssertNil(aircraft.coordinate)
    }

    func testSnapshotFiltersExactRadiusAndPreservesStaleAge() throws {
        let json = #"{"now":1791121068001,"ac":[{"hex":"000001","lat":0,"lon":0.44,"seen_pos":120},{"hex":"000002","lat":0,"lon":0.46},{"hex":"000003","alt_baro":1000},{"hex":"000004","lat":null,"lon":0}]}"#
        let snapshot = try FlightDataClient.decodeSnapshot(Data(json.utf8), center: center, radiusKilometers: 50)
        XCTAssertEqual(snapshot.aircraft.map(\.hex), ["000001"])
        XCTAssertEqual(snapshot.aircraft.first?.positionAgeSeconds, 120)
        XCTAssertEqual(snapshot.capturedAt.timeIntervalSince1970, 1_791_121_068.001, accuracy: 0.001)
    }

    func testSnapshotAcceptsNullAircraftAndUsesReceiptTimeIfTimeMissing() throws {
        let receipt = Date(timeIntervalSince1970: 100)
        let snapshot = try FlightDataClient.decodeSnapshot(Data(#"{"ac":null}"#.utf8), center: center, radiusKilometers: 50, receivedAt: receipt)
        XCTAssertTrue(snapshot.aircraft.isEmpty)
        XCTAssertEqual(snapshot.capturedAt, receipt)
        XCTAssertThrowsError(try FlightDataClient.decodeSnapshot(Data(#"{"error":"unavailable"}"#.utf8), center: center, radiusKilometers: 50))
    }

    func testCardinalBearingsAndDateLineDistance() {
        XCTAssertEqual(FlightGeometry.bearingDegrees(from: center, to: GeoCoordinate(latitude: 1, longitude: 0)), 0, accuracy: 0.001)
        XCTAssertEqual(FlightGeometry.bearingDegrees(from: center, to: GeoCoordinate(latitude: 0, longitude: 1)), 90, accuracy: 0.001)
        XCTAssertEqual(FlightGeometry.bearingDegrees(from: center, to: GeoCoordinate(latitude: -1, longitude: 0)), 180, accuracy: 0.001)
        XCTAssertEqual(FlightGeometry.bearingDegrees(from: center, to: GeoCoordinate(latitude: 0, longitude: -1)), 270, accuracy: 0.001)
        XCTAssertEqual(FlightGeometry.distanceKilometers(from: GeoCoordinate(latitude: 0, longitude: 179.9), to: GeoCoordinate(latitude: 0, longitude: -179.9)), 22.239, accuracy: 0.01)
    }

    func testWGS84LocalFrameAndEarthCurvature() {
        let east = FlightGeometry.relativePosition(observer: center, observerAltitudeMeters: 0, target: GeoCoordinate(latitude: 0, longitude: 0.01), targetAltitudeMeters: 0)
        XCTAssertEqual(east.eastMeters, 1113.1949, accuracy: 0.01)
        XCTAssertEqual(east.northMeters, 0, accuracy: 0.001)
        XCTAssertEqual(east.azimuthDegrees, 90, accuracy: 0.001)
        let north = FlightGeometry.relativePosition(observer: center, observerAltitudeMeters: 0, target: GeoCoordinate(latitude: 0.01, longitude: 0), targetAltitudeMeters: 0)
        XCTAssertEqual(north.northMeters, 1105.7428, accuracy: 0.01)
        XCTAssertEqual(north.eastMeters, 0, accuracy: 0.001)
        let up = FlightGeometry.relativePosition(observer: center, observerAltitudeMeters: 10, target: center, targetAltitudeMeters: 1010)
        XCTAssertEqual(up.upMeters, 1000, accuracy: 0.001)
        XCTAssertEqual(up.elevationDegrees, 90, accuracy: 0.001)
        let horizon = FlightGeometry.relativePosition(observer: center, observerAltitudeMeters: 0, target: GeoCoordinate(latitude: 0, longitude: 1), targetAltitudeMeters: 0)
        XCTAssertEqual(horizon.upMeters, -971.421, accuracy: 0.01)
        XCTAssertEqual(horizon.elevationDegrees, -0.5, accuracy: 0.001)
    }

    func testDetailsDecodeCombinedAndNullFields() throws {
        let data = Data(#"{"response":{"aircraft":{"type":"A321-231","manufacturer":"Airbus","registration":"B-8583","registered_owner":"Example Airline","registered_owner_country_name":"China","url_photo":null},"flightroute":{"callsign_iata":"CA9815","airline":{"name":"Example Airline"},"origin":{"name":"Hangzhou Xiaoshan International Airport","iata_code":"HGH","icao_code":"ZSHC","municipality":"Hangzhou","latitude":30.2295,"longitude":120.434},"destination":{"name":"Demo Destination","iata_code":"XYZ","icao_code":null,"latitude":null}}}}"#.utf8)
        let details = try DetailsDataClient.decodeDetails(data)
        XCTAssertEqual(details.aircraft?.manufacturer, "Airbus")
        XCTAssertEqual(details.aircraft?.typeName, "A321-231")
        XCTAssertNil(details.aircraft?.photoURL)
        XCTAssertEqual(details.route?.callsignIATA, "CA9815")
        XCTAssertEqual(details.route?.origin?.iata, "HGH")
        XCTAssertNil(details.route?.destination?.latitude)
        let empty = try DetailsDataClient.decodeDetails(Data(#"{"response":{"aircraft":null,"flightroute":null}}"#.utf8))
        XCTAssertNil(empty.aircraft)
        XCTAssertNil(empty.route)
    }

    func testRateLimitAppliesAcrossConcurrentCallsIncludingFailure() async throws {
        let stub = StubURLProtocol.state
        stub.reset { index, _ in
            (index == 0 ? 429 : 200, Data(#"{"now":1791121068001,"ac":[]}"#.utf8))
        }
        let client = FlightDataClient(session: stubSession())
        let queryCenter = center
        async let first = try? client.fetchNearby(center: queryCenter, radiusKilometers: 50)
        async let second = try? client.fetchNearby(center: queryCenter, radiusKilometers: 50)
        async let third = try? client.fetchNearby(center: queryCenter, radiusKilometers: 50)
        let snapshots = await [first, second, third]
        XCTAssertEqual(snapshots.compactMap { $0 }.count, 2)
        let starts = stub.requests.map(\.time)
        XCTAssertEqual(starts.count, 3)
        for pair in zip(starts, starts.dropFirst()) {
            XCTAssertGreaterThanOrEqual(pair.1.timeIntervalSince(pair.0), 0.95)
        }
    }

    func testUnknownAircraftFallsBackToCallsignAndCachesResult() async throws {
        StubURLProtocol.state.reset { _, request in
            if request.url!.path.contains("/aircraft/") { return (404, Data(#"{"response":"unknown aircraft"}"#.utf8)) }
            return (200, Data(#"{"response":{"flightroute":{"callsign_iata":"MF8062","airline":null,"origin":null,"destination":null}}}"#.utf8))
        }
        let client = DetailsDataClient(session: stubSession())
        let details = try await client.fetchDetails(hex: "abc123", callsign: " CXA8062 ")
        XCTAssertNil(details.aircraft)
        XCTAssertEqual(details.route?.callsignIATA, "MF8062")
        let cached = try await client.fetchDetails(hex: "ABC123", callsign: "CXA8062")
        XCTAssertEqual(details.fetchedAt, cached.fetchedAt)
        XCTAssertEqual(StubURLProtocol.state.requests.count, 2)
        XCTAssertEqual(StubURLProtocol.state.requests.first?.url?.query, "callsign=CXA8062")
    }

    func testUnknownDetailsAreNormalAndInvalidIdentifiersNeverRequest() async throws {
        StubURLProtocol.state.reset { _, _ in (404, Data()) }
        let client = DetailsDataClient(session: stubSession())
        let details = try await client.fetchDetails(hex: "abc123", callsign: nil)
        XCTAssertNil(details.aircraft)
        XCTAssertNil(details.route)
        do {
            _ = try await client.fetchDetails(hex: "abc123/../route", callsign: nil)
            XCTFail("Invalid identifier should fail")
        } catch {
            XCTAssertEqual(error as? FlightAPIError, .invalidAircraftIdentifier)
        }
        XCTAssertEqual(StubURLProtocol.state.requests.count, 1)
    }

    func testDemoDataIsClearlySyntheticAndWithin50Kilometers() {
        let snapshot = DemoData.snapshot(around: GeoCoordinate(latitude: 30.17284, longitude: 120.264387))
        XCTAssertEqual(snapshot.aircraft.count, 6)
        for aircraft in snapshot.aircraft {
            XCTAssertTrue(aircraft.callsign!.hasPrefix("DEMO"))
            XCTAssertTrue(aircraft.registration!.hasPrefix("DEMO"))
            XCTAssertLessThan(FlightGeometry.distanceKilometers(from: GeoCoordinate(latitude: 30.17284, longitude: 120.264387), to: aircraft.coordinate!), 50)
            XCTAssertTrue(DemoData.details(for: aircraft).route!.airlineName!.contains("虚构"))
        }
    }

    private func stubSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private final class StubState: @unchecked Sendable {
    struct RequestRecord: Sendable { let url: URL?; let time: Date }
    private let lock = NSLock()
    private var records: [RequestRecord] = []
    private var handler: @Sendable (Int, URLRequest) -> (Int, Data) = { _, _ in (200, Data()) }

    var requests: [RequestRecord] {
        lock.withLock { records }
    }

    func reset(handler: @escaping @Sendable (Int, URLRequest) -> (Int, Data)) {
        lock.withLock { records = []; self.handler = handler }
    }

    func respond(to request: URLRequest) -> (Int, Data) {
        lock.withLock {
            let index = records.count
            records.append(RequestRecord(url: request.url, time: Date()))
            return handler(index, request)
        }
    }
}

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    static let state = StubState()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, data) = Self.state.respond(to: request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Retry-After": "5"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
