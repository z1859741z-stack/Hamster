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

    // 用运行时选到的 App Group（与 FileManager.shareURL 同一组）；
    // 无可用组时把数据库放在沙盒目录。
    let baseURL = AppGroupResolver.resolvedGroupURL ?? FileManager.sandboxDirectory
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
