//  現在地をひとつ取る
//
//  押されたときだけ取りに行きます。追いかけ続けることはしません。
//  許可を求めてから位置を頼むまでに間があるので、
//  「許可の返事」と「位置の返事」を別々に待ちます。

import CoreLocation

@MainActor
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var waitingForAuth: CheckedContinuation<Void, Never>?
    private var waitingForFix: CheckedContinuation<CLLocationCoordinate2D, Error>?

    enum Failure: LocalizedError {
        case denied
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .denied:
                #if os(macOS)
                return "位置情報の利用が許可されていません。"
                    + "システム設定 → プライバシーとセキュリティ → 位置情報サービス で許可してください。"
                #else
                return "位置情報の利用が許可されていません。"
                    + "設定 → プライバシーとセキュリティ → 位置情報サービス で許可してください。"
                #endif
            case .failed(let why):
                return "現在地を取得できませんでした（\(why)）"
            }
        }
    }

    override init() {
        super.init()
        manager.delegate = self
        // 天気を見るのに数十mの精度は要りません。速さと電池を優先します。
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func current() async throws -> CLLocationCoordinate2D {
        if manager.authorizationStatus == .notDetermined {
            await withCheckedContinuation { c in
                waitingForAuth = c
                startTimeout(30, forAuth: true)
                manager.requestWhenInUseAuthorization()
            }
        }
        switch manager.authorizationStatus {
        case .denied, .restricted:
            throw Failure.denied
        default:
            break
        }
        return try await withCheckedThrowingContinuation { c in
            waitingForFix = c
            startTimeout(20, forAuth: false)
            manager.requestLocation()
        }
    }

    /// 返事が来ないまま止まらないようにします。
    /// ボタンが押せないままになるのを防ぐためです。
    private func startTimeout(_ seconds: Double, forAuth: Bool) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            if forAuth {
                guard let c = waitingForAuth else { return }
                waitingForAuth = nil
                c.resume()
            } else {
                guard let c = waitingForFix else { return }
                waitingForFix = nil
                c.resume(throwing: Failure.failed("時間切れ"))
            }
        }
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // 最初に一度、まだ決まっていない状態でも呼ばれます。返事が出るまで待ちます。
        let decided = manager.authorizationStatus != .notDetermined
        Task { @MainActor in
            guard decided, let c = waitingForAuth else { return }
            waitingForAuth = nil
            c.resume()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        let coord = locations.last?.coordinate
        Task { @MainActor in
            guard let c = waitingForFix else { return }
            waitingForFix = nil
            if let coord {
                c.resume(returning: coord)
            } else {
                c.resume(throwing: Failure.failed("位置が空でした"))
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didFailWithError error: Error) {
        let why = error.localizedDescription
        Task { @MainActor in
            guard let c = waitingForFix else { return }
            waitingForFix = nil
            c.resume(throwing: Failure.failed(why))
        }
    }
}
