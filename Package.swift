// swift-tools-version:5.9
import PackageDescription

let version = "3.0.15"
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
            checksum: "27a0a2651f4e959da01b3ab6293db8995b064220a18c6a2b4c21648e77cb36d5"),
        .binaryTarget(name: "EnsemblesCloudKit",
            url: "\(base)/EnsemblesCloudKit.xcframework.zip",
            checksum: "a2ab0db1f9176102d7871f93a54547310ebc640c0a08d35e97776a3d3ad07725"),
        .binaryTarget(name: "EnsemblesLocalFile",
            url: "\(base)/EnsemblesLocalFile.xcframework.zip",
            checksum: "7c861e06343faba6602b0302366ef0be363daef36cec782205878644a49e02b6"),
        .binaryTarget(name: "EnsemblesMemory",
            url: "\(base)/EnsemblesMemory.xcframework.zip",
            checksum: "4ac9d6f43ea99d680aac3ad22ab69d2c43dcb7c10f8ea4d474a589f3ee829157"),
        .binaryTarget(name: "EnsemblesSwiftData",
            url: "\(base)/EnsemblesSwiftData.xcframework.zip",
            checksum: "4512272b076771de8dbfcb311753ad3b45bafc00de2a370daf3d66b50b80c6b9"),
        // Paid
        .binaryTarget(name: "EnsemblesGoogleDrive",
            url: "\(base)/EnsemblesGoogleDrive.xcframework.zip",
            checksum: "fdc11de07c6c17898a59784f487e391fb37eb732ee9fee1ae2af3837158746ff"),
        .binaryTarget(name: "EnsemblesOneDrive",
            url: "\(base)/EnsemblesOneDrive.xcframework.zip",
            checksum: "714febab778103c03615bfa7dd2df897a2c350f1513d893805ec30aaefccd673"),
        .binaryTarget(name: "EnsemblesPCloud",
            url: "\(base)/EnsemblesPCloud.xcframework.zip",
            checksum: "d17c6d994e0921cacd63cf0f0c2d93cdce30c9b9c2b01a26b5e3c6c70ddd0e0f"),
        .binaryTarget(name: "EnsemblesSupabase",
            url: "\(base)/EnsemblesSupabase.xcframework.zip",
            checksum: "e653615fc276599195877f19f3b2907575e04c8f8fe6c3f7c4bdecab19243bb9"),
        .binaryTarget(name: "EnsemblesWebDAV",
            url: "\(base)/EnsemblesWebDAV.xcframework.zip",
            checksum: "798ab263246affda284b89d89ea0783ad776934f9c055afe67b209512088553f"),
        .binaryTarget(name: "EnsemblesEncrypted",
            url: "\(base)/EnsemblesEncrypted.xcframework.zip",
            checksum: "ff34709d83ee3ed87e2562b7b4d95a12a299dafa70929f71de9a20c5b60b3330"),
        // Paid + external SDK required (add the SDK as a separate package dependency)
        .binaryTarget(name: "EnsemblesiCloudDrive",
            url: "\(base)/EnsemblesiCloudDrive.xcframework.zip",
            checksum: "8caca0687d0a191b6018cc4f12a4806d19a2e7b3507f8eeab7ff764e3573bb86"),
        .binaryTarget(name: "EnsemblesDropbox",
            url: "\(base)/EnsemblesDropbox.xcframework.zip",
            checksum: "89c1df97e6102224339b600c7d59c1f0ec8917a8ec1fc326dc042a9fb8af386d"),
        .binaryTarget(name: "EnsemblesS3",
            url: "\(base)/EnsemblesS3.xcframework.zip",
            checksum: "5bfc2b5b55e1066a1b5a6511f9d4af20dff032f80c1f18f2d827582610739335"),
        .binaryTarget(name: "EnsemblesBox",
            url: "\(base)/EnsemblesBox.xcframework.zip",
            checksum: "c80933800c230019e7e84809e3fe32a82a07ab3dc0551499e92b0758f560059c"),
        .binaryTarget(name: "EnsemblesZip",
            url: "\(base)/EnsemblesZip.xcframework.zip",
            checksum: "8419b6f6bb9c641d9c591c56069ae9612df1b354fd971e07284429cf98d12ec2"),
        .binaryTarget(name: "EnsemblesMultipeer",
            url: "\(base)/EnsemblesMultipeer.xcframework.zip",
            checksum: "9bd08b4067e91f8ee9add1ffe2aab11a0ef8f087df728dcfa406588f19e10ad3"),
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
