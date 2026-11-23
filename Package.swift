// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Varal",
    platforms: [.macOS(.v14)],
    targets: [
        // All app sources live under Varal/. The testable logic is compiled
        // into VaralKit; the executable target only adds the @main entry.
        .target(
            name: "VaralKit",
            path: ".",
            sources: [
                "Varal/Contracts/CompanionPiece.swift",
                "Varal/Models/TaskSlip.swift",
                "Varal/Models/VacationPlan.swift",
                "Varal/Services/TaskSlipStore.swift",
                "Varal/Services/HolidayPlanStore.swift",
                "Varal/Services/URLSchemeRouter.swift",
                "Varal/Services/RolloverScheduler.swift",
                "Varal/Services/UIStrings.swift",
                "Varal/Engine/ClotheslinePhysicsEngine.swift",
                "Varal/Engine/OcclusionGovernor.swift",
                "Varal/Pieces/AtmosPiece.swift",
                "Varal/Pieces/GetLongWeekendPiece.swift",
                "Varal/UI/DesktopYardWindow.swift",
                "Varal/UI/ClotheslineCanvasView.swift",
                "Varal/UI/TaskSlipView.swift",
                "Varal/UI/LaundryBasketView.swift",
                "Varal/UI/MenuBarController.swift",
            ]
        ),
        .executableTarget(
            name: "Varal",
            dependencies: ["VaralKit"],
            path: ".",
            exclude: ["Varal/Info.plist"],
            sources: ["Varal/VaralApp.swift"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Varal/Info.plist",
                ])
            ]
        ),
        .testTarget(
            name: "VaralTests",
            dependencies: ["VaralKit"],
            path: "VaralTests"
        ),
    ]
)
