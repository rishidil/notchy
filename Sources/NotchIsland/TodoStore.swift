import Foundation

/// A small local to-do list, saved in UserDefaults.
final class TodoStore: ObservableObject {
    struct Item: Identifiable, Codable, Equatable {
        var id = UUID()
        var title: String
        var done = false
        var created = Date()
    }

    @Published private(set) var items: [Item] = []
    private let key = "todoItems"

    var remaining: Int { items.filter { !$0.done }.count }

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([Item].self, from: data) {
            items = saved
        }
    }

    func add(_ title: String) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        items.insert(Item(title: t), at: 0)
        save()
    }

    func toggle(_ item: Item) {
        guard let i = items.firstIndex(of: item) else { return }
        items[i].done.toggle()
        // Finished items sink below open ones.
        items.sort { !$0.done && $1.done }
        save()
    }

    func delete(_ item: Item) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func clearDone() {
        items.removeAll(where: \.done)
        save()
    }

    func applyDemo() {
        items = [
            Item(title: "Send design review notes to Maya"),
            Item(title: "Book flights for the offsite"),
            Item(title: "Water the plants"),
            Item(title: "Finish onboarding slides", done: true),
            Item(title: "Renew passport", done: true),
        ]
    }

    private func save() {
        guard !isDemoMode, let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
