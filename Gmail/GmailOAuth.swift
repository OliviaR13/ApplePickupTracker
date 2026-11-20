import AuthenticationServices
import CryptoKit
import Foundation
import UIKit
import Security

@MainActor
final class GmailOAuth: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    @Published private(set) var isConnected = false
    @Published private(set) var accountEmail: String?

    private let clientID = "963422500853-ngfp095nepkeklena1ul1vtpp2sddt44.apps.googleusercontent.com"
    private let redirectScheme = "com.googleusercontent.apps.963422500853-ngfp095nepkeklena1ul1vtpp2sddt44"
    private let scope = "https://www.googleapis.com/auth/gmail.readonly"
    private var session: ASWebAuthenticationSession?
    private var verifier = ""
    private var state = ""
    private let tokenKey = "gmail_access_token"
    private let refreshKey = "gmail_refresh_token"
    private var accessToken: String? { Keychain.read(tokenKey) }
    private var refreshToken: String? { Keychain.read(refreshKey) }

    override init() {
        super.init()
        isConnected = refreshToken != nil
    }

    func connect() async throws {
        guard !clientID.hasPrefix("YOUR_") else { throw GmailError.missingOAuthConfiguration }
        verifier = Self.randomString(count: 64)
        state = Self.randomString(count: 32)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: "\(redirectScheme):/oauth2redirect"),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: "openid email \(scope)"),
            .init(name: "access_type", value: "offline"),
            .init(name: "prompt", value: "consent"),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state)
        ]
        guard let url = components.url else { throw GmailError.invalidURL }
        let callback = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let auth = ASWebAuthenticationSession(url: url, callbackURLScheme: redirectScheme) { callbackURL, error in
                if let error { continuation.resume(throwing: error); return }
                guard let callbackURL else { continuation.resume(throwing: GmailError.invalidCallback); return }
                continuation.resume(returning: callbackURL)
            }
            auth.presentationContextProvider = self
            auth.prefersEphemeralWebBrowserSession = false
            session = auth
            auth.start()
        }
        guard let parts = URLComponents(url: callback, resolvingAgainstBaseURL: false),
              parts.queryItems?.first(where: { $0.name == "state" })?.value == state,
              let code = parts.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw GmailError.invalidCallback
        }
        try await exchange(code: code)
        isConnected = true
        accountEmail = try? await fetchProfileEmail()
    }

    func validAccessToken() async throws -> String {
        if let accessToken,
           let expiry = UserDefaults.standard.object(forKey: "gmail_token_expiry") as? Date,
           expiry > Date() {
            return accessToken
        }
        guard let refreshToken else { throw GmailError.notConnected }
        let body = ["client_id": clientID, "refresh_token": refreshToken, "grant_type": "refresh_token"]
        let response = try await postToken(body)
        guard let token = response["access_token"] as? String else { throw GmailError.tokenExchangeFailed }
        Keychain.write(token, for: tokenKey)
        return token
    }

    func disconnect() {
        Keychain.delete(tokenKey); Keychain.delete(refreshKey)
        isConnected = false; accountEmail = nil
    }

    private func exchange(code: String) async throws {
        let response = try await postToken(["client_id": clientID, "code": code,
                                            "code_verifier": verifier,
                                            "redirect_uri": "\(redirectScheme):/oauth2redirect",
                                            "grant_type": "authorization_code"])
        guard let token = response["access_token"] as? String else { throw GmailError.tokenExchangeFailed }
        Keychain.write(token, for: tokenKey)
        if let refresh = response["refresh_token"] as? String { Keychain.write(refresh, for: refreshKey) }
    }

    private func postToken(_ values: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = values.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }.joined(separator: "&").data(using: .utf8)
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw GmailError.tokenExchangeFailed }
        if let expires = json["expires_in"] as? Double, let token = json["access_token"] as? String {
            Keychain.write(token, for: tokenKey)
            UserDefaults.standard.set(Date().addingTimeInterval(expires - 60), forKey: "gmail_token_expiry")
        }
        return json
    }

    private func fetchProfileEmail() async throws -> String? {
        let token = try await validAccessToken()
        var request = URLRequest(url: URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/profile")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: request)
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["emailAddress"] as? String
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
    }

    private static func randomString(count: Int) -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return String((0..<count).compactMap { _ in alphabet.randomElement() })
    }
}

enum GmailError: LocalizedError {
    case missingOAuthConfiguration, invalidURL, invalidCallback, tokenExchangeFailed, notConnected, requestFailed
    var errorDescription: String? {
        switch self {
        case .missingOAuthConfiguration: "请先配置 Google OAuth iOS Client ID。"
        case .invalidURL: "无法创建 Google 授权地址。"
        case .invalidCallback: "Google 授权回调无效。"
        case .tokenExchangeFailed: "Google Token 交换失败。"
        case .notConnected: "尚未连接 Gmail。"
        case .requestFailed: "Gmail 请求失败。"
        }
    }
}

private enum Keychain {
    static func write(_ value: String, for key: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key]
        SecItemDelete(query as CFDictionary)
        var insert = query; insert[kSecValueData as String] = data
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
