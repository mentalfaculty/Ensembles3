// swift-tools-version:5.9
import PackageDescription

let version = "3.0.1"
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
            checksum: "9957aaefb5bf29bbd23470947eee0780378f904082f386ffaa08f392b821fdcc"),
        .binaryTarget(name: "EnsemblesCloudKit",
            url: "\(base)/EnsemblesCloudKit.xcframework.zip",
            checksum: "19c6e84c21eefbaf753424a38397aea54aab5cb95294f141a2990a0a7438ff25"),
        .binaryTarget(name: "EnsemblesLocalFile",
            url: "\(base)/EnsemblesLocalFile.xcframework.zip",
            checksum: "f9b3ec5faacee225bcd3bbd768f7667a6b7eac2322be7117ac4bcd932d92dc1f"),
        .binaryTarget(name: "EnsemblesMemory",
            url: "\(base)/EnsemblesMemory.xcframework.zip",
            checksum: "143f75f094e315782ebe5e044151dcc6387769b8dd479c583c89f4d3cddd45a9"),
        .binaryTarget(name: "EnsemblesSwiftData",
            url: "\(base)/EnsemblesSwiftData.xcframework.zip",
            checksum: "c639b100c2c6126655ddfd86d58fad8b2c6a965d3f7922c1b0c48b7a2ec2b1e5"),
        // Paid
        .binaryTarget(name: "EnsemblesGoogleDrive",
            url: "\(base)/EnsemblesGoogleDrive.xcframework.zip",
            checksum: "9adfd91a064dc18bfeb4b9e4c8fa1e26d847188d42944b0ebde6b3b815ebbe20"),
        .binaryTarget(name: "EnsemblesOneDrive",
            url: "\(base)/EnsemblesOneDrive.xcframework.zip",
            checksum: "b5bc78bc20649d2e8586da35258fd8927361108295de331fbf2343b541c378d9"),
        .binaryTarget(name: "EnsemblesPCloud",
            url: "\(base)/EnsemblesPCloud.xcframework.zip",
            checksum: "6fb7e53a084e36d0980e388f8b52fff15215c464ebb829a25edfdff01a415c41"),
        .binaryTarget(name: "EnsemblesSupabase",
            url: "\(base)/EnsemblesSupabase.xcframework.zip",
            checksum: "8df1a99c20b901d19e8a38e809f84e8c4818912c20bb25b5f9290637ff2d8d8e"),
        .binaryTarget(name: "EnsemblesWebDAV",
            url: "\(base)/EnsemblesWebDAV.xcframework.zip",
            checksum: "05d589cd0b83390f575a9548a7bcd86ef7fd0807a446eb5d048aad3b36b946e7"),
        .binaryTarget(name: "EnsemblesEncrypted",
            url: "\(base)/EnsemblesEncrypted.xcframework.zip",
            checksum: "2ca56a073b8c346ab3116b713ff885369bced0b05b8dc643dbdcf42e37d8ae3b"),
        // Paid + external SDK required (add the SDK as a separate package dependency)
        .binaryTarget(name: "EnsemblesDropbox",
            url: "\(base)/EnsemblesDropbox.xcframework.zip",
            checksum: "1a7ba0f806292ffb3db763a6b07fdc44e8e96863c810e7dfaaa36cddfbea3a79"),
        .binaryTarget(name: "EnsemblesS3",
            url: "\(base)/EnsemblesS3.xcframework.zip",
            checksum: "e1143417a76ebed9d80e019e510f91dcfa96b1712b444baf2e3fbe3209e51c45"),
        .binaryTarget(name: "EnsemblesBox",
            url: "\(base)/EnsemblesBox.xcframework.zip",
            checksum: "fe0f7b52e55bfeeafee2cf53f554f45286c54b95789c32c6b6d4a1cf036a5322"),
        .binaryTarget(name: "EnsemblesZip",
            url: "\(base)/EnsemblesZip.xcframework.zip",
            checksum: "3adf4c19177782244262677ff3f8a059152c3c24ef47bafff51c71a240bcb229"),
        .binaryTarget(name: "EnsemblesMultipeer",
            url: "\(base)/EnsemblesMultipeer.xcframework.zip",
            checksum: "1470b081024ce1b443eb62b6e02d409a9141fd4d1d2e7c3af59ed069de18894e"),
        // Tests
        .testTarget(
            name: "EnsemblesTests",
            dependencies: [
                "Ensembles", "EnsemblesMemory", "EnsemblesLocalFile",
                "EnsemblesEncrypted", "EnsemblesGoogleDrive", "EnsemblesOneDrive", "EnsemblesPCloud",
                "EnsemblesSupabase",
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
