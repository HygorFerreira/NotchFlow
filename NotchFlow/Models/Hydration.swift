import Foundation

struct WaterIntake: Identifiable, Codable, Equatable {
    var id = UUID()
    let milliliters: Int
    let container: HydrationSettings.Container
    var recordedAt: Date = Date()
}

struct HydrationSettings: Codable, Equatable {
    enum Container: String, Codable, CaseIterable, Identifiable {
        case glass, bottle
        var id: Self { self }
        var title: String { self == .glass ? "Glass" : "Bottle" }
        var symbol: String { self == .glass ? "mug" : "waterbottle" }
    }

    var container: Container = .glass
    var glassMilliliters = 250
    var bottleMilliliters = 500
    var goalMilliliters = 2000
    var servingMilliliters: Int { container == .glass ? glassMilliliters : bottleMilliliters }

    static let capacityRange = 50...3000
    static let goalRange = 250...10000

    /// Accept either decimal separator; reject partial/invalid input rather than saving a stale value.
    static func capacity(from text: String, inLiters: Bool) -> Int? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.range(of: "^[0-9]+([.,][0-9]{1,3})?$", options: .regularExpression) != nil,
              let value = Double(cleaned.replacingOccurrences(of: ",", with: ".")), value.isFinite else { return nil }
        let ml = value * (inLiters ? 1000 : 1)
        guard ml >= Double(capacityRange.lowerBound), ml <= Double(capacityRange.upperBound),
              abs(ml - ml.rounded()) < 0.000001 else { return nil }
        return Int(ml.rounded())
    }

    init() {}

    private enum CodingKeys: String, CodingKey {
        case container, glassMilliliters, bottleMilliliters, goalMilliliters
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        container = try values.decodeIfPresent(Container.self, forKey: .container) ?? .glass
        glassMilliliters = min(3000, max(50, try values.decodeIfPresent(Int.self, forKey: .glassMilliliters) ?? 250))
        bottleMilliliters = min(3000, max(50, try values.decodeIfPresent(Int.self, forKey: .bottleMilliliters) ?? 500))
        goalMilliliters = min(10000, max(250, try values.decodeIfPresent(Int.self, forKey: .goalMilliliters) ?? 2000))
    }
}
