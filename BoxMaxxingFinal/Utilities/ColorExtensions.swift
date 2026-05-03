import SwiftUI

// MARK: - MovementState

enum MovementState: Equatable {
    case excellent      // 🟢 85-100%
    case fair           // 🟡 50-84%
    case poor           // 🔴 0-49%
    case noScan         // ⚠️ body not detected
    case noMovement     // ❌ model returned unknown

    var color: Color {
        switch self {
        case .excellent:                        return Color(UIColor.systemGreen)
        case .fair:                             return Color(UIColor.systemYellow)
        case .poor, .noScan, .noMovement:       return Color(UIColor.systemRed)
        }
    }

    var label: String {
        switch self {
        case .excellent:  return "Excellent"
        case .fair:       return "Fair"
        case .poor:       return "Poor"
        case .noScan:     return "No Scan"
        case .noMovement: return "No Movement"
        }
    }

    var isClipSaved: Bool { self != .excellent }
}

// MARK: - Color Helpers

extension Color {
    static func performanceColor(for confidence: Float) -> Color {
        let pct = confidence * 100
        if pct >= 85 { return Color(UIColor.systemGreen) }
        if pct >= 50 { return Color(UIColor.systemYellow) }
        return Color(UIColor.systemRed)
    }

    static func performanceLabel(for confidence: Float) -> String {
        let pct = confidence * 100
        if pct >= 85 { return "Excellent" }
        if pct >= 50 { return "Fair" }
        return "Poor"
    }
}
