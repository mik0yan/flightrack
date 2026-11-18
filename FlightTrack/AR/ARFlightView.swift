import ARKit
import AVFoundation
import RealityKit
import SwiftUI
import UIKit
import simd

enum ARTrackingStatus: Equatable {
    case unavailable(String)
    case initializing
    case normal
    case limited(String)
    case interrupted
    case failed(String)

    var title: String {
        switch self {
        case .unavailable(let reason), .limited(let reason), .failed(let reason):
            return reason
        case .initializing:
            return "正在校准相机与方向"
        case .normal:
            return "AR 跟踪正常"
        case .interrupted:
            return "AR 跟踪暂时中断"
        }
    }

    var isNormal: Bool {
        if case .normal = self { return true }
        return false
    }
}

/// Places aircraft bearings over the camera feed. Labels show reported positions;
/// they are not optical detections and are never filled from demonstration data.
struct ARFlightView: UIViewRepresentable {
    var aircraft: [Aircraft]
    var observer: GeoCoordinate
    var observerAltitudeMeters: Double
    var snapshotDate: Date
    var selectedAircraftID: String?
    var onSelect: (String) -> Void
    var onStatus: (ARTrackingStatus) -> Void

    func makeUIView(context: Context) -> FlightARContainerView {
        let view = FlightARContainerView()
        view.update(with: self)
        return view
    }

    func updateUIView(_ uiView: FlightARContainerView, context: Context) {
        uiView.update(with: self)
    }

    static func dismantleUIView(_ uiView: FlightARContainerView, coordinator: ()) {
        uiView.stop()
    }
}

final class FlightARContainerView: UIView {
    private struct Candidate {
        let aircraft: Aircraft
        let relative: RelativeAircraftPosition
    }

    private enum FallbackAction {
        case none, settings, retry
    }

    private var input: ARFlightView?
    private var arView: ARView?
    private let overlay = FlightLabelOverlayView()
    private let fallback = UIView()
    private let fallbackLabel = UILabel()
    private let fallbackButton = UIButton(type: .system)
    private var fallbackAction: FallbackAction = .none
    private var labels: [String: AircraftCalloutButton] = [:]
    private var candidates: [Candidate] = []
    private var displayLink: CADisplayLink?
    private var displayTarget: FlightARDisplayTarget?
    private var sessionObserver: FlightARSessionObserver?
    private var notificationTokens: [NSObjectProtocol] = []
    private var lastStatus: ARTrackingStatus?
    private var permissionRequestInProgress = false
    private var isSessionRunning = false
    private var isStopped = false
    private var cameraCanProject = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(red: 0.025, green: 0.045, blue: 0.08, alpha: 1)
        clipsToBounds = true
        configureFallback()
        addSubview(overlay)
        overlay.isUserInteractionEnabled = true

