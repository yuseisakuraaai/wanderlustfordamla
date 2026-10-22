import Foundation
import OSLog

#if canImport(FirebaseCrashlytics)
import FirebaseCrashlytics
#endif

enum WanderlustLogCategory: String, CaseIterable {
    case auth
    case sync
    case offline
    case migration
    case search
    case route
    case storage
    case ui
    case performance
}

enum WanderlustDiagnostics {
    nonisolated private static let subsystem = Bundle.main.bundleIdentifier ?? "Wanderlust"

    nonisolated static func logger(_ category: WanderlustLogCategory) -> Logger {
        Logger(subsystem: subsystem, category: category.rawValue)
    }

    nonisolated static func info(_ message: String, category: WanderlustLogCategory) {
        logger(category).info("\(message, privacy: .public)")
    }

    nonisolated static func warning(_ message: String, category: WanderlustLogCategory) {
        logger(category).warning("\(message, privacy: .public)")
    }

    nonisolated static func error(_ error: Error, category: WanderlustLogCategory, message: String, metadata: [String: String] = [:]) {
        let safeMetadata = metadata
            .filter { !$0.key.localizedCaseInsensitiveContains("email") && !$0.key.localizedCaseInsensitiveContains("token") }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        logger(category).error("\(message, privacy: .public) error=\(error.localizedDescription, privacy: .public) \(safeMetadata, privacy: .public)")
        recordNonFatal(error, category: category, message: message, metadata: metadata)
    }

    nonisolated static func recordNonFatal(_ error: Error, category: WanderlustLogCategory, message: String, metadata: [String: String] = [:]) {
        #if canImport(FirebaseCrashlytics)
        #if !DEBUG
        let crashlytics = Crashlytics.crashlytics()
        crashlytics.setCustomValue(category.rawValue, forKey: "wanderlust_category")
        crashlytics.setCustomValue(message, forKey: "wanderlust_message")
        for (key, value) in metadata where !key.localizedCaseInsensitiveContains("email") && !key.localizedCaseInsensitiveContains("token") {
            crashlytics.setCustomValue(value, forKey: key)
        }
        crashlytics.record(error: error)
        #endif
        #endif
    }
}
