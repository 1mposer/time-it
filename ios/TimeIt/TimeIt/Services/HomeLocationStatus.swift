import CoreLocation

/// What Settings' Home row says, and whether "Use current location" can be
/// offered (fresh-eyes notes 3 + 8). Pure, so the truth table is pinned by
/// `HomeLocationStatusTests`.
enum HomeLocationStatus {

    /// The row's value: the picked city when there is one; otherwise the
    /// truth about device location — never "Using current location" when
    /// access is denied or restricted.
    static func label(homeName: String?, authorization: CLAuthorizationStatus) -> String {
        if let homeName { return homeName }
        return canUseCurrentLocation(authorization: authorization) ? "Using current location" : "Location off"
    }

    /// False while location is denied or restricted: clearing the picked
    /// city then would leave the app with no location at all (note 8).
    static func canUseCurrentLocation(authorization: CLAuthorizationStatus) -> Bool {
        authorization != .denied && authorization != .restricted
    }
}
