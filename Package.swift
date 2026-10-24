// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MenubarTodo",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "MenubarTodo", path: "Sources/MenubarTodo")
    ]
)
