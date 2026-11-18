// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FlightTrackCore",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [.library(name: "FlightTrackCore", targets: ["FlightTrackCore"])],
    targets: [
        .target(name: "FlightTrackCore", path: "FlightTrack/Core"),
        .testTarget(name: "FlightTrackCoreTests", dependencies: ["FlightTrackCore"])
    ]
)
