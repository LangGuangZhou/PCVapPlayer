//
//  PCBaseDFileInfo.swift
//  PCVapPlayer
//
//  Created by converting from Objective-C
//  Copyright © 2024. All rights reserved.
//

import Foundation

/// 文件信息基类协议
protocol PCBaseDFileInfo {
    var filePath: String { get set }
    var occupiedCount: Int { get set }
}

/// 文件信息基类
class PCBaseDFileInfoImpl: PCBaseDFileInfo {
    var filePath: String = ""
    var occupiedCount: Int = 0
}

