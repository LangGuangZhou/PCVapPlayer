//
//  PCAnimatedImageBufferManager.swift
//  PCVapPlayer
//
//  Created by converting from Objective-C
//  Copyright © 2024. All rights reserved.
//

import Foundation

/// 动画图像缓冲区管理器
class PCAnimatedImageBufferManager {
    /// 缓冲
    var buffers: PCSafeMutableArray<Any>
    
    private let config: PCAnimatedImageDecodeConfig
    
    init(config: PCAnimatedImageDecodeConfig) {
        self.config = config
        self.buffers = PCSafeMutableArray(capacity: config.bufferCount)
    }
    
    /// 取出指定的在缓冲区的帧，若不存在于缓冲区则返回空
    /// - Parameter frameIndex: 目标帧索引
    /// - Returns: 帧数据
    func getBufferedFrame(_ frameIndex: Int) -> PCBaseAnimatedImageFrameImpl? {
        if buffers.count == 0 {
            return nil
        }
        
        let bufferIndex = frameIndex % buffers.count
        if bufferIndex > buffers.count - 1 {
            return nil
        }
        
        guard let frame = buffers.object(at: bufferIndex) as? PCBaseAnimatedImageFrameImpl,
              frame.frameIndex == frameIndex else {
            return nil
        }
        
        return frame
    }
    
    /// 弹出视频帧
    /// - Returns: 帧数据
    func popVideoFrame() -> PCBaseAnimatedImageFrameImpl? {
        if buffers.count == 0 {
            return nil
        }
        
        guard let firstObject = buffers.firstObject as? PCBaseAnimatedImageFrameImpl else {
            return nil
        }
        
        buffers.removeObject(at: 0)
        return firstObject
    }
    
    /// 判断当前缓冲区是否被填满
    /// - Returns: 只有当缓冲区所有区域都被 PCBaseAnimatedImageFrameImpl 类型的数据填满才算缓冲区满
    func isBufferFull() -> Bool {
        var isFull = true
        
        for i in 0..<buffers.count {
            if buffers.object(at: i) as? PCBaseAnimatedImageFrameImpl == nil {
                isFull = false
                break
            }
        }
        
        return isFull && buffers.count > 0
    }
}

