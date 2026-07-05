import AVFoundation
import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)

    // Native video trim channel (AVFoundation — no ffmpeg). The Flutter side
    // (VideoTrimService) falls back to the untrimmed clip if this is missing.
    guard let controller = window?.rootViewController as? FlutterViewController else { return }
    let channel = FlutterMethodChannel(
      name: "torqueden/video",
      binaryMessenger: controller.binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      guard let args = call.arguments as? [String: Any],
        let path = args["path"] as? String
      else {
        result(FlutterMethodNotImplemented)
        return
      }
      switch call.method {
      case "trim":
        guard let startMs = args["startMs"] as? Int, let endMs = args["endMs"] as? Int else {
          result(FlutterError(code: "bad_args", message: "startMs/endMs required", details: nil))
          return
        }
        SceneDelegate.trim(path: path, startMs: startMs, endMs: endMs, result: result)
      case "thumbnail":
        SceneDelegate.thumbnail(path: path, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// Grabs a poster frame (~0.1s in) as JPEG bytes for a clip's thumbnail.
  static func thumbnail(path: String, result: @escaping FlutterResult) {
    let asset = AVURLAsset(url: URL(fileURLWithPath: path))
    let gen = AVAssetImageGenerator(asset: asset)
    gen.appliesPreferredTrackTransform = true
    gen.maximumSize = CGSize(width: 600, height: 600)
    let time = CMTime(value: 1, timescale: 10)
    gen.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) {
      _, cgImage, _, status, error in
      DispatchQueue.main.async {
        guard status == .succeeded, let cg = cgImage,
          let data = UIImage(cgImage: cg).jpegData(compressionQuality: 0.8)
        else {
          result(
            FlutterError(
              code: "thumb_failed",
              message: error?.localizedDescription ?? "Thumbnail failed", details: nil))
          return
        }
        result(FlutterStandardTypedData(bytes: data))
      }
    }
  }

  /// Trims the video at [path] to the [startMs, endMs] window, re-encoding to a
  /// fresh mp4 in the temp dir. Returns the output path on success.
  static func trim(path: String, startMs: Int, endMs: Int, result: @escaping FlutterResult) {
    let asset = AVURLAsset(url: URL(fileURLWithPath: path))
    guard
      let export = AVAssetExportSession(
        asset: asset, presetName: AVAssetExportPresetHighestQuality)
    else {
      result(FlutterError(code: "export_init", message: "Could not create export session", details: nil))
      return
    }

    let outURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("trim_\(UUID().uuidString).mp4")
    export.outputURL = outURL
    export.outputFileType = .mp4
    export.shouldOptimizeForNetworkUse = true
    let start = CMTime(value: CMTimeValue(startMs), timescale: 1000)
    let end = CMTime(value: CMTimeValue(endMs), timescale: 1000)
    export.timeRange = CMTimeRange(start: start, end: end)

    export.exportAsynchronously {
      DispatchQueue.main.async {
        if export.status == .completed {
          result(outURL.path)
        } else {
          result(
            FlutterError(
              code: "export_failed",
              message: export.error?.localizedDescription ?? "Export failed",
              details: nil))
        }
      }
    }
  }
}
