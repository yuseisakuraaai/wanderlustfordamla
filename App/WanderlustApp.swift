//
//  WanderlustApp.swift
//  Wanderlust
//
//  Created by Yusei Sakurai on 2026/07/14.
//

import SwiftUI
import UIKit
#if canImport(BackgroundTasks)
import BackgroundTasks
#endif
#if canImport(FirebaseCore)
import FirebaseCore
#endif
#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

#if canImport(FirebaseCore)
final class AppDelegate: NSObject, UIApplicationDelegate {
    private let processingTaskIdentifier = "com.yusei.Wanderlust.processing"
    private let appRefreshTaskIdentifier = "com.yusei.Wanderlust.refresh"

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        registerBackgroundTasksIfNeeded()
        // 広告の同意取得・ATT・SDK 起動は AdConsentCoordinator が順序を管理する。
        // ATT のダイアログはアプリが active でないと表示されないため、
        // ここでは開始せず、画面が出てから ContentView 側で呼ぶ。
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
            configureFirestoreIfAvailable()
            #if DEBUG
            WanderlustDiagnostics.info("FirebaseApp configured", category: .auth)
            #endif
        } else {
            #if DEBUG
            WanderlustDiagnostics.info("FirebaseApp already configured", category: .auth)
            #endif
        }
        return true
    }

    func application(
        _ application: UIApplication,
        shouldSaveSecureApplicationState coder: NSCoder
    ) -> Bool {
        false
    }

    func application(
        _ application: UIApplication,
        shouldRestoreSecureApplicationState coder: NSCoder
    ) -> Bool {
        false
    }

    private func configureFirestoreIfAvailable() {
        #if canImport(FirebaseFirestore)
        let settings = Firestore.firestore().settings
        settings.cacheSettings = PersistentCacheSettings()
        Firestore.firestore().settings = settings
        WanderlustDiagnostics.info("Firestore persistent cache configured", category: .sync)
        #endif
    }

    private func registerBackgroundTasksIfNeeded() {
        #if canImport(BackgroundTasks)
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: processingTaskIdentifier,
            using: nil
        ) { task in
            guard let processingTask = task as? BGProcessingTask else {
                task.setTaskCompleted(success: true)
                return
            }
            self.handleProcessingTask(processingTask)
        }
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: appRefreshTaskIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: true)
                return
            }
            self.handleAppRefreshTask(refreshTask)
        }
        #endif
    }

    #if canImport(BackgroundTasks)
    private func handleProcessingTask(_ task: BGProcessingTask) {
        let processing = Task(priority: .utility) {
            let success = await WanderlustBackgroundMaintenance.runProcessingTask()
            await MainActor.run {
                task.setTaskCompleted(success: success)
            }
        }

        task.expirationHandler = {
            processing.cancel()
            task.setTaskCompleted(success: false)
        }
    }

    private func handleAppRefreshTask(_ task: BGAppRefreshTask) {
        scheduleAppRefresh()
        let refresh = Task(priority: .utility) {
            let success = await WanderlustBackgroundMaintenance.runBackgroundFetch()
            await MainActor.run {
                task.setTaskCompleted(success: success)
            }
        }

        task.expirationHandler = {
            refresh.cancel()
            task.setTaskCompleted(success: false)
        }
    }
    #endif

    func applicationDidEnterBackground(_ application: UIApplication) {
        scheduleBackgroundProcessing()
        scheduleAppRefresh()
    }

    func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
        Task { @MainActor in
            WanderlustBackgroundMaintenance.releaseTransientStaticData()
        }
    }

    func application(
        _ application: UIApplication,
        performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        Task { @MainActor in
            let success = await WanderlustBackgroundMaintenance.runBackgroundFetch()
            completionHandler(success ? .newData : .noData)
        }
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        Task { @MainActor in
            let success = await WanderlustBackgroundMaintenance.runRemoteNotificationSync()
            completionHandler(success ? .newData : .noData)
        }
    }

    private func scheduleBackgroundProcessing() {
        #if canImport(BackgroundTasks)
        let request = BGProcessingTaskRequest(identifier: processingTaskIdentifier)
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: 20 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            WanderlustDiagnostics.warning("background processing submit skipped: \(error.localizedDescription)", category: .performance)
        }
        #endif
    }

    private func scheduleAppRefresh() {
        #if canImport(BackgroundTasks)
        let request = BGAppRefreshTaskRequest(identifier: appRefreshTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            WanderlustDiagnostics.warning("app refresh submit skipped: \(error.localizedDescription)", category: .sync)
        }
        #endif
    }

}
#endif

@main
struct WanderlustApp: App {
    #if canImport(FirebaseCore)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif

    init() {
        UITabBar.appearance().tintColor = .systemBlue
        UITabBar.appearance().unselectedItemTintColor = .label
    }

    var body: some Scene {
        WindowGroup {
            RootLaunchView()
        }
    }
}

private struct RootLaunchView: View {
    @AppStorage("atlas.hasCompletedOnboarding")
    private var hasCompletedOnboarding = false

    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var launchCoordinator = AppLaunchCoordinator.shared
    @State private var isShowingLaunchSplash = true
    @AppStorage("atlas.appearance") private var appearance = WanderlustAppearance.system.rawValue

