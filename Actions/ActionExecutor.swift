//
//  ActionExecutor.swift
//  TeleDeckMac
//
//  iPadから届いたアクションを実際にMac上で実行する（起動・URLオープン・ホットキー送信）。
//

import AppKit
import CoreAudio
import CoreGraphics
import Foundation

final class ActionExecutor {

  private let windowLayoutManager = WindowLayoutManager()

  enum ExecutionError: LocalizedError {
    case appNotFound(String)
    case invalidURL(String)
    case unknownKey(String)
    case emptyText
    case invalidVolume(Int)
    case emptySteps
    case appleScriptFailed(String)

    var errorDescription: String? {
      switch self {
      case .appNotFound(let name):
        return "アプリが見つかりません: \(name)"
      case .invalidURL(let url):
        return "無効なURLです: \(url)"
      case .unknownKey(let key):
        return "未対応のキーです: \(key)"
      case .emptyText:
        return "入力するテキストが指定されていません"
      case .invalidVolume(let value):
        return "音量の値が不正です: \(value)"
      case .emptySteps:
        return "マルチアクションのステップが指定されていません"
      case .appleScriptFailed(let message):
        return "AppleScriptの実行に失敗しました: \(message)"
      }
    }
  }

  func execute(_ action: ActionPayload, completion: @escaping (Result<Void, Error>) -> Void) {
    switch action.type {
    case .launchApp:
      launchApp(named: action.target, completion: completion)
    case .openURL:
      openURL(action.target, completion: completion)
    case .hotkey:
      sendHotkey(keys: action.keys ?? [], completion: completion)
    case .typeText:
      typeText(action.text, completion: completion)
    case .setVolume:
      setVolume(action.volume, completion: completion)
    case .multiAction:
      executeMultiAction(steps: action.steps ?? [], completion: completion)
    case .delay:
      wait(ms: action.ms ?? 0, completion: completion)
    case .openFolder, .activateTab, .closeTab, .activateApplication:
      // openFolderはiPad内部専用のため通常ここには来ない。
      // activateTab/closeTab/activateApplicationはBonjourServerが専用処理へ直接振り分けるため、ここには来ない。
      // 防御的に何もせず成功として扱う。
      completion(.success(()))
    case .windowLayout:
      windowLayoutManager.apply(preset: action.preset ?? "", completion: completion)
    case .mediaKey:
      sendMediaKey(action.mediaKey, completion: completion)
    case .quitApplication:
      quitApplication(named: action.target, completion: completion)
    case .openFinderFolder:
      openFinderFolder(action.target, completion: completion)
    case .systemAction:
      sendSystemAction(action.systemAction, completion: completion)
    }
  }

  // MARK: - launchApp

