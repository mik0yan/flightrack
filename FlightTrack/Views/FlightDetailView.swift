import SwiftUI

struct FlightDetailView: View {
    @ObservedObject var store: FlightStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                if let aircraft = store.selectedAircraft {
                    VStack(alignment: .leading, spacing: 22) {
                        header(aircraft)
                        liveObservation(aircraft)
                        routeSection
                        aircraftSection(aircraft)
                        sourceSection
                    }
                    .frame(maxWidth: 760)
                    .padding(24)
                    .frame(maxWidth: .infinity)
                } else {
                    SkyEmptyState(symbol: "airplane.circle", title: "飞机已离开查询范围",
                                  message: "关闭详情后，可在地图中选择另一架飞机。")
                        .padding(.top, 80)
                }
            }
            .background(SkyTheme.canvas)
            .navigationTitle("航班与飞机")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } }
            }
        }
        .tint(SkyTheme.accent)
        .preferredColorScheme(.dark)
    }

    private func header(_ aircraft: Aircraft) -> some View {
        HStack(alignment: .top, spacing: 18) {
            Image(systemName: "airplane")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(SkyTheme.accent)
                .frame(width: 76, height: 76)
                .background(SkyTheme.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 22))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 7) {
                Text(FlightDisplay.callsign(aircraft)).font(.largeTitle.weight(.bold))
                    .textSelection(.enabled)
                Text(aircraft.registration ?? "注册号未提供")
                    .font(.subheadline).foregroundStyle(.secondary)
                if store.isDemoMode {
                    SkyBadge(text: "演示航班与演示资料", color: .orange, symbol: "sparkles")
                } else {
                    SkyBadge(text: "ADS-B 接收记录", symbol: "antenna.radiowaves.left.and.right")
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func liveObservation(_ aircraft: Aircraft) -> some View {
        detailCard {
            sectionTitle("位置与飞行状态", symbol: "location.north.line")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 18)], alignment: .leading, spacing: 22) {
                metric("距查询中心", value: FlightDisplay.distance(aircraft, from: store.center))
                metric("状态", value: aircraft.isOnGround ? "地面" : (aircraft.altitudeMeters != nil ? "空中" : "未知"))
                metric("气压高度", value: meters(aircraft.barometricAltitudeFeet))
                metric("几何高度", value: meters(aircraft.geometricAltitudeFeet))
                metric("地速", value: FlightDisplay.speed(aircraft))
                metric("航迹角", value: degrees(aircraft.trackDegrees))
                metric("垂直速度", value: verticalSpeed(aircraft.verticalRateFeetPerMinute))
                metric("机型代码", value: aircraft.typeCode ?? "未提供")
            }
            Divider().overlay(SkyTheme.line)
            if let coordinate = aircraft.coordinate {
                Label(FlightDisplay.coordinate(coordinate), systemImage: "mappin.and.ellipse")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            FlightPositionAgeLabel(aircraft: aircraft, snapshotDate: store.snapshotDate, isDemo: store.isDemoMode)
            if let date = store.snapshotDate {
                HStack(spacing: 5) {
                    Text(store.isDemoMode ? "演示快照" : "接口快照")
                    Text(date.formatted(date: .abbreviated, time: .standard))
                }.font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var routeSection: some View {
        detailCard {
            sectionTitle("航班信息", symbol: "point.topleft.down.to.point.bottomright.curvepath")
            if store.isLoadingDetails {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("正在查询航班与飞机资料…").font(.subheadline).foregroundStyle(.secondary)
                }.padding(.vertical, 8)
            } else if let route = store.details?.route {
                HStack(alignment: .firstTextBaseline) {
                    Text(route.callsignIATA ?? store.selectedAircraft?.callsign ?? "航班号未提供")
                        .font(.title2.weight(.semibold))
                    Spacer()
                    Text(route.airlineName ?? "航空公司未提供")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                HStack(alignment: .top, spacing: 12) {
                    airport(route.origin, role: "出发机场")
                    Image(systemName: "airplane").foregroundStyle(SkyTheme.accent).padding(.top, 27)
                    airport(route.destination, role: "目的机场")
                }.padding(.vertical, 8)
                Text(store.isDemoMode
                     ? "这是用于演示详情界面的示例航线。"
                     : "根据呼号关联的航线资料，来自 adsbdb。航线可能与当前飞行不一致；此数据源不提供实时起降时间或延误状态。")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("暂未找到此呼号关联的航线资料。")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text("飞机仍可根据 ADS-B 位置跟踪；起降机场和航班时刻保持未知。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let error = store.detailsError {
                Text(error).font(.caption).foregroundStyle(.orange)
                if let aircraft = store.selectedAircraft {
                    Button("重试补充资料", systemImage: "arrow.clockwise") {
                        store.selectAircraft(aircraft.id)
                    }.font(.subheadline)
                }
            }
        }
    }

    private func aircraftSection(_ aircraft: Aircraft) -> some View {
        detailCard {
            sectionTitle("飞机资料", symbol: "airplane.circle")
            dataRow("注册号", value: store.details?.aircraft?.registration ?? aircraft.registration)
            dataRow("ICAO 24 位地址", value: aircraft.hex.uppercased())
            dataRow("制造商", value: store.details?.aircraft?.manufacturer)
            dataRow("飞机型号", value: store.details?.aircraft?.typeName ?? aircraft.typeCode)
            dataRow("注册所有者", value: store.details?.aircraft?.owner)
            dataRow("注册国家 / 地区", value: store.details?.aircraft?.ownerCountry)
            if let photo = store.details?.aircraft?.photoURL {
                Link(destination: photo) {
                    Label("查看数据源飞机照片", systemImage: "photo")
                }.font(.subheadline).padding(.top, 4)
            }
            if !store.isDemoMode {
                Text("补充资料来自 adsbdb；未提供的字段显示为未知。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SourceCredits()
            Text(store.isDemoMode ? "当前所有航班、航线与飞机资料均为演示内容。"
                 : "位置来自志愿者接收网络，覆盖可能不完整。AR 与地图位置受接收延迟、定位精度和方位误差影响。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func detailCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16, content: content)
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SkyTheme.panel, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(SkyTheme.line, lineWidth: 1))
    }

    private func sectionTitle(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol).font(.headline).foregroundStyle(SkyTheme.accent)
    }

    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold).monospacedDigit())
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func dataRow(_ title: String, value: String?) -> some View {
        HStack(alignment: .top, spacing: 18) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value ?? "未知")
                .font(.subheadline.weight(.medium))
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }

    private func airport(_ info: AirportInfo?, role: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(role).font(.caption).foregroundStyle(.secondary)
            Text(info?.iata ?? info?.icao ?? "—").font(.largeTitle.weight(.light))
            Text(info?.name ?? "机场未知").font(.subheadline.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
            if let city = info?.city { Text(city).font(.caption).foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func meters(_ feet: Double?) -> String {
        guard let feet else { return "未知" }
        return (feet * 0.3048).formatted(.number.precision(.fractionLength(0))) + " m"
    }
    private func degrees(_ degrees: Double?) -> String {
        guard let degrees else { return "未知" }
        return degrees.formatted(.number.precision(.fractionLength(0))) + "°"
    }
    private func verticalSpeed(_ feet: Double?) -> String {
        guard let feet else { return "未知" }
        return (feet * 0.3048 / 60).formatted(.number.precision(.fractionLength(1))) + " m/s"
    }
}
