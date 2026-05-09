// swift-tools-version:5.9
import PackageDescription

let version = "3.0.0-beta.9"
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
            checksum: "f2495e52af2f644d0faf3751eaad55480c0010a0b397ff5782c0f95a15f937fd"),
        .binaryTarget(name: "EnsemblesCloudKit",
            url: "\(base)/EnsemblesCloudKit.xcframework.zip",
            checksum: "97393da0aa23ca8b620a583bf8d182b4e4c71fa1f428cc635388041f5b1a2747"),
        .binaryTarget(name: "EnsemblesLocalFile",
            url: "\(base)/EnsemblesLocalFile.xcframework.zip",
            checksum: "94840bff17a06260c22b1f007fea1c5aaf019a5e4060364c5686f15e3012418b"),
        .binaryTarget(name: "EnsemblesMemory",
            url: "\(base)/EnsemblesMemory.xcframework.zip",
            checksum: "d81dbef2ac1d067cc38d9842d0b52fb331b2f135e5898752322978091d0817fb"),
        .binaryTarget(name: "EnsemblesSwiftData",
            url: "\(base)/EnsemblesSwiftData.xcframework.zip",
            checksum: "702d27bd61920e09662d994f80fffe338d3a51169e7c5212649557ad385ab93f"),
        // Paid
        .binaryTarget(name: "EnsemblesGoogleDrive",
            url: "\(base)/EnsemblesGoogleDrive.xcframework.zip",
            checksum: "042b5ba239211a7b006b82a1b8ee3c482aca942a1b03ecdb51db9d8b4a4c023e"),
        .binaryTarget(name: "EnsemblesOneDrive",
            url: "\(base)/EnsemblesOneDrive.xcframework.zip",
            checksum: "9d063a2320e8de56efeff49d2b290d8691a5398f0a4cb67c8aa433a09ae57b84"),
        .binaryTarget(name: "EnsemblesPCloud",
            url: "\(base)/EnsemblesPCloud.xcframework.zip",
            checksum: "49be542d4df0573aff64e1e637a2137f920b2ec772d83c39f608985c08d8e489"),
        .binaryTarget(name: "EnsemblesWebDAV",
            url: "\(base)/EnsemblesWebDAV.xcframework.zip",
            checksum: "33dd619b0938043874b7e21a2fc888421279d395c836fdf2c59453cf67a89917"),
        .binaryTarget(name: "EnsemblesEncrypted",
            url: "\(base)/EnsemblesEncrypted.xcframework.zip",
            checksum: "ff35571e3e3017a4582fd77f839cbaa2e21265560523f68b11115a88bc14d8dc"),
        // Paid + external SDK required (add the SDK as a separate package dependency)
        .binaryTarget(name: "EnsemblesDropbox",
            url: "\(base)/EnsemblesDropbox.xcframework.zip",
            checksum: "bb61f939ed9b4338454210f847f8616688b89e311726054468632cc373c82ff6"),
        .binaryTarget(name: "EnsemblesS3",
            url: "\(base)/EnsemblesS3.xcframework.zip",
            checksum: "3a3a786442e25e8aa361e2bdac740fbc6a5f31c3306cea3e949dc341b2d205fe"),
        .binaryTarget(name: "EnsemblesBox",
            url: "\(base)/EnsemblesBox.xcframework.zip",
            checksum: "a9c33e08d75b0906073fc1a0a32219f05ddb53047adae0357829828a2a0aef99"),
        .binaryTarget(name: "EnsemblesZip",
            url: "\(base)/EnsemblesZip.xcframework.zip",
            checksum: "2486e2bf1b4be263f50e083578ee1fa00cae5aa731a459cd25ce1fee92754a47"),
        .binaryTarget(name: "EnsemblesMultipeer",
            url: "\(base)/EnsemblesMultipeer.xcframework.zip",
            checksum: "2bc33712b30f40c4aacbc965ba7834e032b7f1675073233c8480f601ab871366"),
        // Tests
        .testTarget(
            name: "EnsemblesTests",
            dependencies: [
                "Ensembles", "EnsemblesMemory", "EnsemblesLocalFile",
                "EnsemblesEncrypted", "EnsemblesGoogleDrive", "EnsemblesOneDrive", "EnsemblesPCloud",
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
