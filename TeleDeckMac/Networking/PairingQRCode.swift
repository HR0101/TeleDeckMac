//
//  PairingQRCode.swift
//  TeleDeckMac
//
//  ペアリング情報（PairingQRPayload）をQRコード画像へ変換する。
//  iPad側がカメラで読み取り、PIN手入力の代わりに使う。
//

import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

enum PairingQRCode {

  enum GenerationError: LocalizedError {
    case renderingFailed

    var errorDescription: String? {
      switch self {
      case .renderingFailed:
        return "QRコード画像の生成に失敗しました"
      }
    }
  }

  /// PayloadをJSON化し、指定した一辺のサイズ（px）のQRコードNSImageを生成する。
  /// CIQRCodeGeneratorの出力は数十px四方と小さいため、ぼやけないよう最近傍で整数倍に拡大する
  static func makeImage(for payload: PairingQRPayload, sideLength: CGFloat) throws -> NSImage {
    // JSONEncoderのencodeは理論上throwするが、単純な値型のため実際にはまず失敗しない。
    // 失敗した場合は呼び出し側へそのまま伝播させる
    let jsonData = try JSONEncoder().encode(payload)

    let filter = CIFilter.qrCodeGenerator()
    filter.message = jsonData
    // 誤り訂正レベルM（約15%復元）。小さな表示でも読み取りやすいバランス
    filter.correctionLevel = "M"

    guard let outputImage = filter.outputImage else {
      throw GenerationError.renderingFailed
    }

    // 生成直後のQRは1モジュール=1pxのため、モジュール境界が崩れないよう整数倍で拡大してから描画する
    let rawScale = sideLength / outputImage.extent.width
    let scale = max(1, rawScale.rounded(.down))
    let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

    let context = CIContext()
    guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
      throw GenerationError.renderingFailed
    }

    return NSImage(cgImage: cgImage, size: NSSize(width: scaledImage.extent.width, height: scaledImage.extent.height))
  }
}
