//
//  PCAnimatedImageDecodeThreadPool.swift
//  PCVapPlayer
//
//  Created by converting from Objective-C
//  Copyright © 2024. All rights reserved.
//

import Foundation

/// 动画图像解码线程池
class PCAnimatedImageDecodeThreadPool {
    private var threads: PCSafeMutableArray<Any>
    
    private init() {
        threads = PCSafeMutableArray()
    }
    
    /// 共享线程池（单例）
    static let shared = PCAnimatedImageDecodeThreadPool()
    
    /// 从池子中找出没被占用的线程，如果没有则新建一个
    /// - Returns: 解码线程
    func getDecodeThread() -> PCAnimatedImageDecodeThread {
        var freeThread: PCAnimatedImageDecodeThread?
        
        // 查找空闲线程
        for i in 0..<threads.count {
            if let decodeThread = threads.object(at: i) as? PCAnimatedImageDecodeThread,
               !decodeThread.occupied {
                freeThread = decodeThread
                break
            }
        }
        
        // 如果没有空闲线程，创建新线程
        if freeThread == nil {
            freeThread = PCAnimatedImageDecodeThread(target: self, selector: #selector(run), object: nil)
            freeThread?.start()
            threads.add(freeThread!)
        }
        
        return freeThread!
    }
    
    /// 线程保活
    @objc private func run() {
        autoreleasepool {
            let runLoop = RunLoop.current
            runLoop.add(Port(), forMode: .default)
            runLoop.run()
        }
    }
}

