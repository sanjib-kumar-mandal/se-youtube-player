import Foundation
import Capacitor
import youtube_ios_player_helper

@objc(YoutubePlayerPlugin)
public final class YoutubePlayerPlugin: CAPPlugin, CAPBridgedPlugin, YTPlayerViewDelegate {

    private static let pluginVersion = "7.4.5"

    public let identifier = "YoutubePlayerPlugin"
    public let jsName = "YoutubePlayer"

    private var players: [String: PlayerInstance] = [:]

    private struct PlayerInstance {
        let playerView: YTPlayerView
        let viewController: UIViewController
    }

    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "initialize", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "destroy", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "playVideo", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "pauseVideo", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "stopVideo", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "seekTo", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getCurrentTime", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setVolume", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getVolume", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getPluginVersion", returnType: CAPPluginReturnPromise)
    ]

    // MARK: - Plugin Version

    @objc func getPluginVersion(_ call: CAPPluginCall) {
        call.resolve([
            "version": Self.pluginVersion
        ])
    }

    // MARK: - Initialize Player

    @objc func initialize(_ call: CAPPluginCall) {

        guard let videoId = call.getString("videoId"),
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
            playerView.delegate = self

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

            playerView.load(withVideoId: videoId, playerVars: playerVars)

            let vc = UIViewController()
            vc.view.backgroundColor = .black

            playerView.translatesAutoresizingMaskIntoConstraints = false
            vc.view.addSubview(playerView)

            NSLayoutConstraint.activate([
                playerView.topAnchor.constraint(equalTo: vc.view.topAnchor),
                playerView.bottomAnchor.constraint(equalTo: vc.view.bottomAnchor),
                playerView.leadingAnchor.constraint(equalTo: vc.view.leadingAnchor),
                playerView.trailingAnchor.constraint(equalTo: vc.view.trailingAnchor)
            ])

            vc.modalPresentationStyle = .fullScreen

            let instance = PlayerInstance(
                playerView: playerView,
                viewController: vc
            )

            self.players[playerId] = instance

            self.bridge?.viewController?.present(vc, animated: true) {

                call.resolve([
                    "playerReady": true,
                    "player": playerId
                ])

            }
        }
    }

    // MARK: - Destroy

    @objc func destroy(_ call: CAPPluginCall) {

        guard let playerId = call.getString("playerId"),
              let instance = players[playerId] else {
            call.reject("Player not found")
            return
        }

        DispatchQueue.main.async {

            instance.playerView.stopVideo()
            instance.playerView.delegate = nil

            instance.viewController.dismiss(animated: true) {

                self.players.removeValue(forKey: playerId)

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
            "result": [
                "method": "playVideo",
                "value": true
            ]
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
            "result": [
                "method": "pauseVideo",
                "value": true
            ]
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
            "result": [
                "method": "stopVideo",
                "value": true
            ]
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
            "result": [
                "method": "seekTo",
                "value": seconds
            ]
        ])
    }

    // MARK: - Volume

    @objc func setVolume(_ call: CAPPluginCall) {

        guard let playerId = call.getString("playerId"),
            let player = getPlayer(playerId) else {
            call.reject("Player not found")
            return
        }

        let volume = call.getInt("volume") ?? 50

        let js = "player.setVolume(\(volume));"
        player.evaluateJavaScript(js, completionHandler: nil)

        call.resolve([
            "result": [
                "method": "setVolume",
                "value": volume
            ]
        ])
    }

    @objc func getVolume(_ call: CAPPluginCall) {

        guard let playerId = call.getString("playerId"),
            let player = getPlayer(playerId) else {
            call.reject("Player not found")
            return
        }

        player.evaluateJavaScript("player.getVolume();") { result, error in

            if let error = error {
                call.reject("Failed to get volume: \(error.localizedDescription)")
                return
            }

            let volume = result as? Int ?? 0

            call.resolve([
                "result": [
                    "method": "getVolume",
                    "value": volume
                ]
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
            "result": [
                "method": "getCurrentTime",
                "value": time
            ]
        ])
    }

    // MARK: - Player Events

    public func playerViewDidBecomeReady(_ playerView: YTPlayerView) {

        notifyListeners("playerReady", data: [:])
    }

    public func playerView(_ playerView: YTPlayerView, didChangeTo state: YTPlayerState) {

        notifyListeners("playerStateChange", data: [
            "state": state.rawValue
        ])
    }

    public func playerView(_ playerView: YTPlayerView, receivedError error: YTPlayerError) {

        notifyListeners("playerError", data: [
            "error": error.rawValue
        ])
    }

}