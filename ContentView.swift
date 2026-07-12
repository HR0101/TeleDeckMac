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
  let profileStore: ProfileStore

  @Environment(\.openWindow) private var openWindow

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Label(
          server.isRunning ? "接続待機中" : "サーバー停止中",
          systemImage: server.isRunning ? "dot.radiowaves.left.and.right" : "exclamationmark.circle"
        )
        .foregroundStyle(server.isRunning ? .green : .red)
        Spacer()
        if server.connectedDeviceName != nil {
          Text("接続済み")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.green)
        }
      }

      if let deviceName = server.connectedDeviceName {
        Label("接続中: \(deviceName)", systemImage: "ipad")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      VStack(alignment: .leading, spacing: 8) {
        Text("現在のプロファイル")
          .font(.caption)
          .foregroundStyle(.secondary)

        Menu {
          ForEach(profileStore.profiles) { profile in
            Button {
              profileStore.setActiveProfile(id: profile.id)
            } label: {
              if profile.id == profileStore.activeProfileId {
                Label(profile.name, systemImage: "checkmark")
              } else {
                Text(profile.name)
              }
            }
          }
        } label: {
          HStack {
            Image(systemName: "square.grid.3x3.fill")
              .foregroundStyle(.tint)
            Text(profileStore.activeProfile.name)
              .fontWeight(.semibold)
            Spacer()
            Image(systemName: "chevron.up.chevron.down")
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
          .padding(10)
          .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
        }
        .menuStyle(.borderlessButton)
      }

      Button {
        openWindow(id: "profile-editor")
      } label: {
        Label("パネルを編集", systemImage: "slider.horizontal.3")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.large)

      Divider()

      HStack {
        VStack(alignment: .leading, spacing: 3) {
          Text("ペアリングPIN")
            .font(.caption)
            .foregroundStyle(.secondary)
          Text(pairingManager.currentPIN)
            .font(.system(.title2, design: .monospaced, weight: .bold))
        }
        Spacer()
        Button {
          pairingManager.regeneratePIN()
        } label: {
          Image(systemName: "arrow.clockwise")
        }
        .help("PINを再発行")
      }

      if pairingManager.trustedDeviceName != nil {
        Button("ペアリングを解除", role: .destructive) {
          pairingManager.revokeTrustedDevice()
        }
      }

      Button("TeleDeckを終了") {
        NSApplication.shared.terminate(nil)
      }
      .foregroundStyle(.secondary)
    }
    .padding(16)
    .frame(width: 280)
  }
}

#Preview {
  let previewPairingManager = PairingManager()
  let previewProfileStore = ProfileStore()
  ContentView(
    pairingManager: previewPairingManager,
    server: BonjourServer(pairingManager: previewPairingManager, actionExecutor: ActionExecutor(), profileStore: previewProfileStore),
    profileStore: previewProfileStore
  )
}
