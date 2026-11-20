import AuthenticationServices
import CryptoKit
import Foundation
import UIKit
import Security

@MainActor
final class OutlookOAuth: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    @Published private(set) var isConnected = false
    @Published private(set) var accountEmail: String?

    private let clientID = "62607893-1546-469f-8fa0-79f43c10e7c0"
    private let redirectURI = "msauth.com.example.ApplePickupTracker://auth"
    private let callbackScheme = "msauth.com.example.ApplePickupTracker"
    private let authority = "https://login.microsoftonline.com/consumers"
    private let scope = "openid profile email offline_access https://graph.microsoft.com/Mail.Read https://graph.microsoft.com/User.Read"
    private var session: ASWebAuthenticationSession?
    private var verifier = ""
    private var state = ""
    private let accessKey = "outlook_access_token"
    private let refreshKey = "outlook_refresh_token"
    private let expiryKey = "outlook_token_expiry"

    private var accessToken: String? { Keychain.read(accessKey) }
    private var refreshToken: String? { Keychain.read(refreshKey) }

    override init() {
        super.init()
        isConnected = refreshToken != nil
    }

    func connect() async throws {
        verifier = Self.randomString(count: 64)
        state = Self.randomString(count: 32)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
        var components = URLComponents(string: "\(authority)/oauth2/v2.0/authorize")!
        components.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "response_mode", value: "query"),
            .init(name: "scope", value: scope),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state)
        ]
        guard let url = components.url else { throw OutlookError.invalidURL }
        let callback = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let auth = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { callbackURL, error in
                if let error { continuation.resume(throwing: error); return }
                guard let callbackURL else { continuation.resume(throwing: OutlookError.invalidCallback); return }
                continuation.resume(returning: callbackURL)
            }
            auth.presentationContextProvider = self
            auth.prefersEphemeralWebBrowserSession = false
            session = auth
            if !auth.start() { continuation.resume(throwing: OutlookError.authorizationUnavailable) }
        }
        guard let parts = URLComponents(url: callback, resolvingAgainstBaseURL: false),
              parts.queryItems?.first(where: { $0.name == "state" })?.value == state else {
            throw OutlookError.invalidCallback
        }
        if let error = parts.queryItems?.first(where: { $0.name == "error" })?.value {
            let description = parts.queryItems?.first(where: { $0.name == "error_description" })?.value ?? error
            throw OutlookError.authorizationFailed(description)
        }
        guard let code = parts.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw OutlookError.invalidCallback
        }
        try await exchange(code: code)
        isConnected = true
        accountEmail = try? await fetchProfileEmail()
    }

    func validAccessToken() async throws -> String {
        if let token = accessToken,
           let expiry = UserDefaults.standard.object(forKey: expiryKey) as? Date,
           expiry > Date().addingTimeInterval(60) { return token }
        guard let refreshToken else { throw OutlookError.notConnected }
        let response = try await postToken([
            "client_id": clientID,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "scope": scope
        ])
        try storeTokens(response)
        guard let token = response["access_token"] as? String else { throw OutlookError.tokenExchangeFailed }
        return token
    }

    func disconnect() {
        Keychain.delete(accessKey)
        Keychain.delete(refreshKey)
        UserDefaults.standard.removeObject(forKey: expiryKey)
        isConnected = false
        accountEmail = nil
    }

    private func exchange(code: String) async throws {
        let response = try await postToken([
            "client_id": clientID,
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "code_verifier": verifier,
            "scope": scope
        ])
        try storeTokens(response)
        guard response["access_token"] is String else { throw OutlookError.tokenExchangeFailed }
    }

    private func postToken(_ values: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "\(authority)/oauth2/v2.0/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = values.map {
            let key = $0.key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.key
            let value = $0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value
            return "\(key)=\(value)"
        }.joined(separator: "&").data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let message = json["error_description"] as? String ?? "HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)"
            throw OutlookError.tokenRequestFailed(message)
        }
        return json
    }

    private func storeTokens(_ response: [String: Any]) throws {
        guard let token = response["access_token"] as? String else { throw OutlookError.tokenExchangeFailed }
        Keychain.write(token, for: accessKey)
        if let refresh = response["refresh_token"] as? String { Keychain.write(refresh, for: refreshKey) }
        if let expires = response["expires_in"] as? Double {
            UserDefaults.standard.set(Date().addingTimeInterval(expires - 90), forKey: expiryKey)
        }
    }

    private func fetchProfileEmail() async throws -> String? {
        let token = try await validAccessToken()
        var request = URLRequest(url: URL(string: "https://graph.microsoft.com/v1.0/me?$select=mail,userPrincipalName")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (json?["mail"] as? String) ?? (json?["userPrincipalName"] as? String)
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
    }

    private static func randomString(count: Int) -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return String((0..<count).compactMap { _ in alphabet.randomElement() })
    }
}

enum OutlookError: LocalizedError {
    case invalidURL, invalidCallback, authorizationUnavailable, tokenExchangeFailed, notConnected
    case authorizationFailed(String), tokenRequestFailed(String), apiFailure(status: Int, message: String)
    var errorDescription: String? {
        switch self {
        case .invalidURL: "无法创建 Microsoft 登录地址。"
        case .invalidCallback: "Microsoft 登录回调无效，请重试。"
        case .authorizationUnavailable: "无法启动 Microsoft 登录页面。"
        case .tokenExchangeFailed: "Microsoft 登录令牌交换失败。"
        case .notConnected: "尚未连接 Outlook。"
        case let .authorizationFailed(message): "Microsoft 授权失败：\(message)"
        case let .tokenRequestFailed(message): "Microsoft Token 请求失败：\(message)"
        case let .apiFailure(status, message): "Outlook API 错误（HTTP \(status)）：\(message)"
        }
    }
}

private enum Keychain {
    static func write(_ value: String, for key: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key]
        SecItemDelete(query as CFDictionary)
        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(insert as CFDictionary, nil)
    }
    static func read(_ key: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key,
                                    kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func delete(_ key: String) {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key] as CFDictionary)
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
