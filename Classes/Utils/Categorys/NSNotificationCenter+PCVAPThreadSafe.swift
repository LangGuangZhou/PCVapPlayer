//
//  NSNotificationCenter+VAPThreadSafe.swift
//  PCVapPlayer
//
//  Created by converting from Objective-C
//  Copyright © 2024. All rights reserved.
//

import Foundation

extension NotificationCenter {
    /// 线程安全地添加观察者
    func hwd_addSafeObserver(_ observer: Any, selector: Selector, name: NSNotification.Name?, object: Any?) {
        if Thread.isMainThread {
            addObserver(observer, selector: selector, name: name, object: object)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.addObserver(observer, selector: selector, name: name, object: object)
            }
        }
    }
    
    /// 线程安全地移除观察者
    func hwd_removeSafeObserver(_ observer: Any, name: NSNotification.Name?, object: Any?) {
        if Thread.isMainThread {
            removeObserver(observer, name: name, object: object)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.removeObserver(observer, name: name, object: object)
            }
        }
    }
}

