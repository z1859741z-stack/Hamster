//
//  RepeatGestureTimer.swift
//  KeyboardKit
//
//  Created by Daniel Saidi on 2021-01-28.
//  Copyright © 2021-2023 Daniel Saidi. All rights reserved.
//

import Foundation

/**
 This class is used to handle repeating actions on a
 keyboard button.

 该类用于处理键盘按钮上的重复操作。
 */
public class RepeatGestureTimer {
  public init() {}

  deinit { stop() }

  private var timer: Timer?

  private var startDate: Date?

  /**
   The timer tick interval at start.

   计时器起步间隔，默认为 0.1 秒
   */
  public var timeInterval: TimeInterval = 0.1

  /**
   The fastest tick interval the timer accelerates to.

   计时器加速到的最快间隔，默认为 0.05 秒（约 20 字/秒）
   */
  public var minimumTimeInterval: TimeInterval = 0.05

  /**
   How much the interval shortens after each tick.

   每次触发后间隔缩短的量，默认为 0.01 秒；
   0.1s 起步，每跳缩短 0.01s，约 0.4s 后达到 0.05s 最快间隔。
   */
  public var accelerationStep: TimeInterval = 0.01

  /// 当前间隔：一次 start 内从 timeInterval 递减到 minimumTimeInterval
  private var currentInterval: TimeInterval = 0.1
}

public extension RepeatGestureTimer {
  /**
   This shared timer can be used if you only need to track
   a single thing.

   如果您只需要跟踪一件事，就可以使用这种共享计时器。
   */
  static let shared = RepeatGestureTimer()
}

public extension RepeatGestureTimer {
  /**
   The time for how long the timer has been active.

   计时器已激活时长。
   */
  var duration: TimeInterval? {
    guard let date = startDate else { return nil }
    return Date().timeIntervalSince(date)
  }

  /**
   Whether or not the timer is active.

   计时器是否处于活动状态。
   */
  var isActive: Bool { timer != nil }

  /**
   Start the timer.

   启动计时器。起步间隔 timeInterval（0.1s），每次触发后缩短
   accelerationStep（0.01s），直到最快间隔 minimumTimeInterval（0.05s，
   约 20 字/秒）。
   */
  func start(action: @escaping () -> Void) {
    if isActive { return }
    stop()
    startDate = Date()
    currentInterval = timeInterval
    scheduleNext(action: action)
  }

  /// 以当前间隔安排下一次触发；触发后缩短间隔再安排下一次，直到最快间隔。
  private func scheduleNext(action: @escaping () -> Void) {
    let timer = Timer.scheduledTimer(withTimeInterval: currentInterval, repeats: false) { [weak self] _ in
      guard let self else { return }
      guard self.timer != nil else { return }
      action()
      guard self.timer != nil else { return }
      self.currentInterval = max(self.minimumTimeInterval, self.currentInterval - self.accelerationStep)
      self.scheduleNext(action: action)
    }
    self.timer = timer
    RunLoop.current.add(timer, forMode: .common)
  }

  /**
   Stop the timer.

   停止计时器。
   */
  func stop() {
    timer?.invalidate()
    timer = nil
    startDate = nil
  }
}

extension RepeatGestureTimer {
  /// 修改计时器启动时间
  func modifyStartDate(to date: Date) {
    startDate = date
  }
}
