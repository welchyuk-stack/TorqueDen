import AVFoundation
import CoreImage
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
        SceneDelegate.trim(
          path: path, startMs: startMs, endMs: endMs,
          filter: args["filter"] as? String, result: result)
      case "thumbnail":
        SceneDelegate.thumbnail(path: path, result: result)
      case "overlayText":
        guard let text = args["text"] as? String else {
          result(FlutterError(code: "bad_args", message: "text required", details: nil))
          return
        }
        SceneDelegate.overlayText(
          path: path, text: text,
          normY: (args["normY"] as? Double) ?? 0.85,
          sizeFraction: (args["sizeFraction"] as? Double) ?? 0.08,
          colorHex: (args["colorHex"] as? String) ?? "#FFFFFF",
          result: result)
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

  /// Trims the video at [path] to the [startMs, endMs] window and, if [filter]
  /// is given, bakes in a colour filter — in a single re-encode to a fresh mp4.
  /// Returns the output path on success.
  static func trim(
    path: String, startMs: Int, endMs: Int, filter: String?, result: @escaping FlutterResult
  ) {
    let asset = AVURLAsset(url: URL(fileURLWithPath: path))
    guard
      let export = AVAssetExportSession(
        asset: asset, presetName: AVAssetExportPresetHighestQuality)
    else {
      result(FlutterError(code: "export_init", message: "Could not create export session", details: nil))
      return
    }

    if let filter = filter, let ciFilter = SceneDelegate.ciFilter(for: filter) {
      export.videoComposition = AVVideoComposition(asset: asset) { request in
        let source = request.sourceImage.clampedToExtent()
        ciFilter.setValue(source, forKey: kCIInputImageKey)
        let output = (ciFilter.outputImage ?? source).cropped(to: request.sourceImage.extent)
        request.finish(with: output, context: nil)
      }
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

  /// Maps a filter id (from the Flutter editor) to a Core Image filter. Uses
  /// CIColorMatrix with the SAME RGB weights as the Flutter live-preview
  /// matrices, so preview and export match.
  static func ciFilter(for name: String) -> CIFilter? {
    switch name {
    case "mono":
      return colorMatrix(
        r: [0.2126, 0.7152, 0.0722], g: [0.2126, 0.7152, 0.0722], b: [0.2126, 0.7152, 0.0722])
    case "vivid":
      return colorMatrix(
        r: [1.3937, -0.3576, -0.0361], g: [-0.1063, 1.1424, -0.0361], b: [-0.1063, -0.3576, 1.4639])
    case "warm":
      return colorMatrix(r: [1.15, 0, 0], g: [0, 1.0, 0], b: [0, 0, 0.85])
    case "cool":
      return colorMatrix(r: [0.85, 0, 0], g: [0, 1.0, 0], b: [0, 0, 1.2])
    default:
      return nil
    }
  }

  /// Builds a CIColorMatrix from per-channel RGB weight rows (alpha untouched).
  static func colorMatrix(r: [CGFloat], g: [CGFloat], b: [CGFloat]) -> CIFilter? {
    let f = CIFilter(name: "CIColorMatrix")
    f?.setValue(CIVector(x: r[0], y: r[1], z: r[2], w: 0), forKey: "inputRVector")
    f?.setValue(CIVector(x: g[0], y: g[1], z: g[2], w: 0), forKey: "inputGVector")
    f?.setValue(CIVector(x: b[0], y: b[1], z: b[2], w: 0), forKey: "inputBVector")
    return f
  }

  /// Bakes a centred caption over the video via a Core Animation text layer.
  /// [normY] is the vertical centre of the text (0 = top, 1 = bottom);
  /// [sizeFraction] is font size as a fraction of the video height.
  static func overlayText(
    path: String, text: String, normY: Double, sizeFraction: Double, colorHex: String,
    result: @escaping FlutterResult
  ) {
    let asset = AVURLAsset(url: URL(fileURLWithPath: path))
    let videoComp = AVMutableVideoComposition(propertiesOf: asset)  // orientation-aware
    let w = videoComp.renderSize.width
    let h = videoComp.renderSize.height

    let parentLayer = CALayer()
    parentLayer.frame = CGRect(x: 0, y: 0, width: w, height: h)
    let videoLayer = CALayer()
    videoLayer.frame = CGRect(x: 0, y: 0, width: w, height: h)
    parentLayer.addSublayer(videoLayer)

    let fontSize = max(12, CGFloat(sizeFraction) * h)
    let lineH = fontSize * 1.4
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    let textLayer = CATextLayer()
    textLayer.string = NSAttributedString(
      string: text,
      attributes: [
        .font: UIFont.boldSystemFont(ofSize: fontSize),
        .foregroundColor: SceneDelegate.uiColor(colorHex),
        .paragraphStyle: style,
      ])
    textLayer.isWrapped = true
    textLayer.alignmentMode = .center
    textLayer.contentsScale = 2.0
    textLayer.shadowColor = UIColor.black.cgColor
    textLayer.shadowOpacity = 0.85
    textLayer.shadowRadius = 4
    textLayer.shadowOffset = .zero
    // CALayer origin is bottom-left; normY is the centre measured from the top.
    let originY = h - (CGFloat(normY) * h) - lineH / 2
    textLayer.frame = CGRect(x: 12, y: originY, width: w - 24, height: lineH)
    parentLayer.addSublayer(textLayer)

    videoComp.animationTool = AVVideoCompositionCoreAnimationTool(
      postProcessingAsVideoLayer: videoLayer, in: parentLayer)

    guard
      let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality)
    else {
      result(FlutterError(code: "export_init", message: "Could not create export session", details: nil))
      return
    }
    let outURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("text_\(UUID().uuidString).mp4")
    export.outputURL = outURL
    export.outputFileType = .mp4
    export.videoComposition = videoComp
    export.exportAsynchronously {
      DispatchQueue.main.async {
        if export.status == .completed {
          result(outURL.path)
        } else {
          result(
            FlutterError(
              code: "export_failed",
              message: export.error?.localizedDescription ?? "Export failed", details: nil))
        }
      }
    }
  }

  static func uiColor(_ hex: String) -> UIColor {
    let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
    var v: UInt64 = 0
    Scanner(string: s).scanHexInt64(&v)
    return UIColor(
      red: CGFloat((v & 0xFF0000) >> 16) / 255,
      green: CGFloat((v & 0x00FF00) >> 8) / 255,
      blue: CGFloat(v & 0x0000FF) / 255,
      alpha: 1)
  }
}
