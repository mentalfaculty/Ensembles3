// swift-tools-version:5.9
import PackageDescription

let version = "3.0.12"
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
            checksum: "9b0fa4a29192c8b5e9b3a268c9427f4887bad245d8a71da683e14704cdcfcbc1"),
        .binaryTarget(name: "EnsemblesCloudKit",
            url: "\(base)/EnsemblesCloudKit.xcframework.zip",
            checksum: "a5441bd083fd675c34edfb4a5eec7bfe054b17b1301314c9a1cb81811ae5295d"),
        .binaryTarget(name: "EnsemblesLocalFile",
            url: "\(base)/EnsemblesLocalFile.xcframework.zip",
            checksum: "874d78812572a07916cbf21c09ffcba32cc4483c072e888a24817915ec25cc6b"),
        .binaryTarget(name: "EnsemblesMemory",
            url: "\(base)/EnsemblesMemory.xcframework.zip",
            checksum: "4930d4824e4cc7361ef2971246638ee4e9bb7854f615af02ccb977e9406d1487"),
        .binaryTarget(name: "EnsemblesSwiftData",
            url: "\(base)/EnsemblesSwiftData.xcframework.zip",
            checksum: "976e653a0680a1dcf644b90866d3d74c35bbb92c99ce703ecdb0e9921834065c"),
        // Paid
        .binaryTarget(name: "EnsemblesGoogleDrive",
            url: "\(base)/EnsemblesGoogleDrive.xcframework.zip",
            checksum: "7a4006e2738ddb771d6cf95d9a6c59f9398f7c82cd4792510142b8c4b6e42f9d"),
        .binaryTarget(name: "EnsemblesOneDrive",
            url: "\(base)/EnsemblesOneDrive.xcframework.zip",
            checksum: "30663a68b3c585bcb28b6dbaa65bf82a6edc0537474b4b7d3d714db89c774985"),
        .binaryTarget(name: "EnsemblesPCloud",
            url: "\(base)/EnsemblesPCloud.xcframework.zip",
            checksum: "ce1616240bb9561f3e86a217171994c37915c91110e9b095f4a6dcd2c961b4c7"),
        .binaryTarget(name: "EnsemblesSupabase",
            url: "\(base)/EnsemblesSupabase.xcframework.zip",
            checksum: "99bddd52966fe4138c713332cd274b309dc212938ce34cf21b6889b549e2a534"),
        .binaryTarget(name: "EnsemblesWebDAV",
            url: "\(base)/EnsemblesWebDAV.xcframework.zip",
            checksum: "eaba735c284fd3d9a956f002e33f195961aa61717f0e0f5db610a712de8bb4bb"),
        .binaryTarget(name: "EnsemblesEncrypted",
            url: "\(base)/EnsemblesEncrypted.xcframework.zip",
            checksum: "7177aaf9d408c5b5c864c9b293e2ba84600ccdadca1ee0b73790f69bbb6013d8"),
        // Paid + external SDK required (add the SDK as a separate package dependency)
        .binaryTarget(name: "EnsemblesiCloudDrive",
            url: "\(base)/EnsemblesiCloudDrive.xcframework.zip",
            checksum: "aec7baba9cb18c15094c57be5a0a9f7ce581e785e4e367827c6dcdbb872ffebd"),
        .binaryTarget(name: "EnsemblesDropbox",
            url: "\(base)/EnsemblesDropbox.xcframework.zip",
            checksum: "e8ce6764316537b55f67d4357db258b626f911878f0594727c7bd02b9700181a"),
        .binaryTarget(name: "EnsemblesS3",
            url: "\(base)/EnsemblesS3.xcframework.zip",
            checksum: "206105784c9193c6b3a2254716f344ccbe08f4ac37785f5da0cc79f4380f389b"),
        .binaryTarget(name: "EnsemblesBox",
            url: "\(base)/EnsemblesBox.xcframework.zip",
            checksum: "82ee59499b198071e1c8259c3a1fe98db9f68bbe7fb11f5a0ad308d33746376b"),
        .binaryTarget(name: "EnsemblesZip",
            url: "\(base)/EnsemblesZip.xcframework.zip",
            checksum: "a36e5217cb3d9b9e7b8b9cb487dcdd456f7b539959b8632e69030f2961fefaa5"),
        .binaryTarget(name: "EnsemblesMultipeer",
            url: "\(base)/EnsemblesMultipeer.xcframework.zip",
            checksum: "ecc17082185008426585c9c2ea4c57543df7cc463e36b9d0e2826253a9bf8948"),
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
