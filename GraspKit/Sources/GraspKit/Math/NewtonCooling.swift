import Foundation

/// Newton's law of cooling: a cup drifts toward room temperature exponentially,
/// `T(t) = T_room + (T_0 − T_room)·e^(−t/τ)`.
public enum NewtonCooling {
    /// Temperature after `seconds`, starting at `start`, in a room at `ambient`, with time constant `tau` (seconds).
    public static func temperature(start: Double, ambient: Double, tau: Double, after seconds: Double) -> Double {
        guard tau > 0 else { return ambient }
        return ambient + (start - ambient) * exp(-max(seconds, 0) / tau)
    }
}
