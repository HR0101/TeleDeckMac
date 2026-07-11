//
//  ContentView.swift
//  TeleDeckMac
//
//  Created by hara ryuto   on 2026/07/12.
//
//  メニューバーを開いたときに表示するステータスパネル。
//

import AppKit
import SwiftUI

struct ContentView: View {
  let pairingManager: PairingManager
  let server: BonjourServer

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Label(
        server.isRunning ? "サーバー起動中" : "サーバー停止中",
        systemImage: server.isRunning ? "checkmark.circle.fill" : "xmark.circle"
      )
      .foregroundStyle(server.isRunning ? .green : .red)

      Divider()

      VStack(alignment: .leading, spacing: 4) {
        Text("ペアリングPIN")
          .font(.caption)
          .foregroundStyle(.secondary)
        Text(pairingManager.currentPIN)
          .font(.system(.title, design: .monospaced, weight: .bold))
      }

      if let deviceName = server.connectedDeviceName {
        Divider()
        Label("接続中: \(deviceName)", systemImage: "ipad")
      }

      Divider()

      Button("PINを再発行") {
        pairingManager.regeneratePIN()
      }

      Button("終了") {
        NSApplication.shared.terminate(nil)
      }
    }
    .padding()
    .frame(width: 240)
  }
}

#Preview {
  ContentView(pairingManager: PairingManager(), server: BonjourServer(pairingManager: PairingManager(), actionExecutor: ActionExecutor()))
}
