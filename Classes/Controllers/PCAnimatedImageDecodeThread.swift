//
//  PCAnimatedImageDecodeThread.swift
//  PCVapPlayer
//
//  Created by converting from Objective-C
//  Copyright © 2024. All rights reserved.
//

import Foundation

/// 动画图像解码线程
class PCAnimatedImageDecodeThread: Thread {
    /// 是否被解码器占用
    var occupied: Bool = false
    
    /// 线程标识信息
    var sequenceDec: String {
        #if DEBUG
        // 在 Swift 中，我们无法直接访问 private.seqNum
        // 可以使用其他方式生成唯一标识
        return "\(self.hash)"
        #else
        return self.description
        #endif
    }
}

