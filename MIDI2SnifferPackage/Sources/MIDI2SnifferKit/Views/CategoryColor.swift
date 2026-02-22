// CategoryColor.swift — Color coding for message categories

import SwiftUI

func categoryColor(_ category: MessageCategory) -> Color {
    switch category {
    case .note: return .primary
    case .cc: return .blue
    case .pc: return .orange
    case .pitchBend: return .cyan
    case .pressure: return .purple
    case .ci: return .yellow
    case .pe: return .green
    case .system: return .gray
    case .unknown: return .red
    }
}
