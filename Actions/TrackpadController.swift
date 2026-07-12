//
//  TrackpadController.swift
//  TeleDeckMac
//
//  iPadのトラックパッド画面から届いた移動・クリック・スクロールを、CGEventで実際のマウス操作に変換する。
//  フェーズ1のホットキー送信機能と同様、アクセシビリティ権限が既に許可されている前提で動作する（新規権限は不要）。
//

import CoreGraphics
import Foundation

final class TrackpadController {

  /// iPadの指の移動量に対するカーソル移動量の倍率
  private static let sensitivity: CGFloat = 1.5

  /// 現在のカーソル位置へdx/dyを加算し、画面内にクランプしてから移動する
  func move(dx: Double, dy: Double) {
    guard let currentLocation = CGEvent(source: nil)?.location else { return }

    let moved = CGPoint(
      x: currentLocation.x + CGFloat(dx) * Self.sensitivity,
      y: currentLocation.y + CGFloat(dy) * Self.sensitivity
    )
    CGWarpMouseCursorPosition(Self.clamped(moved))
  }

  /// 現在のカーソル位置で左クリック・右クリックを行う
  func click(button: String) {
    guard let currentLocation = CGEvent(source: nil)?.location else { return }
    let source = CGEventSource(stateID: .hidSystemState)

    let (downType, upType, mouseButton): (CGEventType, CGEventType, CGMouseButton) =
      button == "right" ? (.rightMouseDown, .rightMouseUp, .right) : (.leftMouseDown, .leftMouseUp, .left)

    let down = CGEvent(mouseEventSource: source, mouseType: downType, mouseCursorPosition: currentLocation, mouseButton: mouseButton)
    down?.post(tap: .cghidEventTap)

    let up = CGEvent(mouseEventSource: source, mouseType: upType, mouseCursorPosition: currentLocation, mouseButton: mouseButton)
    up?.post(tap: .cghidEventTap)
  }

  /// 2本指スクロールをホイールイベントとして送出する
  func scroll(dx: Double, dy: Double) {
    let event = CGEvent(
      scrollWheelEvent2Source: nil,
      units: .pixel,
      wheelCount: 2,
      wheel1: Int32(dy),
      wheel2: Int32(dx),
      wheel3: 0
    )
    event?.post(tap: .cghidEventTap)
  }

  /// メインディスプレイの範囲内にクランプする（CGDisplayBoundsはCGEventと同じ左上原点の座標系のため、NSScreenは使わない）
  private static func clamped(_ point: CGPoint) -> CGPoint {
    let bounds = CGDisplayBounds(CGMainDisplayID())
    let x = min(max(point.x, bounds.minX), bounds.maxX - 1)
    let y = min(max(point.y, bounds.minY), bounds.maxY - 1)
    return CGPoint(x: x, y: y)
  }
}
