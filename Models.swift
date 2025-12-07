import Foundation

// MARK: - Feature
public struct Feature: Codable, Equatable {
    public let color: String?
    public let pattern: String?
    public let material: String?
    public let warmthLevel: Int?
    public let isRainOk: Bool?
    public let seasons: [String]?
    
    // 追加: Pythonのスネークケースに対応させる
    enum CodingKeys: String, CodingKey {
        case color, pattern, material, seasons
        case warmthLevel = "warmth_level"
        case isRainOk = "is_rain_ok"
    }
}

// MARK: - Cloth
public struct Cloth: Codable, Identifiable, Equatable {
    public let id: UUID 
    public let imageURL: String 
    public let category: String
    public let features: Feature?
    
    enum CodingKeys: String, CodingKey {
        case id = "cloth_id"
        case imageURL = "image_url"
        case category
        case features
    }
}

// MARK: - Recommendation
public struct Recommendation: Codable, Equatable {
    public let clothes: [Cloth]
    public let reason: String
}

// MARK: - Weather
public struct Weather: Codable, Equatable {
    public let tempC: Double
    public let weather: String
    
    enum CodingKeys: String, CodingKey {
        case tempC = "temp_c"
        case weather
    }
}