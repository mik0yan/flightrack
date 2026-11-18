import Combine
import CoreLocation
import Foundation

enum CenterMode: String {
    case manual, device
}

enum CoordinateInputError: LocalizedError {
    case invalid
    var errorDescription: String? { "请输入有效坐标：纬度 −90 至 90，经度 −180 至 180。" }
}

@MainActor
final class FlightStore: ObservableObject {
    @Published private(set) var aircraft: [Aircraft] = []
    @Published var selectedAircraftID: String?
    @Published private(set) var snapshotDate: Date?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var radiusKilometers: Double = 50
    @Published private(set) var center = GeoCoordinate(latitude: 30.17284, longitude: 120.264387)
    @Published private(set) var centerMode: CenterMode = .manual
    @Published private(set) var isDemoMode = false
    @Published private(set) var autoRefresh = true
    @Published private(set) var details: AircraftDetails?
    @Published private(set) var isLoadingDetails = false
    @Published private(set) var detailsError: String?
    @Published var arStatus: ARTrackingStatus = .initializing
    @Published private(set) var headingDegrees: Double?
    @Published private(set) var observerAltitudeMeters: Double = 0
    @Published private(set) var locationMessage: String?
    @Published private(set) var locationAccuracyMeters: Double?
    @Published private(set) var hasCurrentLocation = false

    private let client = FlightDataClient()
    private let detailsClient = DetailsDataClient()
    private let location = LocationService()
    private var pollingTask: Task<Void, Never>?
    private var locationFreshnessTask: Task<Void, Never>?
    private var detailTask: Task<Void, Never>?
    private var contextVersion = 0
    private var pendingRefresh = false
    private var running = false
    private var lastLocationDate: Date?
    private var lastRequestedCenter: GeoCoordinate?
    private var detailsVersion = 0

    var selectedAircraft: Aircraft? {
        aircraft.first { $0.id == selectedAircraftID }
    }

    init() {
        location.onLocation = { [weak self] point in self?.acceptLocation(point) }
        location.onHeading = { [weak self] heading in self?.headingDegrees = heading }
        location.onMessage = { [weak self] message in self?.locationMessage = message }
    }

