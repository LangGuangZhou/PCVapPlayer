//
//  Dictionary+VAPUtil.swift
//  PCVapPlayer
//
//  Created by converting from Objective-C
//  Copyright © 2024. All rights reserved.
//

import Foundation
import UIKit

extension Dictionary where Key == String {
    /// 获取浮点数值
    func hwd_floatValue(for key: String) -> CGFloat {
        guard let value = self[key], !(value is NSNull) else { return 0.0 }
        
        if let number = value as? NSNumber {
            return CGFloat(number.floatValue)
        }
        if let string = value as? String {
            return CGFloat((string as NSString).floatValue)
        }
        return 0.0
    }
    
    /// 获取整数值
    func hwd_integerValue(for key: String) -> Int {
        guard let value = self[key], !(value is NSNull) else { return 0 }
        
        if let number = value as? NSNumber {
            return number.intValue
        }
        if let string = value as? String {
            return (string as NSString).integerValue
        }
        return 0
    }
    
    /// 获取字符串值
    func hwd_stringValue(for key: String) -> String {
        guard let value = self[key], !(value is NSNull) else { return "" }
        
        if let string = value as? String {
            return string
        }
        if let number = value as? NSNumber {
            return number.description
        }
        return ""
    }
    
    /// 获取字典值
    func hwd_dicValue(for key: String) -> [String: Any]? {
        guard let value = self[key] as? [String: Any] else { return nil }
        return value
    }
    
    /// 获取数组值
    func hwd_arrValue(for key: String) -> [Any]? {
        guard let value = self[key] as? [Any] else { return nil }
        return value
    }
}

