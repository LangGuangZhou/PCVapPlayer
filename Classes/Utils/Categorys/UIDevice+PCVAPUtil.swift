//
//  UIDevice+VAPUtil.swift
//  PCVapPlayer
//
//  Created by converting from Objective-C
//  Copyright © 2024. All rights reserved.
//

import UIKit
import Metal

/// 获取系统版本号
var kHWDSystemVersion: Double {
    return UIDevice.systemVersionNum
}

/// iOS 9 及以后版本
var kHWDiOS9Later: Bool {
    return kHWDSystemVersion >= 9.0
}

/// 获取默认 Metal 资源选项
func getDefaultMTLResourceOption() -> MTLResourceOptions {
    return .storageModeShared
}

var kDefaultMTLResourceOption: MTLResourceOptions {
    return getDefaultMTLResourceOption()
}

extension UIDevice {
    /// 获取系统版本号（数字）
    static var systemVersionNum: Double {
        struct Static {
            static var version: Double = 0
            static var onceToken: Int = 0
        }
        
        if Static.onceToken == 0 {
            Static.version = UIDevice.current.systemVersion.doubleValue ?? 0
            Static.onceToken = 1
        }
        return Static.version
    }
}

extension String {
    var doubleValue: Double? {
        return Double(self)
    }
}

