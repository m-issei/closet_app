import Foundation
import UIKit // UIImageのために必要

enum APIError: Error {
    case invalidURL
    case invalidResponse(statusCode: Int)
    case decodingError(Error)
    case unknown(Error)
}

final class APIClient {
    static let shared = APIClient()
    private init() {}

    // ローカル開発用URL (実機の場合はMacのIPアドレスを指定する必要がある場合もあります)
    private let baseURL = URL(string: "http://localhost:8000")!
    
    // ユーザーIDの管理 (初回起動時に生成して保存)
    var currentUserId: UUID {
        if let savedIdString = UserDefaults.standard.string(forKey: "current_user_id"),
           let uuid = UUID(uuidString: savedIdString) {
            return uuid
        }
        let newId = UUID()
        UserDefaults.standard.set(newId.uuidString, forKey: "current_user_id")
        return newId
    }

    private let jsonDecoder: JSONDecoder = {
        let d = JSONDecoder()
        // keyDecodingStrategyは指定せず、CodingKeysで明示的にマッピングする方が安全
        return d
    }()

    // MARK: - Generic Request
    private func request<T: Decodable>(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> T {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw APIError.invalidURL
        }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        if let body = body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, resp) = try await URLSession.shared.data(for: req)
        return try handleResponse(data: data, response: resp)
    }

    private func handleResponse<T: Decodable>(data: Data, response: URLResponse) throws -> T {
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse(statusCode: -1)
        }
        guard (200...299).contains(http.statusCode) else {
            print("API Error Status: \(http.statusCode)")
            if let str = String(data: data, encoding: .utf8) { print("Body: \(str)") }
            throw APIError.invalidResponse(statusCode: http.statusCode)
        }
        do {
            return try jsonDecoder.decode(T.self, from: data)
        } catch {
            print("Decoding Error: \(error)")
            throw APIError.decodingError(error)
        }
    }

    // MARK: - Endpoints

    // バックエンドに GET /clothes が必要です
    func fetchClothes() async throws -> [Cloth] {
        // バックエンド実装完了！
        let path = "/clothes?user_id=\(currentUserId.uuidString)"
        return try await request(path)
    }

    // 画像アップロード (Multipart/form-data)
    func addCloth(image: UIImage, category: String) async throws -> Cloth {
        let url = baseURL.appendingPathComponent("/clothes")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        
        let boundary = UUID().uuidString
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var data = Data()
        
        // 1. user_id
        data.append("--\(boundary)\r\n".data(using: .utf8)!)
        data.append("Content-Disposition: form-data; name=\"user_id\"\r\n\r\n".data(using: .utf8)!)
        data.append("\(currentUserId.uuidString)\r\n".data(using: .utf8)!)
        
        // 2. category
        data.append("--\(boundary)\r\n".data(using: .utf8)!)
        data.append("Content-Disposition: form-data; name=\"category\"\r\n\r\n".data(using: .utf8)!)
        data.append("\(category)\r\n".data(using: .utf8)!)
        
        // 3. file (image)
        if let imageData = image.jpegData(compressionQuality: 0.8) {
            data.append("--\(boundary)\r\n".data(using: .utf8)!)
            data.append("Content-Disposition: form-data; name=\"file\"; filename=\"upload.jpg\"\r\n".data(using: .utf8)!)
            data.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
            data.append(imageData)
            data.append("\r\n".data(using: .utf8)!)
        }
        
        data.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        req.httpBody = data
        
        let (resData, resp) = try await URLSession.shared.data(for: req)
        return try handleResponse(data: resData, response: resp)
    }

    func recommend(latitude: Double, longitude: Double) async throws -> Recommendation {
        let body: [String: Any] = [
            "user_id": currentUserId.uuidString,
            "latitude": latitude,
            "longitude": longitude
        ]
        return try await request("/recommend", method: "POST", body: body)
    }

    func fetchWeather(latitude: Double, longitude: Double) async throws -> Weather {
        // Mock API (FILE 2) doesn't use query params properly yet, usually internal logic
        // But assuming we might want to visualize it or just rely on recommend api internally
        // For now, let's keep request simple or remove if backend doesn't expose standalone weather
        // Assuming backend *could* have GET /weather
        return Weather(tempC: 20.0, weather: "Sunny") // Mock fallback
    }

    func wear(clothIds: [UUID]) async throws {
        let body: [String: Any] = [
            "user_id": currentUserId.uuidString,
            "cloth_ids": clothIds.map { $0.uuidString }
        ]
        // Backend returns generic JSON, ignore response content
        let _: EmptyResponse = try await request("/wear", method: "POST", body: body)
    }
}

private struct EmptyResponse: Decodable {}