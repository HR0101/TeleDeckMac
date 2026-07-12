//
//  ProfileStore.swift
//  TeleDeckMac
//
//  プロファイル・ボタン構成の本体（source of truth）。Application Support配下のJSONへ永続化し、
//  変更のたびにonChangeフックを呼ぶ（BonjourServerがこれを使って接続中のiPadへ`profileSync`を送る）。
//

import Foundation
import Observation

@Observable
final class ProfileStore {
  /// iPad側（Models/ProfileStore.swift）と同じグリッドサイズ。編集画面のグリッド表示で使う
  static let gridRows = 3
  static let gridCols = 5

  private(set) var profiles: [ProfileConfig]
  private(set) var activeProfileId: UUID

  /// プロファイル一覧または選択中プロファイルが変わるたびに呼ばれる
  var onChange: (([ProfileConfig], UUID) -> Void)?

  /// activeProfileIdに一致するプロファイル。見つからなければ先頭のプロファイルを返す
  var activeProfile: ProfileConfig {
    profiles.first { $0.id == activeProfileId } ?? profiles[0]
  }

  private let fileURL: URL

  init() {
    let supportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("TeleDeckMac", isDirectory: true)
    fileURL = supportURL.appendingPathComponent("profiles.json")

    let loaded = Self.loadFromDisk(at: fileURL)
    let resolvedProfiles = loaded ?? Self.defaultProfiles
    profiles = resolvedProfiles
    activeProfileId = resolvedProfiles[0].id

    if loaded == nil {
      save()
    }
  }

  // MARK: - iPadからの反映依頼・自動切替

  /// iPad側からの編集依頼、またはiPadとの再同期に使う。全面的に置き換えて保存する
  func replaceAll(profiles: [ProfileConfig], activeProfileId: UUID) {
    self.profiles = profiles
    self.activeProfileId = profiles.contains(where: { $0.id == activeProfileId }) ? activeProfileId : profiles[0].id
    save()
    onChange?(self.profiles, self.activeProfileId)
  }

  /// フォアグラウンドアプリのBundle IDに一致するプロファイルへ自動切替する
  func activateProfile(matchingBundleId bundleId: String) {
    let newActiveId: UUID
    if let matched = profiles.first(where: { $0.triggerAppBundleId == bundleId }) {
      newActiveId = matched.id
    } else if let defaultProfile = profiles.first(where: { $0.triggerAppBundleId == nil }) {
      newActiveId = defaultProfile.id
    } else {
      return
    }

    guard newActiveId != activeProfileId else { return }
    activeProfileId = newActiveId
    save()
    onChange?(profiles, activeProfileId)
  }

  // MARK: - Mac側編集ウィンドウからの操作

  func addProfile(_ profile: ProfileConfig) {
    profiles.append(profile)
    notifyChange()
  }

  func updateProfile(_ profile: ProfileConfig) {
    guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
    profiles[index] = profile
    notifyChange()
  }

  func deleteProfile(id: UUID) {
    guard profiles.count > 1 else { return }
    profiles.removeAll { $0.id == id }
    if activeProfileId == id {
      activeProfileId = profiles[0].id
    }
    notifyChange()
  }

  func setActiveProfile(id: UUID) {
    guard profiles.contains(where: { $0.id == id }) else { return }
    activeProfileId = id
    notifyChange()
  }

  func addButton(_ button: ButtonConfig, toProfile profileId: UUID) {
    guard let profileIndex = profiles.firstIndex(where: { $0.id == profileId }) else { return }
    profiles[profileIndex].buttons.append(button)
    notifyChange()
  }

  func updateButton(_ button: ButtonConfig, inProfile profileId: UUID) {
    guard let profileIndex = profiles.firstIndex(where: { $0.id == profileId }) else { return }
    guard let buttonIndex = profiles[profileIndex].buttons.firstIndex(where: { $0.id == button.id }) else { return }
    profiles[profileIndex].buttons[buttonIndex] = button
    notifyChange()
  }

  func deleteButton(id: UUID, fromProfile profileId: UUID) {
    guard let profileIndex = profiles.firstIndex(where: { $0.id == profileId }) else { return }
    profiles[profileIndex].buttons.removeAll { $0.id == id }
    notifyChange()
  }

  private func notifyChange() {
    save()
    onChange?(profiles, activeProfileId)
  }

  // MARK: - 永続化

  private func save() {
    do {
      try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      let data = try JSONEncoder().encode(profiles)
      try data.write(to: fileURL, options: .atomic)
    } catch {
      print("プロファイルの保存に失敗しました: \(error.localizedDescription)")
    }
  }

  private static func loadFromDisk(at url: URL) -> [ProfileConfig]? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder().decode([ProfileConfig].self, from: data)
  }

  private static let defaultButtons: [ButtonConfig] = [
    ButtonConfig(row: 0, col: 0, label: "Chrome", iconName: "globe", action: ActionPayload(type: .launchApp, target: "Google Chrome")),
    ButtonConfig(row: 0, col: 1, label: "Safari", iconName: "safari", action: ActionPayload(type: .launchApp, target: "Safari")),
    ButtonConfig(row: 0, col: 2, label: "リンクを開く", iconName: "link", action: ActionPayload(type: .openURL, target: "https://example.com")),
    ButtonConfig(row: 0, col: 3, label: "コピー", iconName: "doc.on.doc", action: ActionPayload(type: .hotkey, keys: ["cmd", "c"])),
    ButtonConfig(row: 0, col: 4, label: "ペースト", iconName: "clipboard", action: ActionPayload(type: .hotkey, keys: ["cmd", "v"]))
  ]

  private static let chromeProfileButtons: [ButtonConfig] = [
    ButtonConfig(row: 0, col: 0, label: "新しいタブ", iconName: "plus.square", action: ActionPayload(type: .hotkey, keys: ["cmd", "t"])),
    ButtonConfig(row: 0, col: 1, label: "タブを閉じる", iconName: "xmark.square", action: ActionPayload(type: .hotkey, keys: ["cmd", "w"]))
  ]

  private static let defaultProfiles: [ProfileConfig] = [
    ProfileConfig(name: "デフォルト", triggerAppBundleId: nil, buttons: defaultButtons),
    ProfileConfig(name: "Chrome用", triggerAppBundleId: "com.google.Chrome", buttons: chromeProfileButtons)
  ]
}
