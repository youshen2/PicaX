import Foundation

enum AppVersion {
    static func compare(_ lhs: String, to rhs: String) -> ComparisonResult {
        let lhsParts = normalizedParts(lhs)
        let rhsParts = normalizedParts(rhs)
        let count = max(lhsParts.count, rhsParts.count)

        for index in 0..<count {
            let lhsValue = index < lhsParts.count ? lhsParts[index] : 0
            let rhsValue = index < rhsParts.count ? rhsParts[index] : 0

            if lhsValue < rhsValue { return .orderedAscending }
            if lhsValue > rhsValue { return .orderedDescending }
        }

        return .orderedSame
    }

    static func isEquivalent(_ lhs: String, to rhs: String) -> Bool {
        compare(lhs, to: rhs) == .orderedSame
    }

    static func displayName(for version: String) -> String {
        let trimmedVersion = version.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedVersion.lowercased().hasPrefix("v") else {
            return trimmedVersion
        }
        return String(trimmedVersion.dropFirst())
    }

    private static func normalizedParts(_ version: String) -> [Int] {
        version
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "v"))
            .split { !$0.isNumber }
            .compactMap { Int($0) }
    }
}

extension Bundle {
    var appVersion: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    var appBuildNumber: String {
        object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }
}
