//
//  WindowLayoutManager.swift
//  TeleDeckMac
//
//  現在フォアグラウンドにあるアプリ（three-splitでは直近アクティブな複数アプリ）のメインウィンドウを、
//  プリセットのレイアウトへ配置する。フェーズ1のホットキー送信機能と同様、
//  ユーザーからアクセシビリティ権限が既に許可されている前提で動作する（新規権限は不要）。
//

import AppKit
import ApplicationServices

final class WindowLayoutManager {

  enum LayoutError: LocalizedError {
    case noFrontmostApp
    case noAccessibleWindow
    case noScreen
    case unknownPreset(String)
    case axOperationFailed(String)

    var errorDescription: String? {
      switch self {
      case .noFrontmostApp:
        return "最前面のアプリが取得できませんでした"
      case .noAccessibleWindow:
        return "対象アプリのウィンドウを取得できませんでした（アクセシビリティ権限を確認してください）"
      case .noScreen:
        return "画面情報を取得できませんでした"
      case .unknownPreset(let preset):
        return "未対応のウィンドウ配置プリセットです: \(preset)"
      case .axOperationFailed(let detail):
        return "ウィンドウの位置・サイズの変更に失敗しました: \(detail)"
      }
    }
  }

  /// centeredプリセットで使う、画面サイズに対するウィンドウの倍率
  private static let centeredScale: CGFloat = 0.7
  /// three-splitプリセットで対象にする最大アプリ数
  private static let threeSplitMaxAppCount = 3

  func apply(preset: String, completion: @escaping (Result<Void, Error>) -> Void) {
    guard let screenFrame = NSScreen.main?.visibleFrame else {
      completion(.failure(LayoutError.noScreen))
      return
    }

    switch preset {
    case "left-half":
      applySingleWindowLayout(frame: Self.leftHalfFrame(in: screenFrame), completion: completion)
    case "right-half":
      applySingleWindowLayout(frame: Self.rightHalfFrame(in: screenFrame), completion: completion)
    case "maximize":
      applySingleWindowLayout(frame: screenFrame, completion: completion)
    case "centered":
      applySingleWindowLayout(frame: Self.centeredFrame(in: screenFrame), completion: completion)
    case "three-split":
      applyThreeSplitLayout(in: screenFrame, completion: completion)
    default:
      completion(.failure(LayoutError.unknownPreset(preset)))
    }
  }

  // MARK: - 単一ウィンドウの配置（left-half / right-half / maximize / centered）

  private func applySingleWindowLayout(frame: CGRect, completion: @escaping (Result<Void, Error>) -> Void) {
    guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
      completion(.failure(LayoutError.noFrontmostApp))
      return
    }

    guard let window = Self.mainWindowElement(forPid: frontmostApp.processIdentifier) else {
      completion(.failure(LayoutError.noAccessibleWindow))
      return
    }

