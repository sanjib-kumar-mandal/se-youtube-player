import Foundation
import Capacitor
import youtube_ios_player_helper

@objc(YoutubePlayerPlugin)
public final class YoutubePlayerPlugin: CAPPlugin, CAPBridgedPlugin {

    private static let pluginVersion = "7.4.5"

    public let identifier = "YoutubePlayerPlugin"
    public let jsName = "YoutubePlayer"

    private var players: [String: PlayerInstance] = [:]

    // MARK: - Player Instance

    // FIX (Bug 1): Each PlayerInstance owns its delegate so events can be
    // attributed back to the correct playerId.
    private class PlayerInstance: NSObject, YTPlayerViewDelegate {

        let playerId: String
        let playerView: YTPlayerView
        let viewController: UIViewController

        // Deferred resolve: fired once the iframe reports ready, not when the
        // view controller finishes presenting (Bug 4).
        var pendingReadyCall: CAPPluginCall?

        weak var plugin: YoutubePlayerPlugin?

        init(playerId: String,
             playerView: YTPlayerView,
             viewController: UIViewController,
             plugin: YoutubePlayerPlugin) {
            self.playerId    = playerId
            self.playerView  = playerView
            self.viewController = viewController
            self.plugin      = plugin
            super.init()
            playerView.delegate = self
        }

        // MARK: YTPlayerViewDelegate

        func playerViewDidBecomeReady(_ playerView: YTPlayerView) {
            // FIX (Bug 4): resolve the initialize() call here, not inside the
            // present(animated:completion:) block.
            if let call = pendingReadyCall {
                call.resolve([
                    "playerReady": true,
                    "player": playerId
                ])
                pendingReadyCall = nil
            }
            // FIX (Bug 5): include playerId in every event payload.
            plugin?.notifyListeners("playerReady", data: ["playerId": playerId])
        }

        func playerView(_ playerView: YTPlayerView, didChangeTo state: YTPlayerState) {
            // FIX (Bug 5): include playerId so the JS side can route correctly.
            plugin?.notifyListeners("playerStateChange", data: [
                "playerId": playerId,
                "state": state.rawValue
            ])
        }

        func playerView(_ playerView: YTPlayerView, receivedError error: YTPlayerError) {
            // FIX (Bug 5): include playerId.
            plugin?.notifyListeners("playerError", data: [
                "playerId": playerId,
                "error": error.rawValue
            ])
        }
    }

