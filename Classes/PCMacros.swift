//
//  PCMacros.swift
//  PCVapPlayer
//
//  Created by converting from Objective-C
//  Copyright © 2024. All rights reserved.
//

import UIKit
import Metal

// MARK: - Constants

let kPCHWDMP4DefaultFPS: Int = 20      // 默认 fps
let kPCHWDMP4MinFPS: Int = 1           // 最小 fps
let PCHWDMP4MaxFPS: Int = 60           // 最大 fps
let PCVapMaxCompatibleVersion: Int = 2   // 最大兼容版本

// MARK: - Type Aliases

public typealias PCVAPView = UIView  // 特效播放容器

// MARK: - Enums

/// MP4 素材中每一帧 alpha 通道数据的位置
public enum PCTextureBlendMode: Int {
    case alphaLeft = 0      // 左侧 alpha
    case alphaRight = 1     // 右侧 alpha
    case alphaTop = 2       // 上侧 alpha
    case alphaBottom = 3    // 下侧 alpha
}

// MARK: - Type Definitions

/// 图片加载完成回调
public typealias PCVAPImageCompletionBlock = (UIImage?, Error?, String?) -> Void

/// 手势事件回调
public typealias PCVAPGestureEventBlock = (UIGestureRecognizer, Bool, PCVAPSourceDisplayItem?) -> Void

// MARK: - Metal Device

/// Metal 渲染器设备（全局共享）
var kPCHWDMetalRendererDevice: MTLDevice? = nil

// MARK: - Background Operation Type

/// 退后台时的行为
public enum PCHWDMP4EBOperationType: UInt {
    case stop = 0                    // 退后台时结束 VAP 播放
    case pauseAndResume = 1          // 退后台时暂停、回到前台时自动恢复
    case doNothing = 2               // VAP 自身不进行控制，当外部进行控制时可以使用这个
}

