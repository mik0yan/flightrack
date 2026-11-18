import SwiftUI
import MapKit

struct FlightMapView: View {
    let aircraft: [Aircraft]
    let center: GeoCoordinate
    let radiusKilometers: Double
    let selectedAircraftID: String?
    let showsUserLocation: Bool
    let snapshotDate: Date?
    let isDemo: Bool
    let onSelect: (String) -> Void
    @State private var camera: MapCameraPosition = .automatic

    private var mapCenter: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude)
    }

    var body: some View {
        Map(position: $camera) {
            MapCircle(center: mapCenter, radius: radiusKilometers * 1_000)
                .foregroundStyle(SkyTheme.accent.opacity(0.035))
                .stroke(SkyTheme.accent.opacity(0.32), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))

            Annotation("查询中心", coordinate: mapCenter, anchor: .center) {
                ZStack {
                    Circle().fill(SkyTheme.accent.opacity(0.2)).frame(width: 35, height: 35)
                    Circle().fill(SkyTheme.accent).frame(width: 11, height: 11)
                    Circle().stroke(.white.opacity(0.9), lineWidth: 2).frame(width: 11, height: 11)
                }.accessibilityLabel("航班查询中心")
            }

            if showsUserLocation { UserAnnotation() }

            ForEach(aircraft) { aircraft in
                if let coordinate = aircraft.coordinate {
                    Annotation(FlightDisplay.callsign(aircraft),
                               coordinate: CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude),
                               anchor: .center) {
                        TimelineView(.periodic(from: .now, by: 5)) { timeline in
                            let age = FlightDisplay.effectiveAgeSeconds(aircraft, snapshotDate: snapshotDate, now: timeline.date)
                            let markerColor = isDemo ? Color.orange : ((age.map { $0 > 60 } ?? true) ? .gray : SkyTheme.accent)
                            Button { onSelect(aircraft.id) } label: {
                                VStack(spacing: 5) {
                                    Image(systemName: "airplane")
                                        .font(.system(size: selectedAircraftID == aircraft.id ? 26 : 21, weight: .semibold))
                                        .rotationEffect(.degrees((aircraft.trackDegrees ?? 0) - 90))
                                        .foregroundStyle(selectedAircraftID == aircraft.id ? SkyTheme.canvas : markerColor)
                                        .frame(width: 46, height: 46)
                                        .background(selectedAircraftID == aircraft.id ? markerColor : SkyTheme.panel.opacity(0.95), in: Circle())
                                        .overlay(Circle().stroke(markerColor.opacity(0.45), lineWidth: 1))
                                        .shadow(color: .black.opacity(0.25), radius: 5, y: 3)
                                    if selectedAircraftID == aircraft.id {
                                        Text(FlightDisplay.callsign(aircraft))
                                            .font(.caption.weight(.bold))
                                            .padding(.horizontal, 8).padding(.vertical, 4)
                                            .background(SkyTheme.panel, in: Capsule())
                                            .foregroundStyle(.white)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(isDemo ? "演示" : "")飞机 \(FlightDisplay.callsign(aircraft))，高度 \(FlightDisplay.altitude(aircraft))")
                            .accessibilityHint("选中飞机并显示位置详情")
                        }
                    }
                    .annotationTitles(.hidden)
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .onAppear(perform: centerMap)
        .onChange(of: center.latitude) { _, _ in centerMap() }
        .onChange(of: center.longitude) { _, _ in centerMap() }
        .onChange(of: radiusKilometers) { _, _ in centerMap() }
        .overlay(alignment: .bottomTrailing) {
            Button(action: centerMap) {
                Image(systemName: "scope")
                    .font(.title3)
                    .frame(width: 46, height: 46)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
            .padding(14)
            .accessibilityLabel("将地图移回查询范围")
        }
    }

    private func centerMap() {
        let span = radiusKilometers * 2_700
        camera = .region(MKCoordinateRegion(center: mapCenter, latitudinalMeters: span, longitudinalMeters: span))
    }
}
