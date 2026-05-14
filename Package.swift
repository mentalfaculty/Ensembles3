// swift-tools-version:5.9
import PackageDescription

let version = "3.0.0-beta.14"
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
            checksum: "60c7e5ae2b702545c84dc196cadd539ce16c633c23eaf2d84015e8340dc4c277"),
        .binaryTarget(name: "EnsemblesCloudKit",
            url: "\(base)/EnsemblesCloudKit.xcframework.zip",
            checksum: "80f471e3ef624377f95b8a2362b065c8483bb122fd445ad6bbce87dd61ec267b"),
        .binaryTarget(name: "EnsemblesLocalFile",
            url: "\(base)/EnsemblesLocalFile.xcframework.zip",
            checksum: "5533385ea4dc2c1ae172510c3bf28b622d838baf512917ff885f77c0906d0e87"),
        .binaryTarget(name: "EnsemblesMemory",
            url: "\(base)/EnsemblesMemory.xcframework.zip",
            checksum: "d362aebc527b995946553e903d02996e9bcbe276f30ed67d5397ac496e06f459"),
        .binaryTarget(name: "EnsemblesSwiftData",
            url: "\(base)/EnsemblesSwiftData.xcframework.zip",
            checksum: "3781ae780505476d4fbcbbcf68bdf70c53a0b07c68428143633e162c29fe68f1"),
        // Paid
        .binaryTarget(name: "EnsemblesGoogleDrive",
            url: "\(base)/EnsemblesGoogleDrive.xcframework.zip",
            checksum: "00fe271e489faa932f04227b1f1b6bcbb68725d8173d8645a85766234ee25ee8"),
        .binaryTarget(name: "EnsemblesOneDrive",
            url: "\(base)/EnsemblesOneDrive.xcframework.zip",
            checksum: "539ef1e1d26e8d1ffc356147cb25bf26c414be11ecd9fade88ef0483f67ca388"),
        .binaryTarget(name: "EnsemblesPCloud",
            url: "\(base)/EnsemblesPCloud.xcframework.zip",
            checksum: "7752ef33388f697bb761b0ba97f0aec1394375bc06467603089b3883fcd5035c"),
        .binaryTarget(name: "EnsemblesSupabase",
            url: "\(base)/EnsemblesSupabase.xcframework.zip",
            checksum: "e0d53dbf06ff6c66fc94f46d13423064ae156583fe088e3e007620f20450000e"),
        .binaryTarget(name: "EnsemblesWebDAV",
            url: "\(base)/EnsemblesWebDAV.xcframework.zip",
            checksum: "e71bc12784dd67656eb2d4dbb9f9cfc8e7d219f37dc692e80aaf12f8b6ea1e6d"),
        .binaryTarget(name: "EnsemblesEncrypted",
            url: "\(base)/EnsemblesEncrypted.xcframework.zip",
            checksum: "27ac91e352477eb20bb6ffce000b92e51bc9937d77b4ae65f39331522e841047"),
        // Paid + external SDK required (add the SDK as a separate package dependency)
        .binaryTarget(name: "EnsemblesDropbox",
            url: "\(base)/EnsemblesDropbox.xcframework.zip",
            checksum: "0405bb250391f3f60669395e9e7a39ba76165236049907bc57c3753a8109096a"),
        .binaryTarget(name: "EnsemblesS3",
            url: "\(base)/EnsemblesS3.xcframework.zip",
            checksum: "d8502d9bff4d783d09412f314c2098953c506b50a484c919a987f7b5f32e36b7"),
        .binaryTarget(name: "EnsemblesBox",
            url: "\(base)/EnsemblesBox.xcframework.zip",
            checksum: "ebed25006552a6bd9548b0a6620530a933be6cb3920c74221ecfce6baee272c9"),
        .binaryTarget(name: "EnsemblesZip",
            url: "\(base)/EnsemblesZip.xcframework.zip",
            checksum: "8b3e343e1d8b480ac36581a1984232d10bb7f3dc571f2b25524d6ff65a3992ab"),
        .binaryTarget(name: "EnsemblesMultipeer",
            url: "\(base)/EnsemblesMultipeer.xcframework.zip",
            checksum: "a08b6e0a8a4906fd1852a7014be23144c1dc1ae441beb2acf4f783b7b9177513"),
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