    do {
      try Self.setFrame(frame, for: window)
      completion(.success(()))
    } catch {
      completion(.failure(error))
    }
  }

  // MARK: - 3分割配置（three-split）

  private func applyThreeSplitLayout(in screenFrame: CGRect, completion: @escaping (Result<Void, Error>) -> Void) {
    let targetApps = Self.recentRegularApps(maxCount: Self.threeSplitMaxAppCount)
    guard !targetApps.isEmpty else {
      completion(.failure(LayoutError.noFrontmostApp))
      return
    }

    let slices = Self.threeSplitFrames(in: screenFrame, count: targetApps.count)
    var successCount = 0

    for (index, app) in targetApps.enumerated() {
      guard let window = Self.mainWindowElement(forPid: app.processIdentifier) else { continue }
      if (try? Self.setFrame(slices[index], for: window)) != nil {
        successCount += 1
      }
    }

    // 1つも配置できなければ「取得できた分だけでよい」の対象が0件だったということなので失敗として扱う
    if successCount > 0 {
      completion(.success(()))
    } else {
      completion(.failure(LayoutError.noAccessibleWindow))
    }
  }

  // MARK: - フレーム計算

  private static func leftHalfFrame(in screenFrame: CGRect) -> CGRect {
    CGRect(x: screenFrame.minX, y: screenFrame.minY, width: screenFrame.width / 2, height: screenFrame.height)
  }

  private static func rightHalfFrame(in screenFrame: CGRect) -> CGRect {
    CGRect(x: screenFrame.midX, y: screenFrame.minY, width: screenFrame.width / 2, height: screenFrame.height)
  }

  private static func centeredFrame(in screenFrame: CGRect) -> CGRect {
    let width = screenFrame.width * centeredScale
    let height = screenFrame.height * centeredScale
    let x = screenFrame.minX + (screenFrame.width - width) / 2
    let y = screenFrame.minY + (screenFrame.height - height) / 2
    return CGRect(x: x, y: y, width: width, height: height)
  }

  private static func threeSplitFrames(in screenFrame: CGRect, count: Int) -> [CGRect] {
    guard count > 0 else { return [] }
    let sliceWidth = screenFrame.width / CGFloat(count)
    return (0..<count).map { index in
      CGRect(
        x: screenFrame.minX + sliceWidth * CGFloat(index),
        y: screenFrame.minY,
        width: sliceWidth,
        height: screenFrame.height
      )
    }
  }

  // MARK: - 対象アプリ・ウィンドウの解決

  /// 直近アクティブな通常アプリ（Dockに表示される通常アプリ）を最大maxCount件取得する。
  /// フォアグラウンドアプリを最優先とし、残りはrunningApplicationsの並び順で補う。
  /// NSRunningApplicationは既定でオブジェクト同一性による比較となるためpidで重複判定する
  private static func recentRegularApps(maxCount: Int) -> [NSRunningApplication] {
    let regularApps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }

    var ordered: [NSRunningApplication] = []
    var orderedPids: Set<pid_t> = []

    if let frontmost = NSWorkspace.shared.frontmostApplication, frontmost.activationPolicy == .regular {
      ordered.append(frontmost)
      orderedPids.insert(frontmost.processIdentifier)
    }

    for app in regularApps {
      guard ordered.count < maxCount else { break }
      guard !orderedPids.contains(app.processIdentifier) else { continue }
      ordered.append(app)
      orderedPids.insert(app.processIdentifier)
    }

    return ordered
  }

  /// 指定pidのアプリのメインウィンドウ（フォーカス中のウィンドウ、無ければウィンドウ一覧の先頭）のAXUIElementを取得する
  private static func mainWindowElement(forPid pid: pid_t) -> AXUIElement? {
    let appElement = AXUIElementCreateApplication(pid)

    var focusedWindowRef: CFTypeRef?
    let focusedResult = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindowRef)
    if focusedResult == .success,
       let focusedWindow = focusedWindowRef,
       CFGetTypeID(focusedWindow) == AXUIElementGetTypeID() {
      // AXUIElementはCFTypeRefとしては常にダウンキャストが成功する構造のため、
      // コンパイラの指摘に従いCFTypeIDを明示的に確認したうえでキャストする
      return (focusedWindow as! AXUIElement)
    }

    var windowListRef: CFTypeRef?
    let listResult = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowListRef)
    guard listResult == .success, let windowList = windowListRef as? [AXUIElement], let firstWindow = windowList.first else {
      return nil
    }
    return firstWindow
  }

  /// AXUIElementのウィンドウへ位置・サイズを設定する
  private static func setFrame(_ frame: CGRect, for window: AXUIElement) throws {
    var origin = frame.origin
    var size = frame.size

    guard let positionValue = AXValueCreate(.cgPoint, &origin) else {
      throw LayoutError.axOperationFailed("位置の値生成に失敗しました")
    }
    guard let sizeValue = AXValueCreate(.cgSize, &size) else {
      throw LayoutError.axOperationFailed("サイズの値生成に失敗しました")
    }

    let positionResult = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
    let sizeResult = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)

    guard positionResult == .success, sizeResult == .success else {
      throw LayoutError.axOperationFailed("AXError position=\(positionResult.rawValue) size=\(sizeResult.rawValue)")
    }
  }
}
