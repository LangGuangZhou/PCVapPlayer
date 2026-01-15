//
//  UIGestureRecognizer+VAPUtil.swift
//  PCVapPlayer
//
//  Created by converting from Objective-C
//  Copyright © 2024. All rights reserved.
//

import UIKit

private var vapBlockKey: UInt8 = 0

private class GestureRecognizerBlockTarget {
    let block: (Any) -> Void
    
    init(block: @escaping (Any) -> Void) {
        self.block = block
    }
    
    @objc func invoke(_ sender: Any) {
        block(sender)
    }
}

extension UIGestureRecognizer {
    /// 使用 Block 初始化手势识别器
    convenience init(vapActionBlock block: @escaping (Any) -> Void) {
        self.init()
        addVapActionBlock(block)
    }
    
    /// 添加 VAP Action Block
    func addVapActionBlock(_ block: @escaping (Any) -> Void) {
        let target = GestureRecognizerBlockTarget(block: block)
        addTarget(target, action: #selector(GestureRecognizerBlockTarget.invoke(_:)))
        
        var targets = _vapAllGestureRecognizerBlockTargets()
        targets.add(target)
        objc_setAssociatedObject(self, &vapBlockKey, targets, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
    
    /// 移除所有 VAP Action Blocks
    func removeAllVapActionBlocks() {
        let targets = _vapAllGestureRecognizerBlockTargets()
        targets.forEach { target in
            removeTarget(target, action: #selector(GestureRecognizerBlockTarget.invoke(_:)))
        }
        targets.removeAllObjects()
    }
    
    private func _vapAllGestureRecognizerBlockTargets() -> NSMutableArray {
        if let targets = objc_getAssociatedObject(self, &vapBlockKey) as? NSMutableArray {
            return targets
        }
        let targets = NSMutableArray()
        objc_setAssociatedObject(self, &vapBlockKey, targets, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return targets
    }
}