  private func launchApp(named target: String?, completion: @escaping (Result<Void, Error>) -> Void) {
    guard let target, let appURL = resolveApplicationURL(for: target) else {
      completion(.failure(ExecutionError.appNotFound(target ?? "(未指定)")))
      return
    }

    NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration()) { _, error in
      DispatchQueue.main.async {
        completion(error == nil ? .success(()) : .failure(error!))
      }
    }
  }

  /// Bundle ID（"."を含む）指定と、アプリ名指定の両方に対応してアプリのURLを解決する
  private func resolveApplicationURL(for target: String) -> URL? {
    if target.contains("."), let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: target) {
      return url
    }
    return Self.findApplicationURL(named: target)
  }

  private static func findApplicationURL(named name: String) -> URL? {
    let searchDirectories = [
      "/Applications",
      "/System/Applications",
      "/System/Applications/Utilities",
      (NSHomeDirectory() as NSString).appendingPathComponent("Applications")
    ]
    for directory in searchDirectories {
      let candidate = (directory as NSString).appendingPathComponent("\(name).app")
      if FileManager.default.fileExists(atPath: candidate) {
        return URL(fileURLWithPath: candidate)
      }
    }
    return nil
  }

  // MARK: - quitApplication

  private func quitApplication(named target: String?, completion: @escaping (Result<Void, Error>) -> Void) {
    guard let target, let application = resolveRunningApplication(for: target) else {
      completion(.failure(ExecutionError.appNotFound(target ?? "(未指定)")))
      return
    }
    application.terminate()
    completion(.success(()))
  }

  private func resolveRunningApplication(for target: String) -> NSRunningApplication? {
    if target.contains("."),
       let application = NSRunningApplication.runningApplications(withBundleIdentifier: target).first {
      return application
    }
    return NSWorkspace.shared.runningApplications.first { $0.localizedName == target }
  }

  // MARK: - openFinderFolder

  private func openFinderFolder(_ target: String?, completion: @escaping (Result<Void, Error>) -> Void) {
    guard let target, !target.isEmpty else {
      completion(.failure(ExecutionError.invalidURL("(未指定)")))
      return
    }
    guard FileManager.default.fileExists(atPath: target) else {
      completion(.failure(ExecutionError.invalidURL(target)))
      return
    }
    NSWorkspace.shared.open(URL(fileURLWithPath: target))
    completion(.success(()))
  }

  // MARK: - openURL

  private func openURL(_ target: String?, completion: @escaping (Result<Void, Error>) -> Void) {
    guard let target, let url = URL(string: target) else {
      completion(.failure(ExecutionError.invalidURL(target ?? "(未指定)")))
      return
    }
    NSWorkspace.shared.open(url)
    completion(.success(()))
  }

  // MARK: - hotkey

  private func sendHotkey(keys: [String], completion: @escaping (Result<Void, Error>) -> Void) {
    guard !keys.isEmpty else {
      completion(.failure(ExecutionError.unknownKey("(未指定)")))
      return
    }

    var flags: CGEventFlags = []
    var keyCodes: [CGKeyCode] = []

    for key in keys {
      let lowerKey = key.lowercased()
      if let modifier = Self.modifierFlags[lowerKey] {
        flags.insert(modifier)
      } else if let code = Self.keyCodes[lowerKey] {
        if !keyCodes.contains(code) {
          keyCodes.append(code)
        }
      } else {
        completion(.failure(ExecutionError.unknownKey(key)))
        return
      }
    }

    guard !keyCodes.isEmpty else {
      completion(.failure(ExecutionError.unknownKey(keys.joined(separator: "+"))))
      return
    }

    // 矢印キー（123〜126）は、Mission Controlなどのシステムショートカットを正常に発火させるため
    // 特殊キーとしてのフラグを付与する必要がある
    if keyCodes.contains(where: { [123, 124, 125, 126].contains($0) }) {
      flags.insert(.maskSecondaryFn)
      flags.insert(.maskNumericPad)
    }

    guard let source = CGEventSource(stateID: .hidSystemState) else {
      completion(.failure(ExecutionError.unknownKey("イベントソースの生成に失敗しました")))
      return
    }

    for keyCode in keyCodes {
      let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
      keyDown?.flags = flags
      keyDown?.post(tap: .cghidEventTap)
    }
    for keyCode in keyCodes.reversed() {
      let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
      keyUp?.flags = flags
      keyUp?.post(tap: .cghidEventTap)
    }

    completion(.success(()))
  }

  // MARK: - typeText

  /// 1つのCGEventに載せられるUnicode文字数の上限（超える分は分割して送出する）
  private static let typeTextChunkSize = 20

  private func typeText(_ text: String?, completion: @escaping (Result<Void, Error>) -> Void) {
    guard let text, !text.isEmpty else {
      completion(.failure(ExecutionError.emptyText))
      return
    }

    guard let source = CGEventSource(stateID: .hidSystemState) else {
      completion(.failure(ExecutionError.unknownKey("イベントソースの生成に失敗しました")))
      return
    }

    let utf16Chars = Array(text.utf16)
    var index = 0
    while index < utf16Chars.count {
      let end = min(index + Self.typeTextChunkSize, utf16Chars.count)
      let chunk = Array(utf16Chars[index..<end])

      let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
      keyDown?.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
      keyDown?.post(tap: .cghidEventTap)

      let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
      keyUp?.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
      keyUp?.post(tap: .cghidEventTap)

      index = end
    }

    completion(.success(()))
  }

  // MARK: - setVolume

  private func setVolume(_ volume: Int?, completion: @escaping (Result<Void, Error>) -> Void) {
    guard let volume, (0...100).contains(volume) else {
      completion(.failure(ExecutionError.invalidVolume(volume ?? -1)))
      return
    }
    runAppleScript("set volume output volume \(volume)", completion: completion)
  }

  private func runAppleScript(_ source: String, completion: @escaping (Result<Void, Error>) -> Void) {
    var errorDict: NSDictionary?
    NSAppleScript(source: source)?.executeAndReturnError(&errorDict)

    if let errorDict {
      let message = errorDict[NSAppleScript.errorMessage] as? String ?? "不明なエラー"
      completion(.failure(ExecutionError.appleScriptFailed(message)))
      return
    }

    completion(.success(()))
  }

  // MARK: - mediaKey

  /// 音量・画面の明るさはCGEventの通常キーコードでは送信できず、
  /// NSEventのsystemDefinedイベント（Auxキー）として送出する必要がある。
  /// キーコードはIOKit/hidsystem/ev_keymap.hのNX_KEYTYPE_*定数の値
  private static let mediaKeyCodes: [String: Int32] = [
    "volumeUp": 0,
    "volumeDown": 1,
    "brightnessUp": 2,
    "brightnessDown": 3,
    "mute": 7,
    "playPause": 16,
    "nextTrack": 17,
    "previousTrack": 18,
    "keyboardBacklightUp": 21,
    "keyboardBacklightDown": 22
  ]

  private func sendMediaKey(_ key: String?, completion: @escaping (Result<Void, Error>) -> Void) {
    guard let key else {
      completion(.failure(ExecutionError.unknownKey("(未指定)")))
      return
    }
    // マイクミュートはCGEvent/Auxキーではなく、Core Audio経由で入力デバイス自体をミュートする
    // （個別アプリのミュートではなく、システム全体のマイク入力を止めるため）
    if key == "micMute" {
      toggleMicrophoneMute(completion: completion)
      return
    }
    guard let keyCode = Self.mediaKeyCodes[key] else {
      completion(.failure(ExecutionError.unknownKey(key)))
      return
    }
    Self.postAuxKey(keyCode)
    completion(.success(()))
  }

  // MARK: - マイクミュート（Core Audio）

  /// システムのデフォルト入力デバイスをミュート/解除する。
  /// デバイスがkAudioDevicePropertyMuteに対応していない場合は、入力音量を0にする方式へフォールバックする
  private func toggleMicrophoneMute(completion: @escaping (Result<Void, Error>) -> Void) {
    guard let deviceID = Self.defaultInputDeviceID() else {
      completion(.failure(ExecutionError.unknownKey("入力デバイスが見つかりません")))
      return
    }

    var muteAddress = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyMute,
      mScope: kAudioDevicePropertyScopeInput,
      mElement: kAudioObjectPropertyElementMain
    )

    guard AudioObjectHasProperty(deviceID, &muteAddress) else {
      toggleMicrophoneVolumeFallback(deviceID: deviceID, completion: completion)
      return
    }

    var isMuted: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    let getStatus = AudioObjectGetPropertyData(deviceID, &muteAddress, 0, nil, &size, &isMuted)
    guard getStatus == noErr else {
      completion(.failure(ExecutionError.unknownKey("マイクの状態取得に失敗しました（\(getStatus)）")))
      return
    }

    var newValue: UInt32 = isMuted == 0 ? 1 : 0
    let setStatus = AudioObjectSetPropertyData(deviceID, &muteAddress, 0, nil, size, &newValue)
    guard setStatus == noErr else {
      completion(.failure(ExecutionError.unknownKey("マイクのミュート切り替えに失敗しました（\(setStatus)）")))
      return
    }
    completion(.success(()))
  }

  /// kAudioDevicePropertyMuteに対応していない入力デバイス向けのフォールバック。
  /// 入力音量を0にすることでミュート相当の状態にし、解除時は直前の音量へ戻す。
  /// 直前の音量はAudioDeviceID（再接続やMacエージェント再起動で変わりうる）ではなく、
  /// デバイス固有で不変のUID文字列をキーにUserDefaultsへ永続化し、失われないようにする
  private func toggleMicrophoneVolumeFallback(deviceID: AudioDeviceID, completion: @escaping (Result<Void, Error>) -> Void) {
    var volumeAddress = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyVolumeScalar,
      mScope: kAudioDevicePropertyScopeInput,
      mElement: kAudioObjectPropertyElementMain
    )

    guard AudioObjectHasProperty(deviceID, &volumeAddress) else {
      completion(.failure(ExecutionError.unknownKey("このマイクはミュート操作に対応していません")))
      return
    }

    var currentVolume: Float32 = 0
    var size = UInt32(MemoryLayout<Float32>.size)
    let getStatus = AudioObjectGetPropertyData(deviceID, &volumeAddress, 0, nil, &size, &currentVolume)
    guard getStatus == noErr else {
      completion(.failure(ExecutionError.unknownKey("マイクの音量取得に失敗しました（\(getStatus)）")))
      return
    }

    let deviceUID = Self.deviceUID(for: deviceID)
    var newVolume: Float32
    if currentVolume > 0 {
      if let deviceUID {
        Self.savePreviousInputVolume(currentVolume, forDeviceUID: deviceUID)
      }
      newVolume = 0
    } else {
      newVolume = deviceUID.flatMap { Self.loadPreviousInputVolume(forDeviceUID: $0) } ?? 0.75
    }

    let setStatus = AudioObjectSetPropertyData(deviceID, &volumeAddress, 0, nil, size, &newVolume)
    guard setStatus == noErr else {
      completion(.failure(ExecutionError.unknownKey("マイクのミュート切り替えに失敗しました（\(setStatus)）")))
      return
    }
    completion(.success(()))
  }

  private static let previousInputVolumeDefaultsKey = "ActionExecutor.previousInputVolumeBeforeMute"

  private static func savePreviousInputVolume(_ volume: Float32, forDeviceUID deviceUID: String) {
    var stored = UserDefaults.standard.dictionary(forKey: previousInputVolumeDefaultsKey) as? [String: Double] ?? [:]
    stored[deviceUID] = Double(volume)
    UserDefaults.standard.set(stored, forKey: previousInputVolumeDefaultsKey)
  }

  private static func loadPreviousInputVolume(forDeviceUID deviceUID: String) -> Float32? {
    let stored = UserDefaults.standard.dictionary(forKey: previousInputVolumeDefaultsKey) as? [String: Double]
    return stored?[deviceUID].map { Float32($0) }
  }

  /// デバイス固有で再接続後も変わらないUID文字列を取得する（AudioDeviceIDは再接続や再起動で変わりうるため、
  /// 永続化のキーにはこちらを使う）
  private static func deviceUID(for deviceID: AudioDeviceID) -> String? {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyDeviceUID,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var uid: CFString?
    var size = UInt32(MemoryLayout<CFString?>.size)
    let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &uid)
    guard status == noErr else { return nil }
    return uid as String?
  }

  /// システムのデフォルト入力デバイスのIDを取得する
  private static func defaultInputDeviceID() -> AudioDeviceID? {
    var deviceID = AudioDeviceID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultInputDevice,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )

    let status = AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject),
      &address,
      0,
      nil,
      &size,
      &deviceID
    )

    guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }
    return deviceID
  }

  private static func postAuxKey(_ key: Int32) {
    func post(down: Bool) {
      let flags = NSEvent.ModifierFlags(rawValue: UInt(down ? 0xa00 : 0xb00))
      let data1 = (Int(key) << 16) | (down ? 0xa << 8 : 0xb << 8)
      let event = NSEvent.otherEvent(
        with: .systemDefined,
        location: .zero,
        modifierFlags: flags,
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        subtype: 8,
        data1: data1,
        data2: -1
      )
      event?.cgEvent?.post(tap: .cghidEventTap)
    }
    post(down: true)
    post(down: false)
  }

  // MARK: - systemAction

  /// lockScreen/screenshot系はCGEventでキーボードショートカットをそのまま送るだけで実現できる。
  /// sleep/screenSaverはSystem Eventsへの単発コマンドで済むため、AppleScript経由で実行する
  /// （初回はシステムから「System Eventsの制御を許可しますか」という確認が表示される）
  private func sendSystemAction(_ action: String?, completion: @escaping (Result<Void, Error>) -> Void) {
    switch action {
    case "sleep":
      runAppleScript("tell application \"System Events\" to sleep", completion: completion)
    case "screenSaver":
      runAppleScript("tell application \"System Events\" to start current screen saver", completion: completion)
    case "lockScreen":
      // macOS標準の画面ロックショートカット（Control+Command+Q）と同等
      sendHotkey(keys: ["ctrl", "cmd", "q"], completion: completion)
    case "screenshotFull":
      // macOS標準の全画面スクリーンショットショートカット（Command+Shift+3）と同等
      sendHotkey(keys: ["cmd", "shift", "3"], completion: completion)
    case "screenshotSelection":
      // macOS標準の範囲選択スクリーンショットショートカット（Command+Shift+4）と同等
      sendHotkey(keys: ["cmd", "shift", "4"], completion: completion)
    default:
      completion(.failure(ExecutionError.unknownKey(action ?? "(未指定)")))
    }
  }

  // MARK: - multiAction / delay

  private func executeMultiAction(steps: [ActionPayload], completion: @escaping (Result<Void, Error>) -> Void) {
    guard !steps.isEmpty else {
      completion(.failure(ExecutionError.emptySteps))
      return
    }
    executeSteps(steps, index: 0, completion: completion)
  }

  private func executeSteps(_ steps: [ActionPayload], index: Int, completion: @escaping (Result<Void, Error>) -> Void) {
    guard index < steps.count else {
      completion(.success(()))
      return
    }

    execute(steps[index]) { [weak self] result in
      switch result {
      case .success:
        self?.executeSteps(steps, index: index + 1, completion: completion)
      case .failure(let error):
        completion(.failure(error))
      }
    }
  }

  private func wait(ms: Int, completion: @escaping (Result<Void, Error>) -> Void) {
    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(ms)) {
      completion(.success(()))
    }
  }

  private static let modifierFlags: [String: CGEventFlags] = [
    "cmd": .maskCommand,
    "command": .maskCommand,
    "shift": .maskShift,
    "opt": .maskAlternate,
    "option": .maskAlternate,
    "alt": .maskAlternate,
    "ctrl": .maskControl,
    "control": .maskControl
  ]

  private static let keyCodes: [String: CGKeyCode] = [
    "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
    "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
    "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "9": 25, "7": 26, "8": 28, "0": 29,
    "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46,
    "return": 36, "tab": 48, "space": 49, "delete": 51, "escape": 53,
    // US配列キーボード画面（KeyboardView）向けに追加した記号・矢印・Caps Lock
    "-": 27, "=": 24, "[": 33, "]": 30, "\\": 42,
    ";": 41, "'": 39, ",": 43, ".": 47, "/": 44, "`": 50,
    "left": 123, "right": 124, "down": 125, "up": 126,
    "capslock": 57,
    // JISキーボードの専用入力ソースキー。Commandキー設定に依存せず直接切り替える。
    "eisu": 102,
    "kana": 104
  ]
}
