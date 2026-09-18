import ClipStackCore
import Foundation

/// Where "Buy" goes. Lemon Squeezy hosts the checkout and is the merchant of record,
/// so there is nothing to implement here beyond the URL.
enum Checkout {
    // TODO: replace with the real Lemon Squeezy checkout URL once the product exists.
    static let purchaseURL = URL(string: "https://tryclipstack.com/#pricing")!
}

/// The real network, wrapped to match `LicenseTransport`.
///
/// Returns `nil` for everything that is not a completed HTTP exchange, which is what
/// keeps "the network is broken" from ever being mistaken for "your licence is bad".
enum URLSessionTransport {
    static let send: LicenseTransport = { request in
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse
        else { return nil }
        return (data, http.statusCode)
    }
}
