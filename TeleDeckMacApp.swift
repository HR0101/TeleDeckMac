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

  var body: some Scene {
    MenuBarExtra("TeleDeck", systemImage: "rectangle.grid.3x2.fill") {
      ContentView(pairingManager: pairingManager, server: server, profileStore: profileStore)
    }
    .menuBarExtraStyle(.window)

    Window("プロファイル設定", id: "profile-editor") {
      ProfileEditorView(profileStore: profileStore)
    }
    .defaultSize(width: 820, height: 560)
  }
}
