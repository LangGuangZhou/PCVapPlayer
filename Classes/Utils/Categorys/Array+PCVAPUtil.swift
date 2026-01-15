//
//  Array+VAPUtil.swift
//  PCVapPlayer
//
//  Created by converting from Objective-C
//  Copyright © 2024. All rights reserved.
//

import Foundation
import UIKit

extension Array where Element == Any {
    /// 从数组转换为 CGRect
    /// 数组格式：[x, y, width, height]
    func hwd_rectValue() -> CGRect {
        if count < 4 {
            return .zero
        }
        
        for i in 0..<Swift.min(4, count) {
            let value = self[i]
            if !(value is String) && !(value is NSNumber) {
                return .zero
            }
        }
        
        let x = (self[0] as? NSNumber)?.floatValue ?? (self[0] as? String)?.floatValue ?? 0
        let y = (self[1] as? NSNumber)?.floatValue ?? (self[1] as? String)?.floatValue ?? 0
        let width = (self[2] as? NSNumber)?.floatValue ?? (self[2] as? String)?.floatValue ?? 0
        let height = (self[3] as? NSNumber)?.floatValue ?? (self[3] as? String)?.floatValue ?? 0
        
        return CGRect(x: CGFloat(x), y: CGFloat(y), width: CGFloat(width), height: CGFloat(height))
    }
}

extension String {
    var floatValue: Float? {
        return Float(self)
    }
}

