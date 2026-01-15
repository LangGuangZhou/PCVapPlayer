//
//  PCWeakProxy.swift
//  PCVapPlayer
//
//  Created by converting from Objective-C
//  Copyright © 2024. All rights reserved.
//

import Foundation

/// 弱引用代理，用于避免循环引用
class PCWeakProxy: NSObject {
    weak var target: AnyObject?
    
    init(target: AnyObject) {
        self.target = target
        super.init()
    }
    
    static func proxy(with target: AnyObject) -> PCWeakProxy {
        return PCWeakProxy(target: target)
    }
    
    // 快速消息转发
    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        return target
    }
    
//    // 如果快速转发返回 nil，到标准消息转发处理
//    override func methodSignature(for aSelector: Selector!) -> MethodSignature? {
//        return NSObject.instanceMethodSignature(for: #selector(NSObject.init))
//    }
//    
//    override func forwardInvocation(_ anInvocation: Invocation) {
//        var null: Any? = nil
//        anInvocation.setReturnValue(&null)
//    }
//    
    override func responds(to aSelector: Selector!) -> Bool {
        return target?.responds(to: aSelector) ?? false
    }
}