    // MARK: - Plugin Methods

    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "initialize",      returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "destroy",         returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "playVideo",       returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "pauseVideo",      returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "stopVideo",       returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "seekTo",          returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getCurrentTime",  returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setVolume",       returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getVolume",       returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getPluginVersion",returnType: CAPPluginReturnPromise)
    ]

    // MARK: - Plugin Version

    @objc func getPluginVersion(_ call: CAPPluginCall) {
        call.resolve(["version": Self.pluginVersion])
    }

    // MARK: - Initialize Player

    @objc func initialize(_ call: CAPPluginCall) {

        guard let videoId  = call.getString("videoId"),
              let playerId = call.getString("playerId") else {
            call.reject("Missing required parameters: videoId and playerId")
            return
        }

        if players[playerId] != nil {
            call.reject("Player with id '\(playerId)' already exists")
            return
        }

        DispatchQueue.main.async {

            let playerView = YTPlayerView()
            playerView.backgroundColor = .black

            var playerVars: [String: Any] = [
                "playsinline": 1,
                "controls": 1,
                "rel": 0,
                "modestbranding": 1
            ]

            if let userVars = call.getObject("playerVars") {
                for (key, value) in userVars {
                    playerVars[key] = value
                }
            }

            if call.getBool("autoplay") == true {
                playerVars["autoplay"] = 1
            }

            let vc = UIViewController()
            vc.view.backgroundColor = .black

            // FIX (Bug 6): .overFullScreen works on both iPhone and iPad;
            // .fullScreen is rejected as a sheet on iPad.
            vc.modalPresentationStyle = .overFullScreen

            playerView.translatesAutoresizingMaskIntoConstraints = false
            vc.view.addSubview(playerView)

            NSLayoutConstraint.activate([
                playerView.topAnchor.constraint(equalTo: vc.view.topAnchor),
                playerView.bottomAnchor.constraint(equalTo: vc.view.bottomAnchor),
                playerView.leadingAnchor.constraint(equalTo: vc.view.leadingAnchor),
                playerView.trailingAnchor.constraint(equalTo: vc.view.trailingAnchor)
            ])

            // FIX (Bug 1 + Bug 4): instance owns its delegate; pendingReadyCall
            // is resolved when the iframe fires playerViewDidBecomeReady.
            let instance = PlayerInstance(
                playerId: playerId,
                playerView: playerView,
                viewController: vc,
                plugin: self
            )
            instance.pendingReadyCall = call

            // Register before presenting so no delegate event is missed.
            self.players[playerId] = instance

            playerView.load(withVideoId: videoId, playerVars: playerVars)

            self.bridge?.viewController?.present(vc, animated: true)
            // NOTE: call is intentionally NOT resolved here — see Bug 4 fix above.
        }
    }

    // MARK: - Destroy

    @objc func destroy(_ call: CAPPluginCall) {

        guard let playerId = call.getString("playerId"),
              let instance = players[playerId] else {
            call.reject("Player not found")
            return
        }

        // FIX (Bug 7): remove from the map immediately so a failed dismiss
        // cannot leave a dangling reference.
        players.removeValue(forKey: playerId)

        DispatchQueue.main.async {

            instance.playerView.stopVideo()
            instance.playerView.delegate = nil

            instance.viewController.dismiss(animated: true) {
                call.resolve([
                    "result": [
                        "method": "destroy",
                        "value": true
                    ]
                ])
            }
        }
    }

    // MARK: - Helpers

    private func getPlayer(_ id: String) -> YTPlayerView? {
        return players[id]?.playerView
    }

    // MARK: - Player Controls

    @objc func playVideo(_ call: CAPPluginCall) {

        guard let id = call.getString("playerId"),
              let player = getPlayer(id) else {
            call.reject("Player not found")
            return
        }

        player.playVideo()

        call.resolve([
            "result": ["method": "playVideo", "value": true]
        ])
    }

    @objc func pauseVideo(_ call: CAPPluginCall) {

        guard let id = call.getString("playerId"),
              let player = getPlayer(id) else {
            call.reject("Player not found")
            return
        }

        player.pauseVideo()

        call.resolve([
            "result": ["method": "pauseVideo", "value": true]
        ])
    }

    @objc func stopVideo(_ call: CAPPluginCall) {

        guard let id = call.getString("playerId"),
              let player = getPlayer(id) else {
            call.reject("Player not found")
            return
        }

        player.stopVideo()

        call.resolve([
            "result": ["method": "stopVideo", "value": true]
        ])
    }

    @objc func seekTo(_ call: CAPPluginCall) {

        guard let id = call.getString("playerId"),
              let player = getPlayer(id) else {
            call.reject("Player not found")
            return
        }

        let seconds = call.getDouble("seconds") ?? 0
        player.seek(toSeconds: Float(seconds), allowSeekAhead: true)

        call.resolve([
            "result": ["method": "seekTo", "value": seconds]
        ])
    }

    // MARK: - Volume
    //
    // youtube_ios_player_helper uses WKWebView internally. The only JS bridge
    // available is webView?.evaluateJavaScript(_:completionHandler:), which is
    // async. setVolume fires-and-forgets (resolves immediately). getVolume
    // resolves inside the completion handler once the JS result is returned.

    @objc func setVolume(_ call: CAPPluginCall) {

        guard let playerId = call.getString("playerId"),
              let player = getPlayer(playerId) else {
            call.reject("Player not found")
            return
        }

        // FIX (Bug 3): honour the full 0-100 range via the IFrame Player API.
        let volume  = call.getInt("volume") ?? 100
        let clamped = max(0, min(100, volume))

        player.webView?.evaluateJavaScript("player.setVolume(\(clamped))")

        call.resolve([
            "result": ["method": "setVolume", "value": clamped]
        ])
    }

    @objc func getVolume(_ call: CAPPluginCall) {

        // FIX (Bug 2): validate the player exists before reading.
        guard let playerId = call.getString("playerId"),
              let player = getPlayer(playerId) else {
            call.reject("Player not found")
            return
        }

        // evaluateJavaScript is async — resolve inside the completion handler.
        player.webView?.evaluateJavaScript("player.getVolume()") { result, error in
            if let error = error {
                call.reject("getVolume failed: \(error.localizedDescription)")
                return
            }
            let volume = (result as? Int) ?? (result as? Double).map { Int($0) } ?? 100
            call.resolve([
                "result": ["method": "getVolume", "value": volume]
            ])
        }
    }

    // MARK: - Time

    @objc func getCurrentTime(_ call: CAPPluginCall) {

        guard let id = call.getString("playerId"),
              let player = getPlayer(id) else {
            call.reject("Player not found")
            return
        }

        let time = player.currentTime()

        call.resolve([
            "result": ["method": "getCurrentTime", "value": time]
        ])
    }
}