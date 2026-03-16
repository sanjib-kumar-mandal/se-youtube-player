import Foundation
import Capacitor
import youtube_ios_player_helper

@objc(YoutubePlayerPlugin)
public class YoutubePlayerPlugin: CAPPlugin, CAPBridgedPlugin, YTPlayerViewDelegate {

    public let identifier = "YoutubePlayerPlugin"
    public let jsName = "YoutubePlayer"

    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "play", returnType: CAPPluginReturnPromise)
    ]

    private var playerView: YTPlayerView?

    @objc func play(_ call: CAPPluginCall) {

        print("📺 YoutubePlayerPlugin play() called")

        guard let videoId = call.getString("videoId") else {
            print("videoId missing")
            call.reject("videoId required")
            return
        }

        print("Loading videoId:", videoId)

        DispatchQueue.main.async {

            let player = YTPlayerView()
            player.delegate = self
            player.backgroundColor = .black

            let vc = UIViewController()
            vc.view.backgroundColor = .black

            // NOT fullscreen — allows swipe down
            vc.modalPresentationStyle = .pageSheet

            player.translatesAutoresizingMaskIntoConstraints = false
            vc.view.addSubview(player)

            NSLayoutConstraint.activate([
                player.topAnchor.constraint(equalTo: vc.view.topAnchor),
                player.bottomAnchor.constraint(equalTo: vc.view.bottomAnchor),
                player.leadingAnchor.constraint(equalTo: vc.view.leadingAnchor),
                player.trailingAnchor.constraint(equalTo: vc.view.trailingAnchor)
            ])

            self.playerView = player

            let vars: [String: Any] = [
                "autoplay": 1,
                "playsinline": 1,
                "controls": 1,
                "rel": 0
            ]

            print("Loading YouTube iframe")

            player.load(withVideoId: videoId, playerVars: vars)

            self.bridge?.viewController?.present(vc, animated: true)

            call.resolve([
                "status": "player opening"
            ])
        }
    }

    public func playerViewDidBecomeReady(_ playerView: YTPlayerView) {
        print("YouTube player ready")
        playerView.playVideo()
    }
}