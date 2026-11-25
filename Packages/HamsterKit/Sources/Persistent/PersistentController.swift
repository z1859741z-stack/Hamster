//
//  PersistentController.swift
//  HamsterApp
//
//  Created by morse on 16/3/2023.
//

import CoreData
import OSLog

struct PersistentController {
  static let shared = PersistentController()

  let container: NSPersistentContainer
  init() {
    let name = "HamsterApp"

    // 重签证书不带 App Group 时 containerURL 返回 nil，之前这里强解直接闪退；
    // 不可用时把数据库放在沙盒目录。
    let baseURL = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: HamsterConstants.appGroupName)
      ?? FileManager.sandboxDirectory
    let storeURL = baseURL.appendingPathComponent("\(name).sqlite")

    let storeDescription = NSPersistentStoreDescription(url: storeURL)
    container = NSPersistentContainer(name: name)
    container.persistentStoreDescriptions = [storeDescription]
    container.loadPersistentStores { _, error in
      if let error = error as NSError? {
        Logger.statistics.error("Persistent store load error \(error), \(error.userInfo)")
      }
    }
  }
}