    func start() {
        guard !running else { return }
        running = true
        if centerMode == .device && !isDemoMode {
            lastLocationDate = nil
            location.start()
        }
        if details == nil, let selection = selectedAircraftID { selectAircraft(selection) }
        locationFreshnessTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.running else { break }
                self.updateLocationFreshness()
                do { try await Task.sleep(nanoseconds: 1_000_000_000) }
                catch { break }
            }
        }
        pollingTask = Task { [weak self] in
            var first = true
            while !Task.isCancelled {
                guard let self, self.running else { break }
                self.updateLocationFreshness()
                if first || self.autoRefresh { await self.refresh() }
                first = false
                do { try await Task.sleep(nanoseconds: 10_000_000_000) }
                catch { break }
            }
        }
    }

    func stop() {
        running = false
        contextVersion += 1
        pendingRefresh = false
        lastLocationDate = nil
        lastRequestedCenter = nil
        pollingTask?.cancel()
        pollingTask = nil
        locationFreshnessTask?.cancel()
        locationFreshnessTask = nil
        detailTask?.cancel()
        detailTask = nil
        detailsVersion += 1
        isLoadingDetails = false
        location.stop()
        hasCurrentLocation = false
    }

    func refresh() async {
        guard running else { return }
        guard !isLoading else { pendingRefresh = true; return }
        if centerMode == .device && !isDemoMode &&
            lastLocationDate.map({ abs($0.timeIntervalSinceNow) <= 30 }) != true {
            locationMessage = "正在等待设备当前位置…"
            return
        }
        let version = contextVersion
        let requestedCenter = center
        let requestedRadius = radiusKilometers
        let demo = isDemoMode
        #if DEBUG
        print("[SkyLens] Nearby request: source=\(demo ? "demo" : "adsb.fi"), radius=\(Int(requestedRadius))km")
        #endif
        lastRequestedCenter = requestedCenter
        let previousCallsign = selectedAircraft?.callsign
        isLoading = true
        defer {
            isLoading = false
            if pendingRefresh && running {
                pendingRefresh = false
                Task { [weak self] in await self?.refresh() }
            }
        }
        do {
            let snapshot: FlightSnapshot
            if demo {
                snapshot = DemoData.snapshot(around: requestedCenter)
            } else {
                snapshot = try await client.fetchNearby(center: requestedCenter, radiusKilometers: requestedRadius)
            }
            try Task.checkCancellation()
            guard version == contextVersion else { return }
            aircraft = snapshot.aircraft.filter { flight in
                guard let coordinate = flight.coordinate else { return false }
                return FlightGeometry.distanceKilometers(from: requestedCenter, to: coordinate) <= requestedRadius
            }.sorted { first, second in
                FlightGeometry.distanceKilometers(from: requestedCenter, to: first.coordinate!) <
                    FlightGeometry.distanceKilometers(from: requestedCenter, to: second.coordinate!)
            }
            snapshotDate = snapshot.capturedAt
            errorMessage = nil
            #if DEBUG
            print("[SkyLens] Nearby result: \(aircraft.count) aircraft, snapshot=\(snapshot.capturedAt.ISO8601Format())")
            #endif
            if let selection = selectedAircraftID, !aircraft.contains(where: { $0.id == selection }) {
                clearSelection()
            } else if let selection = selectedAircraftID, previousCallsign != selectedAircraft?.callsign {
                selectAircraft(selection)
            }
        } catch is CancellationError {
            // A background transition or superseded query is not a service failure.
        } catch {
            guard version == contextVersion else { return }
            errorMessage = aircraft.isEmpty ? error.localizedDescription : "刷新失败，当前显示上次的数据。\(error.localizedDescription)"
            #if DEBUG
            print("[SkyLens] Nearby error: \(error.localizedDescription)")
            #endif
        }
    }

    func selectAircraft(_ id: String) {
        guard let flight = aircraft.first(where: { $0.id == id }) else { return }
        let callsign = flight.callsign
        detailsVersion += 1
        let requestVersion = detailsVersion
        selectedAircraftID = id
        details = nil
        detailsError = nil
        detailTask?.cancel()
        if isDemoMode {
            details = DemoData.details(for: flight)
            isLoadingDetails = false
            return
        }
        isLoadingDetails = true
        detailTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.detailsClient.fetchDetails(hex: flight.hex, callsign: callsign)
                try Task.checkCancellation()
                guard self.detailsVersion == requestVersion,
                      self.selectedAircraftID == id, self.selectedAircraft?.callsign == callsign, !self.isDemoMode else { return }
                self.details = result
                self.isLoadingDetails = false
                #if DEBUG
                print("[SkyLens] Details result: aircraft=\(result.aircraft != nil), route=\(result.route != nil)")
                #endif
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled, self.detailsVersion == requestVersion, self.selectedAircraftID == id else { return }
                self.detailsError = "补充资料查询失败。\(error.localizedDescription)"
                self.isLoadingDetails = false
            }
        }
    }

    func setRadius(_ radius: Double) {
        guard [20.0, 50.0, 100.0].contains(radius), radius != radiusKilometers else { return }
        radiusKilometers = radius
        invalidateContext()
        Task { await refresh() }
    }

    func setDemoMode(_ enabled: Bool) {
        guard enabled != isDemoMode else { return }
        isDemoMode = enabled
        invalidateContext()
        if enabled {
            location.stop()
            hasCurrentLocation = false
        } else if centerMode == .device {
            lastLocationDate = nil
            location.start()
        }
        Task { await refresh() }
    }

    func setManualCenter(latitude: Double, longitude: Double) throws {
        guard latitude.isFinite, longitude.isFinite,
              (-90...90).contains(latitude), (-180...180).contains(longitude) else {
            throw CoordinateInputError.invalid
        }
        centerMode = .manual
        center = GeoCoordinate(latitude: latitude, longitude: longitude)
        observerAltitudeMeters = 0
        hasCurrentLocation = false
        locationAccuracyMeters = nil
        locationMessage = nil
        location.stop()
        invalidateContext()
        Task { await refresh() }
    }

    func useDeviceLocation() {
        centerMode = .device
        lastLocationDate = nil
        hasCurrentLocation = false
        invalidateContext()
        if isDemoMode { isDemoMode = false }
        location.start()
    }

    func setAutoRefresh(_ enabled: Bool) {
        autoRefresh = enabled
        if enabled { Task { await refresh() } }
    }

    private func acceptLocation(_ point: CLLocation) {
        guard centerMode == .device && !isDemoMode else { return }
        let next = GeoCoordinate(latitude: point.coordinate.latitude, longitude: point.coordinate.longitude)
        let moved = FlightGeometry.distanceKilometers(from: lastRequestedCenter ?? center, to: next)
        let first = lastLocationDate == nil
        center = next
        lastLocationDate = point.timestamp
        locationAccuracyMeters = point.horizontalAccuracy
        hasCurrentLocation = point.horizontalAccuracy <= 100
        observerAltitudeMeters = point.verticalAccuracy >= 0 ? point.altitude : 0
        if first || moved > 0.2 {
            contextVersion += 1
            Task { await refresh() }
        }
    }

    private func updateLocationFreshness() {
        if centerMode == .device, !isDemoMode {
            hasCurrentLocation = lastLocationDate.map { abs($0.timeIntervalSinceNow) <= 30 } == true &&
                (locationAccuracyMeters.map { $0 <= 100 } == true)
            if !hasCurrentLocation && lastLocationDate != nil {
                locationMessage = "当前位置已过期或精度不足，等待更新后恢复 AR。"
            }
        }
    }

    private func invalidateContext() {
        contextVersion += 1
        aircraft = []
        snapshotDate = nil
        errorMessage = nil
        clearSelection()
    }

    private func clearSelection() {
        detailsVersion += 1
        detailTask?.cancel()
        detailTask = nil
        selectedAircraftID = nil
        details = nil
        detailsError = nil
        isLoadingDetails = false
    }
}
