import Foundation
import Combine

/// Shared destinations for the main workspace and optional standalone windows.
enum WorkspaceDestination: String, CaseIterable, Identifiable {
    case tasks = "Tasks", medications = "Medications", water = "Water", summary = "Weekly summary", ai = "AI usage"
    var id: Self { self }
    var symbol: String {
        switch self {
        case .tasks: return "checklist"
        case .medications: return "pills.fill"
        case .water: return "drop.fill"
        case .summary: return "chart.bar"
        case .ai: return "sparkles"
        }
    }
}

/// Visit screens lazily, then retain their view identities while navigating.
@MainActor
final class WorkspaceNavigation: ObservableObject {
    @Published private(set) var destination: WorkspaceDestination = .tasks
    @Published private(set) var visited: Set<WorkspaceDestination> = [.tasks]

    func select(_ destination: WorkspaceDestination) {
        visited.insert(destination)
        self.destination = destination
    }
}
