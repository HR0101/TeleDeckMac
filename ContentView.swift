//
//  ContentView.swift
//  TeleDeckMac
//
//  Created by hara ryuto   on 2026/07/12.
//
//  メニューバーを開いたときに表示するステータスパネル。
//  iPad版と世界観を揃えた紫ベースのゲーミングテーマで表示する。
//

import AppKit
import ServiceManagement
import SwiftUI

struct ContentView: View {
  let pairingManager: PairingManager
  let server: BonjourServer
  let profileStore: ProfileStore
  let permissionMonitor: PermissionMonitor

  @Environment(\.openWindow) private var openWindow
  @State private var loginItemStatus: SMAppService.Status = SMAppService.mainApp.status
  @State private var isShowingRevokeConfirmation = false
  /// PINとQRを表示するかどうか。画面共有中に不用意に映り込まないよう、
  /// ペアリング済みのときは既定で隠し、必要なときだけ開く
  @State private var isShowingPairingCredentials = false

  var body: some View {
    ZStack {
      // メニューバーの小さなポップオーバーでは、常時動き続ける背景グローが
      // 「ウインドウが動いている」ように見えて操作の邪魔になるため静止させる
      GamingBackground(animated: false)

      VStack(alignment: .leading, spacing: 14) {
        header
        permissionSection
        profileSection
        editPanelButton
        lastExecutionSection
        sectionDivider
        pairingSection
        sectionDivider
        loginAndQuitSection
      }
      .padding(18)
      .frame(width: 300)
    }
    .frame(width: 300)
    // ポップオーバーを開いた時点の状態を必ず反映させる（ポーリングの間隔を待たない）
    .onAppear {
      permissionMonitor.refresh()
    }
    .confirmationDialog(
      "ペアリングを解除しますか？",
      isPresented: $isShowingRevokeConfirmation,
      titleVisibility: .visible
    ) {
      Button("解除", role: .destructive) {
        pairingManager.revokeTrustedDevice()
      }
      Button("キャンセル", role: .cancel) {}
    } message: {
      Text("iPadとの接続情報が破棄され、新しいPINでのペアリングが必要になります。")
    }
  }

  // MARK: - ヘッダー（アプリ名 + 接続ステータス）