        notificationTokens = [
            NotificationCenter.default.addObserver(
                forName: UIApplication.willResignActiveNotification,
                object: nil, queue: .main
            ) { [weak self] _ in self?.pauseSession() },
            NotificationCenter.default.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil, queue: .main
            ) { [weak self] _ in self?.activateIfVisible() }
        ]
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        arView?.frame = bounds
        overlay.frame = bounds
        fallback.frame = bounds
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { pauseSession() }
        else { activateIfVisible() }
    }

    func update(with input: ARFlightView) {
        self.input = input
        let elapsed = max(0, Date().timeIntervalSince(input.snapshotDate))
        candidates = input.aircraft.compactMap { aircraft in
            guard input.observer.isValid, input.observerAltitudeMeters.isFinite,
                  !aircraft.isOnGround,
                  let coordinate = aircraft.coordinate,
                  let altitude = aircraft.altitudeMeters, altitude.isFinite,
                  let positionAge = aircraft.positionAgeSeconds,
                  positionAge.isFinite, positionAge >= 0, positionAge + elapsed <= 60 else { return nil }
            let relative = FlightGeometry.relativePosition(
                observer: input.observer,
                observerAltitudeMeters: input.observerAltitudeMeters,
                target: coordinate,
                targetAltitudeMeters: altitude
            )
            guard relative.distanceKilometers.isFinite else { return nil }
            return Candidate(aircraft: aircraft, relative: relative)
        }.sorted { left, right in
            let leftSelected = left.aircraft.id == input.selectedAircraftID
            let rightSelected = right.aircraft.id == input.selectedAircraftID
            if leftSelected != rightSelected { return leftSelected }
            if left.relative.distanceKilometers == right.relative.distanceKilometers {
                return left.aircraft.id < right.aircraft.id
            }
            return left.relative.distanceKilometers < right.relative.distanceKilometers
        }
        candidates = Array(candidates.prefix(24))

        let retainedIDs = Set(candidates.map { $0.aircraft.id })
        for id in Array(labels.keys) where !retainedIDs.contains(id) {
            labels.removeValue(forKey: id)?.removeFromOverlay()
        }
        for candidate in candidates {
            let id = candidate.aircraft.id
            let button: AircraftCalloutButton
            if let existing = labels[id] { button = existing }
            else {
                button = AircraftCalloutButton()
                button.onSelect = { [weak self] in self?.input?.onSelect(id) }
                labels[id] = button
                overlay.addSubview(button)
                overlay.layer.insertSublayer(button.connector, at: 0)
            }
            button.configure(
                aircraft: candidate.aircraft,
                distanceKilometers: candidate.relative.distanceKilometers,
                selected: id == input.selectedAircraftID
            )
        }
        projectLabels()
    }

    func stop() {
        guard !isStopped else { return }
        isStopped = true
        arView?.session.pause()
        arView?.session.delegate = nil
        displayLink?.invalidate()
        displayLink = nil
        displayTarget = nil
        sessionObserver = nil
        notificationTokens.forEach(NotificationCenter.default.removeObserver)
        notificationTokens.removeAll()
        labels.values.forEach { $0.removeFromOverlay() }
        labels.removeAll()
    }

    private func configureFallback() {
        addSubview(fallback)
        fallbackLabel.font = .preferredFont(forTextStyle: .body)
        fallbackLabel.textColor = .white
        fallbackLabel.numberOfLines = 0
        fallbackLabel.textAlignment = .center
        fallbackLabel.adjustsFontForContentSizeCategory = true
        fallbackButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        fallbackButton.setTitleColor(.systemCyan, for: .normal)
        fallbackButton.addTarget(self, action: #selector(performFallbackAction), for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [fallbackLabel, fallbackButton])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        fallback.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: fallback.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: fallback.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: fallback.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: fallback.trailingAnchor, constant: -32),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: 460)
        ])
        fallback.isHidden = true
    }

    private func activateIfVisible() {
        guard !isStopped, window != nil, UIApplication.shared.applicationState == .active else { return }
        #if targetEnvironment(simulator)
        showFallback("模拟器无法使用 AR 相机。请在支持 ARKit 的 iPad 上打开 AR；地图与航班详情仍可使用。", action: .none)
        report(.unavailable("请在真实 iPad 上使用 AR"))
        return
        #else
        guard ARWorldTrackingConfiguration.isSupported else {
            showFallback("这台设备不支持 AR 世界跟踪。你仍可在地图和列表中查看航班。", action: .none)
            report(.unavailable("设备不支持 AR 世界跟踪"))
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startSession()
        case .notDetermined:
            guard !permissionRequestInProgress else { return }
            permissionRequestInProgress = true
            report(.initializing)
            AVCaptureDevice.requestAccess(for: .video) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.permissionRequestInProgress = false
                    self?.activateIfVisible()
                }
            }
        case .denied, .restricted:
            showFallback("AR 需要相机权限。请在系统设置中允许使用相机。", action: .settings)
            report(.unavailable("相机权限未开启"))
        @unknown default:
            showFallback("目前无法使用相机，请稍后重试。", action: .retry)
            report(.unavailable("相机目前不可用"))
        }
        #endif
    }

    private func startSession() {
        guard !isSessionRunning, !isStopped, window != nil else { return }
        if arView == nil {
            let view = ARView(frame: bounds, cameraMode: .ar, automaticallyConfigureSession: false)
            view.isUserInteractionEnabled = false
            insertSubview(view, at: 0)
            arView = view
            let observer = FlightARSessionObserver(container: self)
            sessionObserver = observer
            view.session.delegate = observer
            view.session.delegateQueue = .main
        }
        fallback.isHidden = true
        arView?.isHidden = false
        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravityAndHeading
        configuration.isAutoFocusEnabled = true
        arView?.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        isSessionRunning = true
        cameraCanProject = false
        report(.initializing)
        if displayLink == nil {
            let target = FlightARDisplayTarget(container: self)
            displayTarget = target
            let link = CADisplayLink(target: target, selector: #selector(FlightARDisplayTarget.tick))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
        displayLink?.isPaused = false
    }

    private func pauseSession() {
        arView?.session.pause()
        isSessionRunning = false
        cameraCanProject = false
        displayLink?.isPaused = true
        hideLabels()
    }

    fileprivate func handleTracking(_ trackingState: ARCamera.TrackingState) {
        guard !isStopped else { return }
        switch trackingState {
        case .normal:
            cameraCanProject = true
            report(.normal)
        case .notAvailable:
            cameraCanProject = false
            hideLabels()
            report(.limited("相机姿态暂不可用"))
        case .limited(let reason):
            // Keep the direction overlay during limited tracking, with a visible
            // accuracy state supplied to the SwiftUI screen.
            cameraCanProject = true
            switch reason {
            case .initializing: report(.initializing)
            case .excessiveMotion: report(.limited("移动过快，请放慢移动 iPad"))
            case .insufficientFeatures: report(.limited("环境特征不足，方向可能不准确"))
            case .relocalizing: report(.limited("正在恢复方向，请缓慢移动 iPad"))
            @unknown default: report(.limited("AR 跟踪精度有限"))
            }
        }
    }

    fileprivate func handleInterruption() {
        cameraCanProject = false
        hideLabels()
        report(.interrupted)
    }

    fileprivate func handleInterruptionEnd() {
        isSessionRunning = false
        activateIfVisible()
    }

    fileprivate func handleFailure(_ message: String) {
        pauseSession()
        showFallback("AR 会话无法继续。请重试，或在地图中查看航班。\n\n\(message)", action: .retry)
        report(.failed("AR 会话出错，请重试"))
    }

    private func report(_ status: ARTrackingStatus) {
        guard status != lastStatus else { return }
        lastStatus = status
        #if DEBUG
        print("[SkyLens] AR status: \(status.title)")
        #endif
        // A representable may be updated while SwiftUI is rendering. Deliver the
        // small, changed-only status updates on the next main-loop turn.
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isStopped else { return }
            self.input?.onStatus(status)
        }
    }

    private func showFallback(_ message: String, action: FallbackAction) {
        hideLabels()
        arView?.isHidden = true
        fallback.isHidden = false
        fallbackLabel.text = message
        fallbackAction = action
        fallbackButton.isHidden = action == .none
        fallbackButton.setTitle(action == .settings ? "打开系统设置" : "重试 AR", for: .normal)
    }

    @objc private func performFallbackAction() {
        switch fallbackAction {
        case .none: break
        case .settings:
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        case .retry:
            isSessionRunning = false
            activateIfVisible()
        }
    }

    private func hideLabels() {
        for label in labels.values {
            label.isHidden = true
            label.connector.isHidden = true
        }
    }

    fileprivate func projectLabels() {
        guard isSessionRunning, cameraCanProject,
              let arView, let frame = arView.session.currentFrame,
              let input, bounds.width > 0, bounds.height > 0 else {
            hideLabels()
            return
        }
        let camera = frame.camera
        let cameraPosition = SIMD3<Float>(
            camera.transform.columns.3.x,
            camera.transform.columns.3.y,
            camera.transform.columns.3.z
        )
        let worldToCamera = simd_inverse(camera.transform)
        let orientation = window?.windowScene?.interfaceOrientation ?? .portrait
        let viewport = bounds.size
        let layoutBounds = bounds.insetBy(dx: 14, dy: 24)
        let elapsed = max(0, Date().timeIntervalSince(input.snapshotDate))
        var occupied: [CGRect] = []

        for candidate in candidates {
            guard let label = labels[candidate.aircraft.id] else { continue }
            label.isHidden = true
            label.connector.isHidden = true
            guard let age = candidate.aircraft.positionAgeSeconds, age + elapsed <= 60 else { continue }

            // Heading-aligned ARKit axes are east (+x), up (+y), south (+z).
            // Only the direction is projected: placing a point 100 m away avoids
            // unstable clipping of objects tens of kilometres from the camera.
            let relative = candidate.relative
            let vector = SIMD3<Float>(
                Float(relative.eastMeters),
                Float(relative.upMeters),
                -Float(relative.northMeters)
            )
            let magnitude = simd_length(vector)
            guard magnitude.isFinite, magnitude > 0.1 else { continue }
            let worldPoint = cameraPosition + vector / magnitude * 100
            let cameraPoint = worldToCamera * SIMD4<Float>(worldPoint, 1)
            guard cameraPoint.z < -0.01 else { continue }
            let anchor = camera.projectPoint(worldPoint, orientation: orientation, viewportSize: viewport)
            guard anchor.x.isFinite, anchor.y.isFinite, bounds.contains(anchor) else { continue }

            let labelSize = CGSize(width: min(246, layoutBounds.width), height: 64)
            let offsets: [CGPoint] = [
                CGPoint(x: 0, y: -labelSize.height - 12),
                CGPoint(x: 0, y: 12),
                CGPoint(x: 24, y: -labelSize.height * 2 - 20),
                CGPoint(x: -24, y: labelSize.height + 20)
            ]
            var chosenFrame: CGRect?
            for offset in offsets {
                var rect = CGRect(
                    origin: CGPoint(x: anchor.x - labelSize.width / 2 + offset.x, y: anchor.y + offset.y),
                    size: labelSize
                )
                rect.origin.x = min(max(rect.minX, layoutBounds.minX), layoutBounds.maxX - rect.width)
                guard layoutBounds.contains(rect),
                      occupied.allSatisfy({ !$0.insetBy(dx: -5, dy: -5).intersects(rect) }) else { continue }
                chosenFrame = rect
                break
            }
            guard let chosenFrame else { continue }
            occupied.append(chosenFrame)
            label.frame = chosenFrame
            label.isHidden = false
            label.drawConnector(from: anchor)
        }
    }
}

