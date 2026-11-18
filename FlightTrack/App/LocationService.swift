import CoreLocation
import Foundation

@MainActor
final class LocationService: NSObject, @preconcurrency CLLocationManagerDelegate {
    var onLocation: ((CLLocation) -> Void)?
    var onHeading: ((Double?) -> Void)?
    var onMessage: ((String?) -> Void)?

    private let manager = CLLocationManager()
    private var wantsUpdates = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 20
        manager.headingFilter = 2
    }

    func start() {
        wantsUpdates = true
        guard CLLocationManager.locationServicesEnabled() else {
            onMessage?("系统定位服务未开启，请在设置中开启定位服务。")
            return
        }
        switch manager.authorizationStatus {
        case .notDetermined:
            onMessage?("请允许使用当前位置，以查询附近飞机并对齐 AR 方位。")
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            onMessage?("正在获取设备位置…")
            manager.startUpdatingLocation()
            if CLLocationManager.headingAvailable() {
                manager.startUpdatingHeading()
            }
        case .denied, .restricted:
            onMessage?("定位权限未开启。可手动查询坐标；AR 需要在系统设置中允许定位。")
        @unknown default:
            onMessage?("定位暂不可用，可先手动查询坐标。")
        }
    }

    func stop() {
        wantsUpdates = false
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard wantsUpdates else { return }
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            start()
        } else if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
            onMessage?("定位权限未开启。可手动查询坐标；AR 需要在系统设置中允许定位。")
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard wantsUpdates, let location = locations.last,
              location.horizontalAccuracy >= 0,
              abs(location.timestamp.timeIntervalSinceNow) < 30 else { return }
        onLocation?(location)
        if location.horizontalAccuracy > 100 {
            onMessage?("定位精度较低，正在等待更准确的位置。AR 方位可能有偏差。")
        } else if location.verticalAccuracy < 0 {
            onMessage?("当前位置可用；设备海拔暂不可用，AR 仰角为近似值。")
        } else {
            onMessage?(nil)
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading heading: CLHeading) {
        guard wantsUpdates else { return }
        onHeading?(heading.headingAccuracy >= 0 && heading.trueHeading >= 0 ? heading.trueHeading : nil)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard wantsUpdates else { return }
        if let error = error as? CLError, error.code == .locationUnknown {
            onMessage?("暂时无法确定位置，正在重试…")
        } else {
            onMessage?("获取位置失败：\(error.localizedDescription)")
        }
    }

    func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool { true }
}
