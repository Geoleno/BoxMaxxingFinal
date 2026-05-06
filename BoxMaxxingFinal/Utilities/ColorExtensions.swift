import SwiftUI

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
