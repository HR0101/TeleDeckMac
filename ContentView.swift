//
//  ContentView.swift
//  TeleDeckMac
//
//  Created by hara ryuto   on 2026/07/12.
//
//  メニューバーを開いたときに表示するステータスパネル。
//

import AppKit
import ServiceManagement
import SwiftUI

struct ContentView: View {
  let pairingManager: PairingManager
  let server: BonjourServer
  let profileStore: ProfileStore

  @Environment(\.openWindow) private var openWindow
  @State private var loginItemStatus: SMAppService.Status = SMAppService.mainApp.status

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

      Divider()

      VStack(alignment: .leading, spacing: 4) {
        Toggle("ログイン時に自動起動", isOn: launchAtLoginBinding)

        if loginItemStatus == .requiresApproval {
          Button("システム設定で承認する…") {
            SMAppService.openSystemSettingsLoginItems()
          }
          .font(.caption)
          .foregroundStyle(.orange)
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

  // MARK: - ログイン時の自動起動

  /// requiresApproval（登録直後、システム設定でユーザーの承認待ちの状態）もONとして見せる。
  /// OFFにした場合のみ実際にunregisterする
  private var launchAtLoginBinding: Binding<Bool> {
    Binding(
      get: { loginItemStatus == .enabled || loginItemStatus == .requiresApproval },
      set: { setLaunchAtLogin($0) }
    )
  }

  private func setLaunchAtLogin(_ enabled: Bool) {
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
    } catch {
      print("ログイン時自動起動の設定に失敗しました: \(error.localizedDescription)")
    }
    loginItemStatus = SMAppService.mainApp.status
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
