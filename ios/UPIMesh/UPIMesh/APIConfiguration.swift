import Foundation

/// Centralized network configuration for UPI Offline Mesh backend integration.
///
/// Ensures the physical iPhone reaches the Mac host without using localhost.
/// The default is the active LAN IP of the host machine (http://192.168.1.100:8080).
/// Can be overridden dynamically via UserDefaults or runtime configuration if DHCP changes the IP.
public final class APIConfiguration: @unchecked Sendable {
    public static let shared = APIConfiguration()

    private let userDefaultsKey = "com.upimesh.api.baseUrl"

    /// The default base URL pointing to the Mac's host IP.
    /// Notice: localhost is NOT used because on physical devices it points to the device itself.
    public static let defaultBaseURL = URL(string: "http://192.168.1.101:8080")!

    private init() {}

    /// The active base URL for backend communication.
    public var baseURL: URL {
        get {
            if let saved = UserDefaults.standard.string(forKey: userDefaultsKey),
               let url = URL(string: saved), !saved.isEmpty,
               url.scheme == "http" || url.scheme == "https" {
                return url
            }
            return Self.defaultBaseURL
        }
        set {
            UserDefaults.standard.set(newValue.absoluteString, forKey: userDefaultsKey)
        }
    }

    /// Host description formatted for UI display (e.g. "192.168.1.100:8080")
    public var hostDescription: String {
        let host = baseURL.host ?? Self.defaultBaseURL.host ?? "localhost"
        let port = baseURL.port ?? Self.defaultBaseURL.port ?? 8080
        return "\(host):\(port)"
    }


    /// Resets the base URL back to the default LAN address.
    public func resetToDefault() {
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
        UserDefaults.standard.removeObject(forKey: authTokenKey)
    }

    private let authTokenKey = "com.upimesh.api.authToken"

    /// Default administrative/demo token matching UPI_MESH_ADMIN_TOKEN in backend
    public static let defaultAuthToken = "admin-secret-token-demo"

    /// The active authentication token for financial read endpoints (e.g. Bearer token).
    public var authToken: String? {
        get {
            if let saved = UserDefaults.standard.string(forKey: authTokenKey), !saved.isEmpty {
                return saved
            }
            return Self.defaultAuthToken
        }
        set {
            if let val = newValue?.trimmingCharacters(in: .whitespacesAndNewlines), !val.isEmpty {
                UserDefaults.standard.set(val, forKey: authTokenKey)
            } else {
                UserDefaults.standard.removeObject(forKey: authTokenKey)
            }
        }
    }
}
