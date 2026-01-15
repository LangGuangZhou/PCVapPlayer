//
//  PCBaseAnimatedImageFrame.swift
//  PCVapPlayer
//
//  Created by converting from Objective-C
//  Copyright © 2024. All rights reserved.
//

import Foundation

/// 动画帧基类协议
public protocol PCBaseAnimatedImageFrame {
    var frameIndex: Int { get set }
    var duration: TimeInterval { get set }
    var pts: UInt64 { get set }
}

/// 动画帧基类
public class PCBaseAnimatedImageFrameImpl: PCBaseAnimatedImageFrame {
    public var frameIndex: Int = 0
    public var duration: TimeInterval = 0
    public var pts: UInt64 = 0
    
    // Displaying 相关属性
    var startDate: Date?
    var decodeTime: TimeInterval = 0
    
    /// 是否需要结束播放（根据播放时长来决定）
    func shouldFinishDisplaying() -> Bool {
        guard let startDate = startDate else {
            return true
        }
        let timeInterval = Date().timeIntervalSince(startDate)
        // 每一个 VSYNC 16ms，加上 10ms 容差
        return timeInterval * 1000 + 10 >= duration
    }
}

