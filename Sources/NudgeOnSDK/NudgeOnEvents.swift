/// Recommended event names shared with the NudgeOn console.
/// Pass these strings to `NudgeOn.track(_:properties:)` after the action succeeds.
/// Constants do not emit events or identify users; custom event names remain supported.
public enum NudgeOnEvents {
    public static let signUp = "sign_up"
    public static let login = "login"
    public static let purchaseCompleted = "purchase_completed"
    public static let productViewed = "product_viewed"
    public static let addToCart = "add_to_cart"
    public static let checkoutStarted = "checkout_started"
}
