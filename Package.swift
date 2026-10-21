// swift-tools-version:5.9
import PackageDescription

let version = "3.0.14"
let base = "https://github.com/mentalfaculty/Ensembles3/releases/download/\(version)"

let package = Package(
    name: "Ensembles3",
    platforms: [.iOS(.v15), .macOS(.v12), .tvOS(.v15), .watchOS(.v8)],
    products: [
        // Free
        .library(name: "Ensembles", targets: ["Ensembles"]),
        .library(name: "EnsemblesCloudKit", targets: ["EnsemblesCloudKit"]),
        .library(name: "EnsemblesLocalFile", targets: ["EnsemblesLocalFile"]),
        .library(name: "EnsemblesMemory", targets: ["EnsemblesMemory"]),
        .library(name: "EnsemblesSwiftData", targets: ["EnsemblesSwiftData"]),
        .library(name: "EnsemblesiCloudDrive", targets: ["EnsemblesiCloudDrive"]),
        // Paid (requires license)
        .library(name: "EnsemblesGoogleDrive", targets: ["EnsemblesGoogleDrive"]),
        .library(name: "EnsemblesOneDrive", targets: ["EnsemblesOneDrive"]),
        .library(name: "EnsemblesPCloud", targets: ["EnsemblesPCloud"]),
        .library(name: "EnsemblesSupabase", targets: ["EnsemblesSupabase"]),
        .library(name: "EnsemblesWebDAV", targets: ["EnsemblesWebDAV"]),
        .library(name: "EnsemblesEncrypted", targets: ["EnsemblesEncrypted"]),
        // Paid + requires external SDK (see README for details)
        .library(name: "EnsemblesDropbox", targets: ["EnsemblesDropbox"]),
        .library(name: "EnsemblesS3", targets: ["EnsemblesS3"]),
        .library(name: "EnsemblesBox", targets: ["EnsemblesBox"]),
        .library(name: "EnsemblesZip", targets: ["EnsemblesZip"]),
        .library(name: "EnsemblesMultipeer", targets: ["EnsemblesMultipeer"]),
    ],
    targets: [
        // Free
        .binaryTarget(name: "Ensembles",
            url: "\(base)/Ensembles.xcframework.zip",
            checksum: "91ad94b7d42db061840d0ad5d8a33d12206addb35fb5068842f664fb35589ea5"),
        .binaryTarget(name: "EnsemblesCloudKit",
            url: "\(base)/EnsemblesCloudKit.xcframework.zip",
            checksum: "eb88f1b0493aa049a4970e1526c27b6faf6d7cda4859059a7fb1196e9b5fa59e"),
        .binaryTarget(name: "EnsemblesLocalFile",
            url: "\(base)/EnsemblesLocalFile.xcframework.zip",
            checksum: "89d2cfab71c313bd083d3b0b0976a45639a275bfb83cb6b7355b25c9ccd9cf1d"),
        .binaryTarget(name: "EnsemblesMemory",
            url: "\(base)/EnsemblesMemory.xcframework.zip",
            checksum: "107e8ac6520b4f6f9720749c27e8b97d22e0716af2c24524900e96f2a53ee10f"),
        .binaryTarget(name: "EnsemblesSwiftData",
            url: "\(base)/EnsemblesSwiftData.xcframework.zip",
            checksum: "8c942ca4a421ab98ed0f216e089b0c9787ed73f08c0e5e68f7b426035f5d6e2d"),
        // Paid
        .binaryTarget(name: "EnsemblesGoogleDrive",
            url: "\(base)/EnsemblesGoogleDrive.xcframework.zip",
            checksum: "caebb8819da0d803bc47e112ed96dbc606798d489ddb1091873df8a20e223103"),
        .binaryTarget(name: "EnsemblesOneDrive",
            url: "\(base)/EnsemblesOneDrive.xcframework.zip",
            checksum: "8103deb52e831f8d324067b4884a0aa1f9b229540a8636291b38b77ccfc3fa8b"),
        .binaryTarget(name: "EnsemblesPCloud",
            url: "\(base)/EnsemblesPCloud.xcframework.zip",
            checksum: "97d782abf18fcfdffd8a47d4ef635fc795ad68ee77a956d669b7e38305b80b46"),
        .binaryTarget(name: "EnsemblesSupabase",
            url: "\(base)/EnsemblesSupabase.xcframework.zip",
            checksum: "136afd2872ab26e56c67ded5b71d2f931148a25dc8897500c054cce9793a1f41"),
        .binaryTarget(name: "EnsemblesWebDAV",
            url: "\(base)/EnsemblesWebDAV.xcframework.zip",
            checksum: "0c48de12b8d145c0ddd6bf94437072e807ec1b2e91a70848844fec1248ef12e7"),
        .binaryTarget(name: "EnsemblesEncrypted",
            url: "\(base)/EnsemblesEncrypted.xcframework.zip",
            checksum: "42d7ca8fd150fc755e3e2e23e92b2cb5bb116f31b993d745a0e4688357585dff"),
        // Paid + external SDK required (add the SDK as a separate package dependency)
        .binaryTarget(name: "EnsemblesiCloudDrive",
            url: "\(base)/EnsemblesiCloudDrive.xcframework.zip",
            checksum: "348c14d1a1413bcaf24919f812785eea04a44afa75276c023b354396322e9dc1"),
        .binaryTarget(name: "EnsemblesDropbox",
            url: "\(base)/EnsemblesDropbox.xcframework.zip",
            checksum: "84069067a9df7bb4d1b8314c56fe533e7cd91f21d1078e2d1c10c62e78facb31"),
        .binaryTarget(name: "EnsemblesS3",
            url: "\(base)/EnsemblesS3.xcframework.zip",
            checksum: "3c5824436690fd096748687ed2dd5c65c07bac03272868c92143315baafc5263"),
        .binaryTarget(name: "EnsemblesBox",
            url: "\(base)/EnsemblesBox.xcframework.zip",
            checksum: "0988130362aa46e11fdae8cb6d74b24d64636eda4cf67e41177e00983c003a30"),
        .binaryTarget(name: "EnsemblesZip",
            url: "\(base)/EnsemblesZip.xcframework.zip",
            checksum: "f67d106595218334a6f4030a781d04748bd35dcb975ada6418ced457907e35c6"),
        .binaryTarget(name: "EnsemblesMultipeer",
            url: "\(base)/EnsemblesMultipeer.xcframework.zip",
            checksum: "30e4038e279af808806df125813bb7fea1c7cd7f68a1b1b78629fdabb968106f"),
        // Tests
        .testTarget(
            name: "EnsemblesTests",
            dependencies: [
                "Ensembles", "EnsemblesMemory", "EnsemblesLocalFile",
                "EnsemblesEncrypted", "EnsemblesGoogleDrive", "EnsemblesOneDrive", "EnsemblesPCloud",
                "EnsemblesSupabase", "EnsemblesCloudKit",
            ],
            path: "Tests/EnsemblesTests",
            exclude: [
                "Resources/CDEStoreModificationEventTestsModel.xcdatamodeld",
                "Resources/CDEMigratedTestsModel.xcdatamodeld",
            ],
            resources: [
                .copy("Resources/CDEStoreModificationEventTestsModel.momd"),
                .copy("Resources/CDEMigratedTestsModel.momd"),
                .copy("Resources/Integrator Test Fixtures"),
            ]
        ),
        .testTarget(
            name: "EnsemblesSwiftDataTests",
            dependencies: ["EnsemblesSwiftData", "EnsemblesMemory", "EnsemblesLocalFile", "Ensembles"],
            path: "Tests/EnsemblesSwiftDataTests"
        ),
    ]
)
