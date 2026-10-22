import Foundation
import Combine

@MainActor
enum AppLaunchState: Equatable {
    case launching
    case preparingLocalData
    case ready
    case degraded(String)

    var canShowMainInterface: Bool {
        switch self {
        case .ready, .degraded:
            true
        case .launching, .preparingLocalData:
            false
        }
    }
}

@MainActor
final class AppLaunchCoordinator: ObservableObject {
    static let shared = AppLaunchCoordinator()

    @Published private(set) var state: AppLaunchState = .launching
    @Published private(set) var isPreparingLongerThanExpected = false

    private var launchTask: Task<Void, Never>?
    private let minimumDisplayNanoseconds: UInt64 = 900_000_000

    private init() {}

    func startIfNeeded() {
        guard launchTask == nil else { return }

        #if DEBUG
        let launchStart = CFAbsoluteTimeGetCurrent()
        WanderlustDiagnostics.info("app_launch_start", category: .performance)
        #endif

        state = .preparingLocalData
        launchTask = Task { [weak self] in
            guard let self else { return }

            async let minimumDisplay: Void = waitMinimumDisplay()
            await prepareMinimalLocalData()
            await minimumDisplay

            guard !Task.isCancelled else { return }
            state = .ready

            #if DEBUG
            WanderlustDiagnostics.info(
                String(format: "app_interactive %.1fms state=%@", (CFAbsoluteTimeGetCurrent() - launchStart) * 1000, String(describing: state)),
                category: .performance
            )
            #endif
        }
    }

    func cancelTransientWork() {
        launchTask?.cancel()
        launchTask = nil
    }

    private func waitMinimumDisplay() async {
        try? await Task.sleep(nanoseconds: minimumDisplayNanoseconds)
    }

    private func prepareMinimalLocalData() async {
        _ = TripStore.shared
        await GeoJSONLoader.shared.loadIfNeededAsync()
        isPreparingLongerThanExpected = false
    }
}

@MainActor
enum WanderlustBackgroundMaintenance {
    static func runProcessingTask() async -> Bool {
        return true
    }

    static func runBackgroundFetch() async -> Bool {
        await TripStore.shared.performDeferredCloudSync()
    }

    static func runRemoteNotificationSync() async -> Bool {
        await TripStore.shared.performDeferredCloudSync()
    }

    static func releaseTransientStaticData() {
        CityDataLoader.shared.releaseMemory()
        AirportDataLoader.shared.releaseMemory()
        AirlineDataLoader.shared.releaseMemory()
        RouteDataStore.shared.releaseMemory()
        GeoJSONLoader.shared.releaseMemory()
    }

}
