import Foundation

struct APIEnvelope<T: Decodable>: Decodable {
    let success: Bool?
    let data: T?
    let message: String?
}

struct APIErrorPayload: Decodable {
    let success: Bool?
    let message: String?
    let errors: [String: [String]]?
}

enum APIError: LocalizedError, Equatable {
    case invalidURL
    case unauthorized(String)
    case server(String)
    case network(String)
    case decoding
    case cancelled

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "服务器地址无效，请到「服务器设置」中修改"
        case .unauthorized(let message):
            return message
        case .server(let message):
            return message
        case .network(let message):
            return "网络连接失败：\(message)"
        case .decoding:
            return "数据解析失败，请稍后再试"
        case .cancelled:
            return "请求已取消"
        }
    }

    var isUnauthorized: Bool {
        if case .unauthorized = self {
            return true
        }
        return false
    }

    var isCancelled: Bool {
        if case .cancelled = self {
            return true
        }
        return false
    }
}

/// 统一的网络层。所有请求都带 Accept: application/json；
/// 登录后自动附加 Authorization: Bearer <token>。
@MainActor
final class APIClient {
    static let shared = APIClient()

    var token: String?

    private let session: URLSession
    private let decoder = JSONDecoder()

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 60
        configuration.waitsForConnectivity = true
        configuration.httpAdditionalHeaders = ["Accept": "application/json"]
        session = URLSession(configuration: configuration)
    }

    func get<T: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> T {
        let request = try makeRequest(path: path, method: "GET", query: query, body: nil)
        return try await perform(request)
    }

    func post<T: Decodable>(_ path: String, body: [String: Any]? = nil) async throws -> T {
        let request = try makeRequest(path: path, method: "POST", query: [:], body: body)
        return try await perform(request)
    }

    func postVoid(_ path: String, body: [String: Any]? = nil) async throws {
        let request = try makeRequest(path: path, method: "POST", query: [:], body: body)
        _ = try await send(request)
    }

    private func makeRequest(
        path: String,
        method: String,
        query: [String: String],
        body: [String: Any]?
    ) throws -> URLRequest {
        let base = AppConfig.shared.baseURLString
        let full = path.hasPrefix("/") ? base + path : base + "/" + path

        guard var components = URLComponents(string: full) else {
            throw APIError.invalidURL
        }

        if !query.isEmpty {
            components.queryItems = query
                .sorted { $0.key < $1.key }
                .map { URLQueryItem(name: $0.key, value: $0.value) }
        }

        guard let url = components.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        return request
    }

    @discardableResult
    private func send(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw APIError.cancelled
        } catch let error as URLError {
            throw APIError.network(error.localizedDescription)
        } catch {
            throw APIError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.network("服务器无响应")
        }

        if http.statusCode == 401 {
            let message = (try? decoder.decode(APIErrorPayload.self, from: data))?.message
            throw APIError.unauthorized(message ?? "登录已过期，请重新登录")
        }

        guard (200..<300).contains(http.statusCode) else {
            if let payload = try? decoder.decode(APIErrorPayload.self, from: data) {
                let firstFieldError = payload.errors?
                    .values
                    .compactMap { $0.first }
                    .first

                throw APIError.server(firstFieldError ?? payload.message ?? "请求失败")
            }

            throw APIError.server("服务器错误（\(http.statusCode)）")
        }

        return data
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data = try await send(request)

        do {
            let envelope = try decoder.decode(APIEnvelope<T>.self, from: data)

            if envelope.success == false {
                throw APIError.server(envelope.message ?? "请求失败")
            }

            guard let payload = envelope.data else {
                throw APIError.server(envelope.message ?? "服务器返回数据为空")
            }

            return payload
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.decoding
        }
    }
}

struct HealthResponse: Decodable {
    let status: String
    let name: String?
    let time: String?
}
