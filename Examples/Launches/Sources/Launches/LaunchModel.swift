// A model file as apps write them: Foundation and Combine imported beside SwiftUI, an
// ObservableObject with @Published properties and a PassthroughSubject sent from a nonisolated
// method, UserDefaults, FileManager and JSONEncoder for its records, DispatchQueue for a delay.
import Foundation
import Combine
import SwiftUI

struct Launch: Codable, Equatable {
    var number: Int
    var date: Date
}

final class LaunchModel: ObservableObject {
    @Published var launches: [Launch] = []
    @Published var status = "starting"
    let events = PassthroughSubject<String, Never>()
    private var subscriptions = Set<AnyCancellable>()

    private let defaults = UserDefaults.standard
    private var file: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("launches.json") }

    init() {
        events.map { "event: \($0)" }.removeDuplicates().sink { [weak self] in self?.status = $0 }.store(in: &subscriptions)
    }

    /// Records this launch: the count in the defaults, the list in a document, both durable.
    func record() {
        let number = defaults.integer(forKey: "launches") + 1
        defaults.set(number, forKey: "launches")
        if let data = try? Data(contentsOf: file), let kept = try? JSONDecoder().decode([Launch].self, from: data) { launches = kept }
        launches.append(Launch(number: number, date: Date()))
        if let data = try? JSONEncoder().encode(launches) { try? data.write(to: file) }
        events.send("recorded \(number)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.events.send("settled \(number)") }
    }

    var summary: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        let last = launches.last.map { formatter.string(from: Double($0.number)) ?? "\($0.number)" } ?? "none"
        return "launch \(last), \(launches.count) on file, log2(8) = \(log2(8.0)), \(Bundle.main.bundlePath)"
    }
}
