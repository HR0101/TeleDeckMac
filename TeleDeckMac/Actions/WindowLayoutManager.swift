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
    case accessibilityPermissionDenied

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
      case .accessibilityPermissionDenied:
        return "Mac側でアクセシビリティの権限が許可されていません。メニューバーのTeleDeckから許可してください"
      }
    }
  }

  /// centeredプリセットで使う、画面サイズに対するウィンドウの倍率
  private static let centeredScale: CGFloat = 0.7
  /// three-splitプリセットで対象にする最大アプリ数
  private static let threeSplitMaxAppCount = 3

  func apply(preset: String, completion: @escaping (Result<Void, Error>) -> Void) {
    // AXUIElementによるウィンドウ操作は権限が無いと必ず失敗する。
    // 「ウィンドウを取得できませんでした」という結果だけを返すと原因が伝わらないため、先に判定する
    guard PermissionMonitor.checkAccessibilityTrusted() else {
      completion(.failure(LayoutError.accessibilityPermissionDenied))
      return
    }

    switch preset {
    case WindowLayoutPreset.threeSplit.rawValue:
      applyThreeSplitLayout(completion: completion)
    default:
      applySingleWindowLayout(preset: preset, completion: completion)
    }
  }

  // MARK: - 単一ウィンドウの配置（left-half / right-half / maximize / centered）

  private func applySingleWindowLayout(preset: String, completion: @escaping (Result<Void, Error>) -> Void) {
    guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
      completion(.failure(LayoutError.noFrontmostApp))
      return
    }

    guard let window = Self.mainWindowElement(forPid: frontmostApp.processIdentifier) else {
      completion(.failure(LayoutError.noAccessibleWindow))
      return
    }

    // TeleDeckMac自身（メニューバー常駐アプリ）が乗っている画面ではなく、
    // 実際に配置対象となるこのウィンドウが乗っている画面を基準にする
    // （外部ディスプレイ環境でNSScreen.mainだけを使うと画面がずれるため）
    guard let screenFrame = Self.screenFrame(containing: window) else {
      completion(.failure(LayoutError.noScreen))
      return
    }

    guard let layout = WindowLayoutPreset(rawValue: preset),
          let targetFrame = Self.frame(for: layout, in: screenFrame) else {
      completion(.failure(LayoutError.unknownPreset(preset)))
      return
    }

    do {
      try Self.setFrame(targetFrame, for: window)
      completion(.success(()))
    } catch {
      completion(.failure(error))
    }
  }

  // MARK: - 3分割配置（three-split）

  private func applyThreeSplitLayout(completion: @escaping (Result<Void, Error>) -> Void) {
    let targetApps = Self.recentRegularApps(maxCount: Self.threeSplitMaxAppCount)
    guard !targetApps.isEmpty else {
      completion(.failure(LayoutError.noFrontmostApp))
      return
    }

    let windows = targetApps.compactMap { Self.mainWindowElement(forPid: $0.processIdentifier) }
    guard let firstWindow = windows.first else {
      completion(.failure(LayoutError.noAccessibleWindow))
      return
    }
    guard let screenFrame = Self.screenFrame(containing: firstWindow) else {
      completion(.failure(LayoutError.noScreen))
      return
    }

    let slices = Self.threeSplitFrames(in: screenFrame, count: windows.count)
    var successCount = 0

    for (index, window) in windows.enumerated() {
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

  /// プリセットに対応するウィンドウの矩形を返す（Cocoa座標系＝画面左下原点・Y上向き）。
  /// three-splitは複数ウィンドウを対象とするため、ここでは扱わずnilを返す
  private static func frame(for preset: WindowLayoutPreset, in screenFrame: CGRect) -> CGRect? {
    let halfWidth = screenFrame.width / 2
    let halfHeight = screenFrame.height / 2

    switch preset {
    case .leftHalf:
      return CGRect(x: screenFrame.minX, y: screenFrame.minY, width: halfWidth, height: screenFrame.height)
    case .rightHalf:
      return CGRect(x: screenFrame.midX, y: screenFrame.minY, width: halfWidth, height: screenFrame.height)
    // Cocoa座標系はY軸が上向きのため、画面上半分はminYではなくmidYが起点になる
    case .topHalf:
      return CGRect(x: screenFrame.minX, y: screenFrame.midY, width: screenFrame.width, height: halfHeight)
    case .bottomHalf:
      return CGRect(x: screenFrame.minX, y: screenFrame.minY, width: screenFrame.width, height: halfHeight)
    case .topLeftQuarter:
      return CGRect(x: screenFrame.minX, y: screenFrame.midY, width: halfWidth, height: halfHeight)
    case .topRightQuarter:
      return CGRect(x: screenFrame.midX, y: screenFrame.midY, width: halfWidth, height: halfHeight)
    case .bottomLeftQuarter:
      return CGRect(x: screenFrame.minX, y: screenFrame.minY, width: halfWidth, height: halfHeight)
    case .bottomRightQuarter:
      return CGRect(x: screenFrame.midX, y: screenFrame.minY, width: halfWidth, height: halfHeight)
    case .maximize:
      return screenFrame
    case .centered:
      return centeredFrame(in: screenFrame)
    case .threeSplit:
      return nil
    }
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

  /// グローバルディスプレイ座標系（kAXPositionAttributeが基準とする座標系）の原点(0,0)を
  /// 持つ「プライマリ画面（メニューバーが乗っている画面）」を返す。
  /// NSScreen.screensの並び順はプライマリ画面が先頭に来るとは限らないため、
  /// frame.originが.zeroの画面を明示的に探す必要がある
  private static func primaryScreen() -> NSScreen? {
    NSScreen.screens.first { $0.frame.origin == .zero }
  }

  /// 指定したウィンドウが実際に乗っている画面のvisibleFrame（Cocoa座標系）を返す。
  /// TeleDeckMac自身の画面ではなく、配置対象ウィンドウの現在位置から画面を特定するため、
  /// 外部ディスプレイ環境でもNSScreen.mainのズレの影響を受けない
  private static func screenFrame(containing window: AXUIElement) -> CGRect? {
    guard let primaryScreenHeight = Self.primaryScreen()?.frame.height else {
      return NSScreen.main?.visibleFrame
    }

    var positionRef: CFTypeRef?
    guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionRef) == .success,
          let positionValue = positionRef,
          CFGetTypeID(positionValue) == AXValueGetTypeID() else {
      return NSScreen.main?.visibleFrame
    }

    var axPosition = CGPoint.zero
    guard AXValueGetValue((positionValue as! AXValue), .cgPoint, &axPosition) else {
      return NSScreen.main?.visibleFrame
    }

    // Accessibility APIの座標（画面左上原点・Y下向き）をNSScreen.frameのCocoa座標
    // （画面左下原点・Y上向き）へ変換してから、突き合わせる画面を探す
    let cocoaPosition = CGPoint(x: axPosition.x, y: primaryScreenHeight - axPosition.y)
    let screen = NSScreen.screens.first { $0.frame.contains(cocoaPosition) } ?? NSScreen.main
    return screen?.visibleFrame
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

  /// setFrame実行後、実際に反映されたフレームと目標フレームがこの誤差（pt）以内なら一致とみなす
  private static let frameToleranceInPoints: CGFloat = 2.0

  /// AXUIElementのウィンドウへ位置・サイズを設定する。
  /// 引数frameはNSScreen由来のCocoa座標系（画面左下原点・Y上向き）だが、
  /// kAXPositionAttributeが期待するのはグローバルディスプレイ座標系（プライマリ画面左上原点・Y下向き）のため、
  /// ここで変換してから設定する（変換しないと、例えばmaximizeで画面下側にはみ出すなどの不具合になる）
  ///
  /// 一部のアプリはAXの実装上、位置とサイズを1回ずつ設定しただけでは狙った通りに反映されないことがある
  /// （特に別画面へまたがる移動の場合、OSが移動前の現在サイズを基準に位置をクランプすることがある）。
  /// そのため、Rectangle.appなど実績のあるウィンドウマネージャーと同様にサイズ→位置→サイズの順で設定し、
  /// 反映結果を読み戻して目標とずれていれば1回だけ再適用する。
  ///
  /// なお、Terminal（文字セル単位でしかリサイズできない）や最大ウィンドウサイズを持つアプリのように、
  /// 目標フレームちょうどには到達できないアプリは珍しくない。その場合でもAXの設定操作自体は成功しており、
  /// ウィンドウは「そのアプリで可能な範囲で最大化・配置」されている。厳密一致しないだけで失敗として扱うと、
  /// maximizeが常にエラーになるアプリが出てしまう（半分配置は届くのに最大化だけ画面幅に届かない等）。
  /// そこで、AXの設定操作が成功していれば成功として報告し、目標に届かなかった場合は調査用にログのみ残す。
  /// 権限不足などAX操作そのものが失敗するケースは、applyFrame側が例外を投げて従来どおり失敗として扱う。
  private static func setFrame(_ cocoaFrame: CGRect, for window: AXUIElement) throws {
    let axFrame = Self.accessibilityFrame(fromCocoa: cocoaFrame)

    // 1回目の適用。AXの設定操作自体が失敗した場合のみ、applyFrameが例外を投げる。
    try Self.applyFrame(axFrame, to: window)

    // 目標に十分近ければ完了。ずれていれば別画面クランプ等の可能性があるため1回だけ再適用する。
    if let appliedFrame = Self.currentAXFrame(of: window),
       Self.isApproximatelyEqual(appliedFrame, axFrame, tolerance: frameToleranceInPoints) {
      return
    }

    try Self.applyFrame(axFrame, to: window)

    // 再適用後も目標に届かない場合は、対象アプリ側の制約（最大/最小サイズ・リサイズ増分など）が理由であり、
    // AXの設定操作は成功している。ウィンドウは可能な範囲で配置済みのため成功として扱い、原因調査用のログのみ残す。
    if let retriedFrame = Self.currentAXFrame(of: window),
       !Self.isApproximatelyEqual(retriedFrame, axFrame, tolerance: frameToleranceInPoints) {
      print("ウィンドウを目標フレームちょうどには配置できませんでした（アプリ側の制約の可能性）: 目標=\(axFrame) 実際=\(retriedFrame)")
    }
  }

  /// axFrame（グローバルディスプレイ座標系）をウィンドウへ実際に適用する。
  /// サイズ→位置→サイズの順で設定することで、別画面への移動時にOSが
  /// 移動前の位置・サイズを基準にサイズをクランプしてしまう問題を回避する
  private static func applyFrame(_ axFrame: CGRect, to window: AXUIElement) throws {
    var origin = axFrame.origin
    var size = axFrame.size

    guard let positionValue = AXValueCreate(.cgPoint, &origin) else {
      throw LayoutError.axOperationFailed("位置の値生成に失敗しました")
    }
    guard let sizeValue = AXValueCreate(.cgSize, &size) else {
      throw LayoutError.axOperationFailed("サイズの値生成に失敗しました")
    }

    // 移動前の画面上でクランプされないよう、位置を設定する前に一度サイズを送っておく
    // （この最初の呼び出しの成否は問わない。最終的な整合性は位置設定後の2回目のサイズ設定で担保する）
    _ = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)

    let positionResult = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
    let sizeResult = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)

    guard positionResult == .success, sizeResult == .success else {
      throw LayoutError.axOperationFailed("AXError position=\(positionResult.rawValue) size=\(sizeResult.rawValue)")
    }
  }

  /// ウィンドウの現在のkAXPositionAttribute/kAXSizeAttributeを読み取り、
  /// グローバルディスプレイ座標系のCGRectとして返す（取得に失敗した場合はnil）
  private static func currentAXFrame(of window: AXUIElement) -> CGRect? {
    var positionRef: CFTypeRef?
    guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionRef) == .success,
          let positionValue = positionRef,
          CFGetTypeID(positionValue) == AXValueGetTypeID() else {
      return nil
    }

    var sizeRef: CFTypeRef?
    guard AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success,
          let sizeValue = sizeRef,
          CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
      return nil
    }

    var position = CGPoint.zero
    var size = CGSize.zero
    guard AXValueGetValue((positionValue as! AXValue), .cgPoint, &position),
          AXValueGetValue((sizeValue as! AXValue), .cgSize, &size) else {
      return nil
    }

    return CGRect(origin: position, size: size)
  }

  /// 2つのCGRectが、各成分について許容誤差(tolerance)以内で一致しているかを判定する
  private static func isApproximatelyEqual(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat) -> Bool {
    abs(lhs.origin.x - rhs.origin.x) <= tolerance &&
      abs(lhs.origin.y - rhs.origin.y) <= tolerance &&
      abs(lhs.size.width - rhs.size.width) <= tolerance &&
      abs(lhs.size.height - rhs.size.height) <= tolerance
  }

  /// Cocoa座標系（画面左下原点・Y上向き）のフレームを、Accessibility APIが期待する
  /// グローバルディスプレイ座標系（プライマリ画面左上原点・Y下向き）のフレームへ変換する
  private static func accessibilityFrame(fromCocoa cocoaFrame: CGRect) -> CGRect {
    guard let primaryScreenHeight = Self.primaryScreen()?.frame.height else { return cocoaFrame }
    let axY = primaryScreenHeight - cocoaFrame.origin.y - cocoaFrame.height
    return CGRect(x: cocoaFrame.origin.x, y: axY, width: cocoaFrame.width, height: cocoaFrame.height)
  }
}
