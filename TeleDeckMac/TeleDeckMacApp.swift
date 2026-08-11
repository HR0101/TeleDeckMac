//
//  TeleDeckMacApp.swift
//  TeleDeckMac
//
//  Created by hara ryuto   on 2026/07/12.
//

import SwiftUI

@main
struct TeleDeckMacApp: App {
  @State private var pairingManager: PairingManager
  @State private var profileStore: ProfileStore
  @State private var server: BonjourServer
  @State private var permissionMonitor = PermissionMonitor()

  init() {
    let newPairingManager = PairingManager()
    let newProfileStore = ProfileStore()
    let newServer = BonjourServer(
      pairingManager: newPairingManager,
      actionExecutor: ActionExecutor(),
      profileStore: newProfileStore
    )
    // メニューバーのポップオーバーを開く前から動作している必要があるため、起動直後にサーバーを開始する
    newServer.start()
    _pairingManager = State(initialValue: newPairingManager)
    _profileStore = State(initialValue: newProfileStore)
    _server = State(initialValue: newServer)
  }

  /// アクセシビリティ権限が未許可の間は、ポップオーバーを開かなくても
  /// メニューバーのアイコンだけで対処が必要なことに気づけるようにする
  private var menuBarSystemImage: String {
    permissionMonitor.isAccessibilityTrusted
      ? "rectangle.grid.3x2.fill"
      : "exclamationmark.triangle.fill"
  }

  var body: some Scene {
    MenuBarExtra("TeleDeck", systemImage: menuBarSystemImage) {
      ContentView(
        pairingManager: pairingManager,
        server: server,
        profileStore: profileStore,
        permissionMonitor: permissionMonitor
      )
    }
    .menuBarExtraStyle(.window)

    Window("プロファイル設定", id: "profile-editor") {
      ProfileEditorView(profileStore: profileStore)
    }
    // サイドバー・編集キャンバス・インスペクタを同時に見せるための初期サイズ。
    // 実際の内容は狭い幅にも追従するが、起動直後から編集画面が見切れないようにする。
    .defaultSize(width: 1180, height: 700)
  }
}
