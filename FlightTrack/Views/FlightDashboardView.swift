import SwiftUI

struct FlightDashboardView: View {
    @ObservedObject var store: FlightStore
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var compactColumn: NavigationSplitViewColumn = .detail
    @State private var displayMode: DisplayMode = .map
    @State private var search = ""
    @State private var airborneOnly = true
    @State private var showsSettings = false
    @State private var showsDetails = false

    private enum DisplayMode: String, CaseIterable, Identifiable {
        case map = "地图", ar = "AR 视野"
        var id: String { rawValue }
    }

    private var filteredAircraft: [Aircraft] {
        store.aircraft.filter { aircraft in
            (!airborneOnly || !aircraft.isOnGround) &&
            (search.isEmpty || [aircraft.callsign, aircraft.registration, aircraft.typeCode, aircraft.hex]
                .compactMap { $0 }
                .contains { $0.localizedCaseInsensitiveContains(search) })
        }.sorted { lhs, rhs in
            guard let left = lhs.coordinate else { return false }
            guard let right = rhs.coordinate else { return true }
            return FlightGeometry.distanceKilometers(from: store.center, to: left)
                < FlightGeometry.distanceKilometers(from: store.center, to: right)
        }
    }

    private var isARReady: Bool {
        !store.isDemoMode && store.centerMode == .device && store.hasCurrentLocation
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility, preferredCompactColumn: $compactColumn) {
            sidebar
                .navigationSplitViewColumnWidth(min: 285, ideal: 330, max: 390)
        } detail: {
            NavigationStack {
                workspace
                    .navigationTitle("周边视野")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItemGroup(placement: .topBarTrailing) {
                            Button {
                                Task { await store.refresh() }
                            } label: {
                                if store.isLoading { ProgressView() }
                                else { Image(systemName: "arrow.clockwise") }
                            }
                            .disabled(store.isLoading)
                            .accessibilityLabel("刷新航班位置")
                            Button { showsSettings = true } label: {
                                Image(systemName: "slider.horizontal.3")
                            }
                            .accessibilityLabel("查询与隐私设置")
                        }
                    }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .tint(SkyTheme.accent)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showsSettings) {
            FlightSettingsView(store: store)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showsDetails) {
            FlightDetailView(store: store)
                .presentationDetents([.large])
        }
    }

    private var sidebar: some View {
        GeometryReader { geometry in
            if verticalSizeClass == .compact || geometry.size.height < 540 {
                // A single scroll surface keeps rows and errors reachable when the
                // navigation/search bars leave little height on a landscape phone.
                ScrollView {
                    VStack(spacing: 0) {
                        sidebarHeader(compact: true)
                        Rectangle().fill(SkyTheme.line).frame(height: 1)
                        if filteredAircraft.isEmpty {
                            sidebarEmptyContent
                        } else {
                            LazyVStack(spacing: 10) {
                                ForEach(filteredAircraft) { aircraft in
                                    sidebarAircraftRow(aircraft)
                                }
                            }
                            .padding(12)
                        }
                        sidebarFooter(compact: true)
                    }
                    .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
                .accessibilityIdentifier("flight-sidebar-scroll")
            } else {
                VStack(spacing: 0) {
                    sidebarHeader(compact: false)
                    Rectangle().fill(SkyTheme.line).frame(height: 1)
                    if filteredAircraft.isEmpty {
                        ScrollView { sidebarEmptyContent }
                            .frame(maxHeight: .infinity)
                    } else {
                        List(filteredAircraft) { aircraft in
                            sidebarAircraftRow(aircraft)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 5, leading: 12, bottom: 5, trailing: 12))
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                    }
                    sidebarFooter(compact: false)
                }
            }
        }
        .background(SkyTheme.panel)
        .navigationTitle("航班")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "呼号、注册号或机型")
    }

    private func sidebarHeader(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 20) {
            if !compact {
                HStack(spacing: 10) {
                    Image(systemName: "viewfinder")
                        .font(.title2.weight(.medium))
                        .foregroundStyle(SkyTheme.accent)
                        .frame(width: 42, height: 42)
                        .background(SkyTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("SkyLens").font(.title2.weight(.bold))
                        Text("天际 · 看见头顶的航班")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("周边航班").font(.headline)
                if !compact { Spacer() }
                Text("\(filteredAircraft.count)")
                    .font(compact ? .headline.monospacedDigit() : .title2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(SkyTheme.accent)
                Text("架").font(.caption).foregroundStyle(.secondary)
                if compact {
                    Spacer(minLength: 4)
                    Text("\(Int(store.radiusKilometers)) km")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            if !compact {
                HStack {
                    Label("\(Int(store.radiusKilometers)) km", systemImage: "dot.scope")
                    Spacer()
                    if store.isDemoMode {
                        SkyBadge(text: "演示数据", color: .orange, symbol: "sparkles")
                    } else {
                        SkyBadge(text: store.autoRefresh ? "自动刷新" : "手动刷新", symbol: "antenna.radiowaves.left.and.right")
                    }
                }
                .font(.subheadline)
            } else if store.isDemoMode {
                SkyBadge(text: "演示数据", color: .orange, symbol: "sparkles")
            }
            Toggle("隐藏地面飞机", isOn: $airborneOnly)
                .font(.subheadline)
                .tint(SkyTheme.accent)
        }
        .padding(compact ? 12 : 20)
    }

    private var sidebarEmptyContent: some View {
        VStack(spacing: 8) {
            sidebarEmptyState
            if search.isEmpty && !store.isLoading {
                Button("刷新数据", systemImage: "arrow.clockwise") {
                    Task { await store.refresh() }
                }
                .buttonStyle(.bordered)
                if !store.isDemoMode {
                    Button("体验演示航班", systemImage: "sparkles") {
                        store.setDemoMode(true)
                    }
                    .font(.subheadline)
                    .padding(.top, 4)
                }
            }
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
    }

    private func sidebarAircraftRow(_ aircraft: Aircraft) -> some View {
        AircraftRow(aircraft: aircraft, center: store.center,
                    isSelected: store.selectedAircraftID == aircraft.id,
                    isDemo: store.isDemoMode, snapshotDate: store.snapshotDate) {
            store.selectAircraft(aircraft.id)
            compactColumn = .detail
        } onDetails: {
            store.selectAircraft(aircraft.id)
            showsDetails = true
        }
    }

    private func sidebarFooter(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 5 : 8) {
            Label(store.centerMode == .device ? "设备所在位置" : "手动查询中心",
                  systemImage: store.centerMode == .device ? "location.fill" : "mappin.and.ellipse")
                .font(.caption.weight(.medium))
            Text(FlightDisplay.coordinate(store.center))
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                .textSelection(.enabled)
            if let date = store.snapshotDate {
                HStack(spacing: 4) {
                    Text(store.isDemoMode ? "演示快照" : "数据快照")
                    Text(date, style: .time).monospacedDigit()
                }.font(.caption).foregroundStyle(.secondary)
            }
            SourceCredits(compact: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(compact ? 12 : 20)
        .background(SkyTheme.canvas)
    }

    @ViewBuilder private var sidebarEmptyState: some View {
        if store.isLoading && store.aircraft.isEmpty {
            VStack(spacing: 16) {
                ProgressView().controlSize(.large)
                Text("正在查询附近飞机…").font(.subheadline).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity).padding(32)
        } else if !search.isEmpty || (!store.aircraft.isEmpty && airborneOnly) {
            SkyEmptyState(symbol: "line.3.horizontal.decrease.circle", title: "没有匹配的飞机",
                          message: "调整搜索关键词，或关闭地面飞机筛选。")
        } else if let error = store.errorMessage {
            SkyEmptyState(symbol: "wifi.exclamationmark", title: "暂时无法获取位置", message: error)
        } else {
            SkyEmptyState(symbol: "airplane.circle", title: "暂未收到飞机信号",
                          message: "adsb.fi 本次未捕获此范围内的飞机。接收覆盖可能不完整。")
        }
    }

    private var workspace: some View {
        VStack(spacing: 0) {
            workspaceControls
            ZStack(alignment: .topLeading) {
                if displayMode == .map {
                    FlightMapView(aircraft: store.aircraft, center: store.center,
                                  radiusKilometers: store.radiusKilometers,
                                  selectedAircraftID: store.selectedAircraftID,
                                  showsUserLocation: store.centerMode == .device && store.hasCurrentLocation,
                                  snapshotDate: store.snapshotDate, isDemo: store.isDemoMode) {
                        store.selectAircraft($0)
                    }
                } else if isARReady {
                    ARFlightView(aircraft: store.aircraft, observer: store.center,
                                 observerAltitudeMeters: store.observerAltitudeMeters,
                                 snapshotDate: store.snapshotDate ?? Date(),
                                 selectedAircraftID: store.selectedAircraftID,
                                 onSelect: {
                                     store.selectAircraft($0)
                                     showsDetails = true
                                 }, onStatus: { store.arStatus = $0 })
                } else {
                    arPreparation
                }

                VStack(alignment: .leading, spacing: 8) {
                    if store.isDemoMode {
                        SkyBadge(text: "演示数据 · 非真实航班位置", color: .orange, symbol: "sparkles")
                    }
                    if let error = store.errorMessage, !store.aircraft.isEmpty {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .padding(12)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                    if displayMode == .map {
                        VStack(alignment: .leading, spacing: 5) {
                            Label(store.centerMode == .device ? "当前位置" : "查询中心", systemImage: "dot.scope")
                                .font(.caption.weight(.semibold))
                            Text("周围 \(Int(store.radiusKilometers)) 公里")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    } else if isARReady {
                        SkyBadge(text: store.arStatus.title,
                                 color: store.arStatus.isNormal ? SkyTheme.accent : .orange,
                                 symbol: "viewfinder")
                    }
                }
                .padding(16)
                .allowsHitTesting(false)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let aircraft = store.selectedAircraft {
                    SelectedAircraftCard(aircraft: aircraft, center: store.center,
                                         isDemo: store.isDemoMode, snapshotDate: store.snapshotDate) {
                        showsDetails = true
                    }
                    .padding(12)
                }
            }
        }
        .background(SkyTheme.canvas)
    }

    private var workspaceControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 20) {
                modePicker.frame(maxWidth: 240)
                Spacer(minLength: 8)
                radiusPicker
                locationButton
            }
            VStack(spacing: 12) {
                modePicker
                HStack { radiusPicker; Spacer(); locationButton }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(SkyTheme.canvas)
    }

    private var modePicker: some View {
        Picker("查看方式", selection: $displayMode) {
            ForEach(DisplayMode.allCases) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("地图或 AR 视野")
    }

    private var radiusPicker: some View {
        Menu {
            ForEach([20.0, 50.0, 100.0], id: \.self) { radius in
                Button {
                    store.setRadius(radius)
                } label: {
                    if radius == store.radiusKilometers {
                        Label("\(Int(radius)) 公里", systemImage: "checkmark")
                    } else { Text("\(Int(radius)) 公里") }
                }
            }
        } label: {
            Label("\(Int(store.radiusKilometers)) km", systemImage: "dot.scope")
                .font(.subheadline.weight(.medium))
                .frame(minHeight: 44)
        }
        .accessibilityLabel("查询半径 \(Int(store.radiusKilometers)) 公里")
    }

    private var locationButton: some View {
        Button {
            store.useDeviceLocation()
        } label: {
            Label("我的位置", systemImage: "location")
                .font(.subheadline.weight(.medium))
                .frame(minHeight: 44)
        }
        .accessibilityHint("使用设备当前位置查询周围飞机")
    }

    private var arPreparation: some View {
        GeometryReader { geometry in
            let compact = verticalSizeClass == .compact || geometry.size.height < 560
            ScrollView {
                VStack(spacing: compact ? 12 : 24) {
                    ZStack {
                        Circle().stroke(SkyTheme.accent.opacity(0.15), lineWidth: 1)
                            .frame(width: compact ? 80 : 210, height: compact ? 80 : 210)
                        Circle().stroke(SkyTheme.accent.opacity(0.3), lineWidth: 1)
                            .frame(width: compact ? 56 : 150, height: compact ? 56 : 150)
                        Image(systemName: "viewfinder")
                            .font(.system(size: compact ? 28 : 60, weight: .ultraLight))
                            .foregroundStyle(SkyTheme.accent)
                    }.accessibilityHidden(true)
                    VStack(spacing: 10) {
                        Text("让天空成为你的航班地图")
                            .font(.title2.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(store.isDemoMode
                             ? "演示航班可以在地图中查看。切回实时数据并获取当前位置，即可启用 AR。"
                             : "AR 需要设备当前位置、相机和方位信息。请在室外开阔处使用，移动 iPad 校准方向。")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: 440)
                        if let message = store.locationMessage {
                            Text(message).font(.caption).foregroundStyle(.orange)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Button {
                        if store.isDemoMode { store.setDemoMode(false) }
                        store.useDeviceLocation()
                    } label: {
                        Label("启用当前位置与 AR", systemImage: "location.fill")
                            .font(.headline)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                    }
                    .buttonStyle(.borderedProminent)
                    .foregroundStyle(SkyTheme.canvas)
                    Text("AR 标记依据接收位置估算，存在数据延迟和方向误差。")
                        .font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 440)
                }
                .padding(compact ? 18 : 30)
                .frame(maxWidth: .infinity)
                .frame(minHeight: geometry.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
            .accessibilityIdentifier("ar-preparation-scroll")
        }
        .background(SkyTheme.canvas.gradient)
    }
}

private struct AircraftRow: View {
    let aircraft: Aircraft
    let center: GeoCoordinate
    let isSelected: Bool
    let isDemo: Bool
    let snapshotDate: Date?
    let onSelect: () -> Void
    let onDetails: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onSelect) {
                HStack(spacing: 12) {
                    Image(systemName: "airplane")
                        .font(.title3)
                        .foregroundStyle(isSelected ? SkyTheme.canvas : SkyTheme.accent)
                        .frame(width: 40, height: 40)
                        .background(isSelected ? SkyTheme.accent : SkyTheme.accent.opacity(0.1), in: Circle())
                    VStack(alignment: .leading, spacing: 5) {
                        Text(FlightDisplay.callsign(aircraft)).font(.headline).foregroundStyle(.primary)
                        Text([aircraft.typeCode, aircraft.registration].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            Text(FlightDisplay.distance(aircraft, from: center))
                            Text("·")
                            Text(FlightDisplay.altitude(aircraft))
                        }.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        FlightPositionAgeLabel(aircraft: aircraft, snapshotDate: snapshotDate, isDemo: isDemo)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(isDemo ? "演示航班，" : "")\(FlightDisplay.callsign(aircraft))，距离 \(FlightDisplay.distance(aircraft, from: center))，高度 \(FlightDisplay.altitude(aircraft))")
            .accessibilityHint("在地图中选中此飞机")
            Button(action: onDetails) {
                Image(systemName: "info.circle")
                    .font(.title3)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("查看 \(FlightDisplay.callsign(aircraft)) 的航班和飞机详情")
        }
        .padding(12)
        .background(isSelected ? SkyTheme.accent.opacity(0.09) : Color.white.opacity(0.025),
                    in: RoundedRectangle(cornerRadius: 15))
        .overlay {
            RoundedRectangle(cornerRadius: 15)
                .stroke(isSelected ? SkyTheme.accent.opacity(0.45) : SkyTheme.line, lineWidth: 1)
        }
    }
}

private struct SelectedAircraftCard: View {
    let aircraft: Aircraft
    let center: GeoCoordinate
    let isDemo: Bool
    let snapshotDate: Date?
    let onDetails: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "airplane").font(.title2).foregroundStyle(SkyTheme.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text(FlightDisplay.callsign(aircraft)).font(.title3.weight(.bold))
                    Text([aircraft.registration, aircraft.typeCode].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if isDemo { SkyBadge(text: "演示", color: .orange) }
                Button(action: onDetails) {
                    Label("详情", systemImage: "arrow.up.right")
                }.buttonStyle(.bordered)
            }
            HStack(spacing: 0) {
                metric("距离", value: FlightDisplay.distance(aircraft, from: center))
                metric("高度", value: FlightDisplay.altitude(aircraft))
                metric("地速", value: FlightDisplay.speed(aircraft))
            }
            FlightPositionAgeLabel(aircraft: aircraft, snapshotDate: snapshotDate, isDemo: isDemo)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(SkyTheme.line, lineWidth: 1))
        .frame(maxWidth: 650)
        .frame(maxWidth: .infinity)
    }

    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.semibold).monospacedDigit())
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