  private var header: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("TeleDeck")
          .font(.headline.weight(.bold))
          .foregroundStyle(GamingPalette.foreground)
        Spacer()
        statusPill
      }

      if let deviceName = server.connectedDeviceName {
        Label("接続中: \(deviceName)", systemImage: "ipad")
          .font(.caption)
          .foregroundStyle(GamingPalette.mutedForeground)
      }
    }
  }

  private var statusPill: some View {
    HStack(spacing: 6) {
      Circle()
        .fill(statusColor)
        .frame(width: 8, height: 8)
        .shadow(color: statusColor.opacity(0.8), radius: 4)
      Text(statusText)
        .font(.caption.weight(.semibold))
        .foregroundStyle(statusColor)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 5)
    .background(
      Capsule().fill(statusColor.opacity(0.12))
    )
    .overlay(
      Capsule().stroke(statusColor.opacity(0.4), lineWidth: 1)
    )
  }

  private var statusColor: Color {
    guard permissionMonitor.isAccessibilityTrusted else { return GamingPalette.warning }
    guard server.isRunning else { return GamingPalette.destructive }
    return server.connectedDeviceName != nil ? GamingPalette.success : GamingPalette.accent
  }

  /// iPadと接続できていても、権限が無ければ操作はMacへ届かない。
  /// 「接続済み」と表示してしまうと動かない理由が隠れるため、権限の状態を優先して示す
  private var statusText: String {
    guard permissionMonitor.isAccessibilityTrusted else { return "権限が必要" }
    guard server.isRunning else { return "停止中" }
    return server.connectedDeviceName != nil ? "接続済み" : "接続待機中"
  }

  // MARK: - アクセシビリティ権限

  /// 許可済みのときは確認用の一行に留め、未許可のときだけ対処を促すカードを出す
  @ViewBuilder
  private var permissionSection: some View {
    if permissionMonitor.isAccessibilityTrusted {
      Label("操作の権限: 許可済み", systemImage: "checkmark.shield")
        .font(.caption)
        .foregroundStyle(GamingPalette.mutedForeground)
    } else {
      accessibilityWarningCard
    }
  }

  private var accessibilityWarningCard: some View {
    VStack(alignment: .leading, spacing: 9) {
      Label("アクセシビリティの権限が必要です", systemImage: "exclamationmark.triangle.fill")
        .font(.caption.weight(.semibold))
        .foregroundStyle(GamingPalette.warning)

      Text("許可するまで、キー送信・文字入力・ウィンドウ配置・トラックパッドは動作しません。")
        .font(.caption2)
        .foregroundStyle(GamingPalette.mutedForeground)
        .fixedSize(horizontal: false, vertical: true)

      HStack(spacing: 8) {
        Button("許可する") {
          permissionMonitor.requestAccess()
        }
        .buttonStyle(GamingButtonStyle(isProminent: true))

        Button("システム設定") {
          PermissionMonitor.openAccessibilitySettings()
        }
        .buttonStyle(GamingButtonStyle())
      }
      .font(.caption)

      // 一度拒否するとmacOSは「許可する」のダイアログを出さなくなるため、その場合の導線を明示する
      Text("ダイアログが出ない場合は「システム設定」から手動で有効にしてください。")
        .font(.caption2)
        .foregroundStyle(GamingPalette.mutedForeground)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(11)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: 11, style: .continuous)
        .fill(GamingPalette.warning.opacity(0.12))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 11, style: .continuous)
        .stroke(GamingPalette.warning.opacity(0.45), lineWidth: 1)
    )
  }

  // MARK: - プロファイル選択

  private var profileSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("現在のプロファイル")
        .font(.caption)
        .foregroundStyle(GamingPalette.mutedForeground)

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
        Divider()
        Button {
          openWindow(id: "profile-editor")
        } label: {
          Label("新規プロファイルを作成…", systemImage: "plus.circle")
        }
        // 「新規作成・編集はMacで管理」という説明ラベルは、真上の作成ボタンと役割が重なるうえ
        // メニュー項目として並ぶと押せそうに見えるため置かない
      } label: {
        HStack(spacing: 10) {
          Image(systemName: "square.grid.3x3.fill")
            .foregroundStyle(GamingPalette.accent)
          Text(profileStore.activeProfile.name)
            .fontWeight(.semibold)
            .foregroundStyle(GamingPalette.foreground)
          Spacer()
          Image(systemName: "chevron.up.chevron.down")
            .font(.caption2)
            .foregroundStyle(GamingPalette.mutedForeground)
        }
        .padding(11)
        .gamingCard(cornerRadius: 10)
      }
      .menuStyle(.borderlessButton)
    }
  }

  private var editPanelButton: some View {
    Button {
      openWindow(id: "profile-editor")
    } label: {
      Label("パネルを編集", systemImage: "slider.horizontal.3")
        .fontWeight(.semibold)
        .frame(maxWidth: .infinity)
    }
    .buttonStyle(GamingButtonStyle(isProminent: true))
  }

  // MARK: - ペアリング

  /// ペアリング済みかどうか。済んでいればPIN・QRは通常不要なため隠しておく
  private var isPaired: Bool {
    pairingManager.trustedDeviceName != nil
  }

  /// PIN・QRを実際に表示するか。未ペアリング時は接続に必須のため常に開く
  private var showsPairingCredentials: Bool {
    !isPaired || isShowingPairingCredentials
  }

  private var pairingSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text("ペアリングPIN")
            .font(.caption)
            .foregroundStyle(GamingPalette.mutedForeground)

          if showsPairingCredentials {
            Text(pairingManager.currentPIN)
              .font(.system(.title, design: .monospaced, weight: .bold))
              .foregroundStyle(GamingPalette.foreground)
              .kerning(3)
          } else {
            // 画面共有中にメニューを開いてもPINが映らないよう伏せ字にする
            Text("••••••")
              .font(.system(.title, design: .monospaced, weight: .bold))
              .foregroundStyle(GamingPalette.mutedForeground)
              .kerning(3)
          }
        }

        Spacer()

        if isPaired {
          Button {
            isShowingPairingCredentials.toggle()
          } label: {
            Image(systemName: isShowingPairingCredentials ? "eye.slash" : "eye")
              .foregroundStyle(GamingPalette.accent)
              .padding(9)
              .gamingCard(cornerRadius: 9)
          }
          .buttonStyle(.plain)
          .help(isShowingPairingCredentials ? "PINを隠す" : "PINを表示")
        }

        Button {
          pairingManager.regeneratePIN()
          // 再発行した意味が伝わるよう、隠れている場合は自動的に開く
          isShowingPairingCredentials = true
        } label: {
          Image(systemName: "arrow.clockwise")
            .foregroundStyle(GamingPalette.accent)
            .padding(9)
            .gamingCard(cornerRadius: 9)
        }
        .buttonStyle(.plain)
        .help("PINを再発行")
      }

      if showsPairingCredentials {
        Text("iPadのペアリング画面で、この6桁PINを入力してください。")
          .font(.caption)
          .foregroundStyle(GamingPalette.mutedForeground)
          .fixedSize(horizontal: false, vertical: true)

        PairingQRCodeView(pin: pairingManager.currentPIN, deviceName: Host.current().localizedName)

        Text("または、iPadの「QRで接続」からこのQRコードを読み取ってください。")
          .font(.caption)
          .foregroundStyle(GamingPalette.mutedForeground)
          .fixedSize(horizontal: false, vertical: true)
      } else {
        Text("ペアリング済みです。新しいiPadを接続するときだけ、目のアイコンでPINを表示してください。")
          .font(.caption)
          .foregroundStyle(GamingPalette.mutedForeground)
          .fixedSize(horizontal: false, vertical: true)
      }

      if isPaired {
        Button {
          isShowingRevokeConfirmation = true
        } label: {
          Label("ペアリングを解除", systemImage: "xmark.shield")
            .font(.caption.weight(.medium))
            .foregroundStyle(GamingPalette.destructive)
        }
        .buttonStyle(.plain)
      }
    }
  }

  // MARK: - 直近の実行結果

  /// 失敗がどこにも残らないと原因を追えないため、最後に実行したアクションの結果を1行で示す
  @ViewBuilder
  private var lastExecutionSection: some View {
    if let log = server.lastExecutionLog {
      HStack(spacing: 8) {
        Image(systemName: log.succeeded ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
          .font(.caption)
          .foregroundStyle(log.succeeded ? GamingPalette.success : GamingPalette.destructive)

        Text(log.summary)
          .font(.caption)
          .foregroundStyle(GamingPalette.mutedForeground)
          .lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)

        Spacer(minLength: 0)

        Text(log.timestamp, style: .time)
          .font(.caption2.monospacedDigit())
          .foregroundStyle(GamingPalette.mutedForeground)
      }
      .padding(9)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: 9, style: .continuous)
          .fill(GamingPalette.muted.opacity(0.45))
      )
    }
  }

  // MARK: - ログイン自動起動 / 終了

  private var loginAndQuitSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      Toggle(isOn: launchAtLoginBinding) {
        Text("ログイン時に自動起動")
          .foregroundStyle(GamingPalette.foreground)
      }
      .toggleStyle(.switch)
      .tint(GamingPalette.accent)

      if loginItemStatus == .requiresApproval {
        Button("システム設定で承認する…") {
          SMAppService.openSystemSettingsLoginItems()
        }
        .font(.caption)
        .foregroundStyle(GamingPalette.warning)
        .buttonStyle(.plain)
      }

      Button {
        NSApplication.shared.terminate(nil)
      } label: {
        Label("TeleDeckを終了", systemImage: "power")
          .font(.caption.weight(.medium))
          .foregroundStyle(GamingPalette.mutedForeground)
      }
      .buttonStyle(.plain)
    }
  }

  private var sectionDivider: some View {
    Rectangle()
      .fill(GamingPalette.mutedForeground.opacity(0.15))
      .frame(height: 1)
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

// MARK: - ペアリングQRコード表示

/// ペアリングPINをQRコードとして表示する小さなビュー。
/// PINが再発行されたら（.task(id:)により）自動でQRを作り直す。
private struct PairingQRCodeView: View {
  let pin: String
  let deviceName: String?

  /// QRの表示サイズ（pt）
  private static let side: CGFloat = 150

  @State private var image: NSImage?

  var body: some View {
    Group {
      if let image {
        Image(nsImage: image)
          .interpolation(.none)
          .resizable()
          .frame(width: Self.side, height: Self.side)
          // QRコードは白地に黒が最も安定して読み取れるため、テーマに関わらず白背景で囲う
          .padding(10)
          .background(Color.white)
          .clipShape(RoundedRectangle(cornerRadius: 10))
      } else {
        RoundedRectangle(cornerRadius: 10)
          .fill(GamingPalette.mutedForeground.opacity(0.12))
          .frame(width: Self.side + 20, height: Self.side + 20)
          .overlay(ProgressView())
      }
    }
    .frame(maxWidth: .infinity)
    .task(id: pin) {
      // 表示は150ptだが、Retinaでも滲まないよう3倍相当の解像度で生成する
      let payload = PairingQRPayload(pin: pin, name: deviceName)
      image = try? PairingQRCode.makeImage(for: payload, sideLength: Self.side * 3)
    }
  }
}

#Preview {
  let previewPairingManager = PairingManager()
  let previewProfileStore = ProfileStore()
  ContentView(
    pairingManager: previewPairingManager,
    server: BonjourServer(pairingManager: previewPairingManager, actionExecutor: ActionExecutor(), profileStore: previewProfileStore),
    profileStore: previewProfileStore,
    permissionMonitor: PermissionMonitor()
  )
}
