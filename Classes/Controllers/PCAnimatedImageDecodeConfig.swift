//
//  PCAnimatedImageDecodeConfig.swift
//  PCVapPlayer
//
//  Created by converting from Objective-C
//  Copyright © 2024. All rights reserved.
//

import Foundation

/// 动画图像解码配置
class PCAnimatedImageDecodeConfig {
    /// 线程数
    var threadCount: Int = 1
    
    /// 缓冲数
    var bufferCount: Int = 5
    
    /// 默认配置
    static func defaultConfig() -> PCAnimatedImageDecodeConfig {
        let config = PCAnimatedImageDecodeConfig()
        config.threadCount = 1
        config.bufferCount = 5
        return config
    }
}

