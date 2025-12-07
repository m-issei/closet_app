import Foundation
import Combine

@MainActor
final class WardrobeViewModel: ObservableObject {
    enum LoadState: Equatable {
        case idle
        case loading
        case success
        case error(String)
    }

    @Published private(set) var clothes: [Cloth] = []
    @Published var state: LoadState = .idle

    private let api = APIClient.shared

    func loadClothes() async {
        state = .loading
        do {
            let list = try await api.fetchClothes()
            self.clothes = list
            state = .success
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    func addCloth(image: UIImage, category: String) async {
        state = .loading
        do {
            // UIImageを直接渡す
            let created = try await api.addCloth(image: image, category: category)
            self.clothes.append(created)
            state = .success
        } catch {
            print("Error: \(error)")
            state = .error(error.localizedDescription)
        }
    }
}
