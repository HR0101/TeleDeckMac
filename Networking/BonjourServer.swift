//
//  BonjourServer.swift
//  TeleDeckMac
//
//  iPadからのWebSocket接続を受け付け、Bonjourで自身を公開するサーバー。
//

import Foundation
import Network
import Observation

@Observable
final class BonjourServer {
  private(set) var isRunning = false
  private(set) var connectedDeviceName: String?

  private var listener: NWListener?
  private var activeConnection: NWConnection?

  private let pairingManager: PairingManager
  private let actionExecutor: ActionExecutor

  private static let serviceType = "_teledeck._tcp"

  init(pairingManager: PairingManager, actionExecutor: ActionExecutor) {
    self.pairingManager = pairingManager
    self.actionExecutor = actionExecutor
  }

  /// サーバーを起動し、Bonjourで公開を開始する
  func start() {
    do {
      let webSocketOptions = NWProtocolWebSocket.Options()
      webSocketOptions.autoReplyPing = true

      let parameters = NWParameters.tcp
      parameters.defaultProtocolStack.applicationProtocols.insert(webSocketOptions, at: 0)

      let newListener = try NWListener(using: parameters)
      newListener.service = NWListener.Service(
        name: Host.current().localizedName ?? "TeleDeckMac",
        type: Self.serviceType
      )

      newListener.stateUpdateHandler = { [weak self] state in
        switch state {
        case .ready:
          self?.isRunning = true
        case .failed, .cancelled:
          self?.isRunning = false
        default:
          break
        }
      }

      newListener.newConnectionHandler = { [weak self] connection in
        self?.accept(connection)
      }

      newListener.start(queue: .main)
      listener = newListener
    } catch {
      print("サーバーの起動に失敗しました: \(error.localizedDescription)")
      isRunning = false
    }
  }

  func stop() {
    listener?.cancel()
    listener = nil
    activeConnection?.cancel()
    activeConnection = nil
    isRunning = false
    connectedDeviceName = nil
  }

  // MARK: - 接続処理

  private func accept(_ connection: NWConnection) {
    // フェーズ1は同時1台のみ対応。既存接続があれば切断して新しい接続に置き換える
    activeConnection?.cancel()
    activeConnection = connection

    connection.stateUpdateHandler = { [weak self] state in
      switch state {
      case .failed, .cancelled:
        self?.handleDisconnect(connection)
      default:
        break
      }
    }

    connection.start(queue: .main)
    receiveNextMessage(on: connection)
  }

  private func handleDisconnect(_ connection: NWConnection) {
    guard connection === activeConnection else { return }
    activeConnection = nil
    connectedDeviceName = nil
  }

  private func receiveNextMessage(on connection: NWConnection) {
    connection.receiveMessage { [weak self] data, _, _, error in
      guard let self else { return }

      if let error {
        print("受信エラー: \(error.localizedDescription)")
        return
      }

      if let data, !data.isEmpty {
        self.handleIncoming(data: data, connection: connection)
      }

      if connection.state == .ready {
        self.receiveNextMessage(on: connection)
      }
    }
  }

  // MARK: - メッセージ処理

  private func handleIncoming(data: Data, connection: NWConnection) {
    do {
      let envelope = try JSONDecoder().decode(MessageEnvelope.self, from: data)
      switch envelope.type {
      case "pair":
        let request = try JSONDecoder().decode(PairMessage.self, from: data)
        handlePair(request, on: connection)
      case "execute":
        let request = try JSONDecoder().decode(ExecuteMessage.self, from: data)
        handleExecute(request, on: connection)
      default:
        print("未知のメッセージ種別を受信しました: \(envelope.type)")
      }
    } catch {
      print("メッセージの解析に失敗しました: \(error.localizedDescription)")
    }
  }

  private func handlePair(_ request: PairMessage, on connection: NWConnection) {
    let result = pairingManager.verify(pin: request.pin)
    if result.success {
      connectedDeviceName = request.deviceName
    }
    let response = PairResultMessage(success: result.success, token: result.token, errorMessage: result.errorMessage)
    send(response, on: connection)
  }

  private func handleExecute(_ request: ExecuteMessage, on connection: NWConnection) {
    // ペアリング未完了の接続からのアクション実行は拒否する
    guard connectedDeviceName != nil else {
      let response = AckMessage(requestId: request.requestId, success: false, errorMessage: "ペアリングが完了していません")
      send(response, on: connection)
      return
    }

    actionExecutor.execute(request.action) { [weak self] result in
      let response: AckMessage
      switch result {
      case .success:
        response = AckMessage(requestId: request.requestId, success: true)
      case .failure(let error):
        response = AckMessage(requestId: request.requestId, success: false, errorMessage: error.localizedDescription)
      }
      self?.send(response, on: connection)
    }
  }

  private func send<T: Encodable>(_ message: T, on connection: NWConnection) {
    do {
      let data = try JSONEncoder().encode(message)
      let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
      let context = NWConnection.ContentContext(identifier: "message", metadata: [metadata])
      connection.send(content: data, contentContext: context, isComplete: true, completion: .contentProcessed { error in
        if let error {
          print("送信エラー: \(error.localizedDescription)")
        }
      })
    } catch {
      print("メッセージのエンコードに失敗しました: \(error.localizedDescription)")
    }
  }
}
