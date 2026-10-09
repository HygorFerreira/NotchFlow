import Foundation

struct Medication: Identifiable, Codable, Hashable {
    static let nameLimit = 100
    static let dosageLimit = 100

    var id: UUID = UUID()
    var name: String
    var dosage: String
    var reminderTimes: [Date]
    var isEnabled: Bool = true
    var createdAt: Date = Date()

    var sortedReminderTimes: [Date] {
        reminderTimes.sorted()
    }
}

struct MedicationIntake: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var medicationID: UUID
    var medicationName: String
    var dosage: String
    var takenAt: Date = Date()
}
