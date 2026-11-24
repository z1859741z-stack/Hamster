//
//  IntentProvider.swift
//  Hamster
//
//  Created by morse on 2023/9/25.
//

import AppIntents

@available(iOS 16.0, *)
struct IntentProvider: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    return [
      AppShortcut(intent: RimeDeployIntent(), phrases: ["RIME Deploy", "RIME 重新部署"]),
    ]
  }
}