    private var selectedColorScheme: ColorScheme? {
        WanderlustAppearance(rawValue: appearance)?.colorScheme
    }

    var body: some View {
        ZStack {
            if launchCoordinator.state.canShowMainInterface {
                mainInterface
            } else {
                Color("WanderlustLaunchBackground")
                    .ignoresSafeArea()
            }

            if isShowingLaunchSplash {
                WanderlustLaunchSplash(
                    isPreparingLongerThanExpected: launchCoordinator.isPreparingLongerThanExpected,
                    isExiting: launchCoordinator.state.canShowMainInterface
                )
                .transition(.opacity)
                .zIndex(10)
            }
        }
        .preferredColorScheme(selectedColorScheme)
        .animation(.easeInOut(duration: 0.25), value: launchCoordinator.state.canShowMainInterface)
        .onAppear {
            launchCoordinator.startIfNeeded()
        }
        .task {
            // 同意取得 → ATT → Mobile Ads SDK 起動の順に進める。
            // ATT のダイアログはアプリが active でないと表示されないため、
            // AppDelegate ではなく画面表示後に開始する。
            await AdConsentCoordinator.shared.start()
        }
        .onChange(of: launchCoordinator.state.canShowMainInterface) { _, canShowMainInterface in
            guard canShowMainInterface, isShowingLaunchSplash else { return }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 850_000_000)
                withAnimation(.easeOut(duration: 0.18)) {
                    isShowingLaunchSplash = false
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                WanderlustDiagnostics.info("app entered background", category: .performance)
            }
        }
        .onOpenURL { url in
            #if canImport(GoogleSignIn)
            GIDSignIn.sharedInstance.handle(url)
            #endif
        }
    }

    @ViewBuilder
    private var mainInterface: some View {
        if hasCompletedOnboarding {
            ContentView()
                .transition(.opacity)
        } else {
            OnboardingFlowView()
                .transition(.opacity)
        }
    }
}

private struct WanderlustLaunchSplash: View {
    let isPreparingLongerThanExpected: Bool
    let isExiting: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var logoScale = 0.94
    @State private var opacity = 0.0
    @State private var contentOffset: CGFloat = 10

    var body: some View {
        ZStack {
            launchBackground
                .ignoresSafeArea()

            VStack(spacing: 24) {
                WanderlustBrandMark(size: 132, cornerRadius: 30, shadowOpacity: colorScheme == .dark ? 0.34 : 0.16)
                    .scaleEffect(logoScale)

                VStack(spacing: 8) {
                    WanderlustBrandTitle(size: 40, color: primaryTextColor)
                    WanderlustBrandSubtitle(color: secondaryTextColor)
                }

                if isPreparingLongerThanExpected {
                    ProgressView()
                        .padding(.top, 8)
                        .transition(.opacity)
                        .accessibilityLabel(WanderlustL10n.string("Preparing map data", table: .world))
                }
            }
            .offset(y: contentOffset)
            .opacity(opacity)
        }
        .onAppear {
            let animation: Animation = reduceMotion
                ? .easeInOut(duration: 0.25)
                : .easeOut(duration: 0.55)
            withAnimation(animation) {
                logoScale = 1
                opacity = 1
                contentOffset = 0
            }
        }
        .onChange(of: isExiting) { _, newValue in
            guard newValue else { return }
            withAnimation(.easeInOut(duration: reduceMotion ? 0.25 : 0.35)) {
                opacity = 0
                logoScale = 0.98
                contentOffset = -6
            }
        }
    }

    private var launchBackground: Color {
        Color("WanderlustLaunchBackground")
    }

    private var primaryTextColor: Color {
        colorScheme == .dark
            ? Color(red: 0.94, green: 0.95, blue: 0.96)
            : Color(red: 0.18, green: 0.13, blue: 0.08)
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark
            ? Color(red: 0.70, green: 0.72, blue: 0.74)
            : Color(red: 0.46, green: 0.36, blue: 0.24)
    }
}

struct WanderlustBrandTitle: View {
    let size: CGFloat
    let color: Color

    var body: some View {
        Text(verbatim: "Wanderlust")
            .wanderlustFont(size, relativeTo: .largeTitle, weight: .bold, design: .rounded, maxScale: 1.3)
            .foregroundStyle(color)
            .multilineTextAlignment(.center)
            .lineLimit(1)
            .minimumScaleFactor(0.86)
            .tracking(0)
            .padding(.horizontal, 18)
    }
}

struct WanderlustBrandSubtitle: View {
    let color: Color

    var body: some View {
        Text(WanderlustL10n.string("Travel beautifully.", table: .trips))
            .font(.footnote.weight(.medium))
            .foregroundStyle(color)
            .multilineTextAlignment(.center)
            .lineLimit(1)
            .minimumScaleFactor(0.86)
    }
}

struct WanderlustBrandMark: View {
    let size: CGFloat
    let cornerRadius: CGFloat
    let shadowOpacity: Double

    var body: some View {
        Image("WanderlustLaunchIcon")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: .black.opacity(shadowOpacity), radius: size * 0.18, y: size * 0.10)
            .accessibilityHidden(true)
    }
}