private final class FlightARDisplayTarget: NSObject {
    weak var container: FlightARContainerView?
    init(container: FlightARContainerView) { self.container = container }
    @objc func tick() { container?.projectLabels() }
}

private final class FlightARSessionObserver: NSObject, ARSessionDelegate {
    weak var container: FlightARContainerView?
    init(container: FlightARContainerView) { self.container = container }

    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        container?.handleTracking(camera.trackingState)
    }

    func sessionWasInterrupted(_ session: ARSession) { container?.handleInterruption() }
    func sessionInterruptionEnded(_ session: ARSession) { container?.handleInterruptionEnd() }
    func session(_ session: ARSession, didFailWithError error: Error) {
        container?.handleFailure(error.localizedDescription)
    }
}

private final class FlightLabelOverlayView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }
}

private final class AircraftCalloutButton: UIButton {
    let connector = CAShapeLayer()
    var onSelect: (() -> Void)?
    private let nameLabel = UILabel()
    private let detailLabel = UILabel()
    private let planeImageView = UIImageView(image: UIImage(systemName: "airplane"))

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = 14
        layer.borderWidth = 1
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.3
        layer.shadowRadius = 6
        layer.shadowOffset = CGSize(width: 0, height: 3)
        addTarget(self, action: #selector(selectFlight), for: .touchUpInside)
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityHint = "打开航班和飞机详情"

        nameLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        nameLabel.textColor = .white
        nameLabel.lineBreakMode = .byTruncatingTail
        detailLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        detailLabel.textColor = UIColor.white.withAlphaComponent(0.8)
        detailLabel.lineBreakMode = .byTruncatingTail
        planeImageView.contentMode = .scaleAspectFit
        planeImageView.tintColor = .systemCyan
        let texts = UIStackView(arrangedSubviews: [nameLabel, detailLabel])
        texts.axis = .vertical
        texts.spacing = 5
        let row = UIStackView(arrangedSubviews: [planeImageView, texts])
        row.spacing = 12
        row.alignment = .center
        row.isUserInteractionEnabled = false
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
            planeImageView.widthAnchor.constraint(equalToConstant: 23),
            planeImageView.heightAnchor.constraint(equalToConstant: 23)
        ])
        connector.fillColor = UIColor.clear.cgColor
        connector.lineWidth = 1.25
        connector.isHidden = true
        connector.actions = ["path": NSNull(), "hidden": NSNull()]
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(aircraft: Aircraft, distanceKilometers: Double, selected: Bool) {
        let name = aircraft.callsign ?? aircraft.registration ?? aircraft.id.uppercased()
        let registration = aircraft.registration ?? aircraft.typeCode ?? "注册号未知"
        let distance = String(format: "%.1f", distanceKilometers)
        let altitude = aircraft.altitudeMeters.map { String(format: "%.0f", $0) } ?? "—"
        nameLabel.text = name
        detailLabel.text = "\(registration) · \(distance) km · \(altitude) m"
        accessibilityLabel = "\(name)，\(registration)，距离 \(distance) 公里，高度 \(altitude) 米"
        backgroundColor = selected
            ? UIColor(red: 0.04, green: 0.25, blue: 0.31, alpha: 0.94)
            : UIColor(red: 0.025, green: 0.06, blue: 0.12, alpha: 0.9)
        layer.borderColor = (selected ? UIColor.systemCyan : UIColor.white.withAlphaComponent(0.3)).cgColor
        connector.strokeColor = (selected ? UIColor.systemCyan : UIColor.white.withAlphaComponent(0.6)).cgColor
        accessibilityTraits = selected ? [.button, .selected] : .button
    }

    func drawConnector(from anchor: CGPoint) {
        let nearest = CGPoint(
            x: min(max(anchor.x, frame.minX + 14), frame.maxX - 14),
            y: anchor.y < frame.midY ? frame.minY : frame.maxY
        )
        let path = UIBezierPath()
        path.move(to: anchor)
        path.addLine(to: nearest)
        path.move(to: CGPoint(x: anchor.x + 3, y: anchor.y))
        path.addArc(withCenter: anchor, radius: 3, startAngle: 0, endAngle: .pi * 2, clockwise: true)
        connector.path = path.cgPath
        connector.isHidden = false
    }

    func removeFromOverlay() {
        connector.removeFromSuperlayer()
        removeFromSuperview()
    }

    @objc private func selectFlight() { onSelect?() }
}
