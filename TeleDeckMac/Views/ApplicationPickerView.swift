//
//  ApplicationPickerView.swift
//  TeleDeckMac
//
//  「アプリを選択」でFinderの階層を毎回たどらせるのは探しにくいため、
//  インストール済みアプリを名前で検索して選べる一覧シートを提供する。
//

import AppKit
import SwiftUI

struct InstalledApplication: Identifiable, Hashable {
  var id: String { url.path }
  let name: String
  let bundleIdentifier: String?
  let url: URL
}

enum InstalledApplicationScanner {
  /// アプリが実際に置かれている標準的な場所だけを浅く走査する。
  /// Spotlight検索(NSMetadataQuery)は非同期で結果が揺れやすいため、
  /// 「アプリを探しやすくする」目的にはこの単純な列挙で十分かつ即座に表示できる
  static func scan() -> [InstalledApplication] {
    let fileManager = FileManager.default

    var directories = [
      URL(fileURLWithPath: "/Applications"),
      URL(fileURLWithPath: "/System/Applications"),
      URL(fileURLWithPath: "/System/Applications/Utilities"),
    ]
    directories.append(contentsOf: fileManager.urls(for: .applicationDirectory, in: .userDomainMask))

    var seenPaths = Set<String>()
    var results: [InstalledApplication] = []

    for directory in directories {
      guard let entries = try? fileManager.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
      ) else { continue }

      for entry in entries where entry.pathExtension == "app" {
        guard seenPaths.insert(entry.path).inserted else { continue }
        let bundle = Bundle(url: entry)
        let name = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
          ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
          ?? entry.deletingPathExtension().lastPathComponent
        results.append(InstalledApplication(name: name, bundleIdentifier: bundle?.bundleIdentifier, url: entry))
      }
    }

    return results.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }
}

/// インストール済みアプリを検索して選べる一覧シート。
/// 標準的な場所にないアプリのために、Finderで直接選ぶ手段への導線も残す
struct ApplicationPickerView: View {
  var onSelect: (InstalledApplication) -> Void
  var onChooseFromFinder: () -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var applications: [InstalledApplication] = []
  @State private var searchText = ""

  private var filteredApplications: [InstalledApplication] {
    guard !searchText.isEmpty else { return applications }
    return applications.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
  }

  var body: some View {
    NavigationStack {
      List(filteredApplications) { app in
        Button {
          onSelect(app)
          dismiss()
        } label: {
          HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
              .resizable()
              .frame(width: 24, height: 24)
            Text(app.name)
            Spacer()
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      }
      .listStyle(.plain)
      .overlay {
        if applications.isEmpty {
          ProgressView()
        } else if filteredApplications.isEmpty {
          ContentUnavailableView.search(text: searchText)
        }
      }
      .searchable(text: $searchText, prompt: "アプリ名で検索")
      .navigationTitle("アプリを選択")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("キャンセル") { dismiss() }
        }
        ToolbarItem(placement: .primaryAction) {
          Button("Finderから選ぶ…") {
            dismiss()
            onChooseFromFinder()
          }
        }
      }
    }
    .frame(width: 380, height: 460)
    .onAppear {
      if applications.isEmpty {
        applications = InstalledApplicationScanner.scan()
      }
    }
  }
}
