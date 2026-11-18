import SwiftUI
import UIKit

struct FlightSettingsView: View {
    @ObservedObject var store: FlightStore
    @Environment(\.dismiss) private var dismiss
    @State private var longitude = ""
    @State private var latitude = ""
    @State private var inputError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("当前中心", value: store.centerMode == .device ? "设备位置" : "手动坐标")
                    Text(FlightDisplay.coordinate(store.center)).font(.subheadline.monospacedDigit())
                        .textSelection(.enabled)
                    Button("使用我的位置", systemImage: "location.fill") {
                        store.useDeviceLocation()
                        dismiss()
                    }
                    if let accuracy = store.locationAccuracyMeters {
                        LabeledContent("定位精度", value: "约 \(Int(accuracy)) 米")
                    }
                    if let message = store.locationMessage {
                        Text(message).font(.caption).foregroundStyle(.orange)
                    }
                } header: { Text("查询中心") } footer: {
                    Text("AR 仅使用设备的真实当前位置。手动坐标适用于远程地图查询。")
                }

                Section {
                    LabeledContent("经度") {
                        TextField("−180 至 180", text: $longitude)
                            .keyboardType(.numbersAndPunctuation)
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                            .accessibilityLabel("手动查询经度")
                    }
                    LabeledContent("纬度") {
                        TextField("−90 至 90", text: $latitude)
                            .keyboardType(.numbersAndPunctuation)
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                            .accessibilityLabel("手动查询纬度")
                    }
                    if let inputError { Text(inputError).font(.caption).foregroundStyle(.orange) }
                    Button("应用查询坐标", systemImage: "mappin.and.ellipse", action: applyManualCenter)
                } header: { Text("手动坐标 · WGS84") } footer: {
                    Text("顺序为经度、纬度。国内地图的 GCJ-02 或 BD-09 坐标需先转换为 WGS84。")
                }

                Section("跟踪设置") {
                    Picker("查询半径", selection: Binding(get: { store.radiusKilometers }, set: { store.setRadius($0) })) {
                        Text("20 公里").tag(20.0)
                        Text("50 公里").tag(50.0)
                        Text("100 公里").tag(100.0)
                    }
                    Toggle("自动刷新位置", isOn: Binding(get: { store.autoRefresh }, set: { store.setAutoRefresh($0) }))
                    Text("应用处于前台时，每 10 秒查询一次。")
                        .font(.caption).foregroundStyle(.secondary)
                    Toggle("演示模式", isOn: Binding(get: { store.isDemoMode }, set: { store.setDemoMode($0) }))
                    if store.isDemoMode {
                        Label("当前显示示例航班与资料，AR 暂停。", systemImage: "sparkles")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }

                Section {
                    Text("查询周边航班时，经纬度和查询半径会发送给 adsb.fi。选择飞机时，ICAO 地址与呼号会发送给 adsbdb 查询飞机和航线资料。")
                    Text("相机画面仅用于设备上的 AR 显示，应用不会上传相机图像。地图使用 Apple 地图服务。")
                    Link("打开系统权限设置", destination: URL(string: UIApplication.openSettingsURLString)!)
                } header: { Text("位置与相机隐私") }

                Section {
                    SourceCredits()
                    Link("adsb.fi 开放数据使用说明", destination: URL(string: "https://github.com/adsbfi/opendata")!)
                    Link("adsbdb 接口说明", destination: URL(string: "https://www.adsbdb.com/")!)
                    Text("航班位置依赖志愿者接收网络。部分区域可能没有覆盖；航线资料为呼号关联信息，不能用于确认实时起降或延误。")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("adsb.fi 公共接口用于个人非商业用途。商用或公开发行前，请确认适用的数据许可。")
                        .font(.caption).foregroundStyle(.secondary)
                } header: { Text("数据来源") }
            }
            .scrollContentBackground(.hidden)
            .background(SkyTheme.canvas)
            .navigationTitle("查询与设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
            .onAppear {
                longitude = String(format: "%.6f", store.center.longitude)
                latitude = String(format: "%.6f", store.center.latitude)
            }
        }
        .tint(SkyTheme.accent)
        .preferredColorScheme(.dark)
    }

    private func applyManualCenter() {
        guard let lat = Double(latitude.trimmingCharacters(in: .whitespacesAndNewlines)),
              let lon = Double(longitude.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            inputError = "请输入有效数字。"
            return
        }
        do {
            try store.setManualCenter(latitude: lat, longitude: lon)
            inputError = nil
            dismiss()
        } catch { inputError = error.localizedDescription }
    }
}
