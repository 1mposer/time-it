import Foundation
@testable import TimeIt

// Shared test fixtures. JSON shapes mirror the backend contract in CLAUDE.md
// ("API response contract") — field names and optionality must not drift from it.
enum Fixtures {

    static func hourJSON(index: Int,
                         temp: Double = 24,
                         humidity: Double = 40,
                         windSpeed: String = "10",
                         rainFall: String = "0",
                         cloudCover: String = "15") -> String {
        """
        {
          "index": \(index),
          "temp": \(temp),
          "humidity": \(humidity),
          "windSpeed": \(windSpeed),
          "rainFall": \(rainFall),
          "cloudCover": \(cloudCover),
          "visibility": 10,
          "moon": ["waxing crescent"],
          "uV": 3,
          "dustAlert": false,
          "darkness": 0,
          "douglasScale": 0,
          "swellHeight": 0,
          "swellLength": 0,
          "tide": 0,
          "seaWarning": false
        }
        """
    }

    static let windowedDayJSON = """
    { "dayIndex": 0, "rating": "perfect", "startIndex": 3, "endIndex": 9, "duration": 6 }
    """

    static let nullDayJSON = """
    { "dayIndex": 1, "rating": null }
    """

    /// An activity whose days[] has `count` entries: day 0 windowed ("perfect"),
    /// day 2 windowed ("good", global indices > 24), the rest null.
    static func activityJSON(id: String = "cycling", label: String = "Cycling", dayCount: Int) -> String {
        let days = (0..<dayCount).map { i -> String in
            switch i {
            case 0: return #"{ "dayIndex": 0, "rating": "perfect", "startIndex": 3, "endIndex": 9, "duration": 6 }"#
            case 2: return #"{ "dayIndex": 2, "rating": "good", "startIndex": 52, "endIndex": 55, "duration": 3 }"#
            default: return #"{ "dayIndex": \#(i), "rating": null }"#
            }
        }.joined(separator: ",\n")
        return """
        {
          "activityId": "\(id)",
          "label": "\(label)",
          "displayMetrics": ["temp", "windSpeed"],
          "days": [\(days)]
        }
        """
    }

    static func forecastResponseJSON(hourCount: Int = 60) -> String {
        let hours = (0..<hourCount).map { i in
            // hour 1 exercises the nullable trio (provider omitted the fields → JSON null)
            hourJSON(index: i,
                     windSpeed: i == 1 ? "null" : "10",
                     rainFall: i == 1 ? "null" : "0",
                     cloudCover: i == 1 ? "null" : "15")
        }.joined(separator: ",\n")
        return """
        {
          "forecastStart": "2026-06-19T12:00:00Z",
          "timezone": "Asia/Dubai",
          "activities": [
            \(activityJSON(id: "cycling", label: "Cycling", dayCount: 7)),
            \(activityJSON(id: "fishing-lite", label: "Fishing Lite", dayCount: 8))
          ],
          "hours": [\(hours)]
        }
        """
    }

    static func decodeForecast(hourCount: Int = 60) throws -> ForecastResponse {
        try JSONDecoder().decode(ForecastResponse.self, from: Data(forecastResponseJSON(hourCount: hourCount).utf8))
    }

    // MARK: - In-memory model builders (for ViewModel tests)

    static func makeHour(index: Int,
                         temp: Double = 24,
                         humidity: Double = 40,
                         visibility: Double = 10,
                         uV: Double = 3,
                         windSpeed: Double? = 10,
                         rainFall: Double? = 0,
                         cloudCover: Double? = 15) -> HourlyWeather {
        HourlyWeather(index: index,
                      temp: temp,
                      humidity: humidity,
                      visibility: visibility,
                      uV: uV,
                      windSpeed: windSpeed,
                      rainFall: rainFall,
                      cloudCover: cloudCover,
                      moon: ["waxing crescent"],
                      dustAlert: false,
                      seaWarning: false,
                      darkness: 0,
                      douglasScale: 0,
                      swellHeight: 0,
                      swellLength: 0,
                      tide: 0)
    }

    static func makeDay(dayIndex: Int,
                        rating: String? = nil,
                        startIndex: Int? = nil,
                        endIndex: Int? = nil,
                        duration: Int? = nil) -> Day {
        Day(dayIndex: dayIndex, rating: rating, startIndex: startIndex, endIndex: endIndex, duration: duration)
    }

    static func makeActivity(id: String = "cycling", label: String = "Cycling", days: [Day]) -> ActivityRating {
        ActivityRating(activityId: id, label: label, displayMetrics: ["temp", "windSpeed"], days: days)
    }

    static func makeForecast(activities: [ActivityRating], hourCount: Int = 60) -> ForecastResponse {
        ForecastResponse(forecastStart: "2026-06-19T12:00:00Z",
                         timezone: "Asia/Dubai",
                         activities: activities,
                         hours: (0..<hourCount).map { makeHour(index: $0) })
    }
}
