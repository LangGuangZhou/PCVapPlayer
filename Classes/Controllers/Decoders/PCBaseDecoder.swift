//
//  PCBaseDecoder.swift
//  PCVapPlayer
//
//  Created by converting from Objective-C
//  Copyright © 2024. All rights reserved.
//

import Foundation

/// 解码器通知名称
let kPCVAPDecoderSeekStart = Notification.Name("kPCVAPDecoderSeekStart")
let kPCVAPDecoderSeekFinish = Notification.Name("kPCVAPDecoderSeekFinish")

/// 解码器基类协议
protocol PCBaseDecoderProtocol {
    var currentDecodeFrame: Int { get set }
    var fileInfo: PCBaseDFileInfo { get }
    
    func decodeFrame(_ frameIndex: Int, buffers: NSMutableArray) throws
    func shouldStopDecode(_ nextFrameIndex: Int) -> Bool
    func isFrameIndexBeyondEnd(_ frameIndex: Int) -> Bool
}

/// 解码器基类
class PCBaseDecoder: PCBaseDecoderProtocol {
    var currentDecodeFrame: Int = -1
    private let _fileInfo: PCBaseDFileInfo
    var fileInfo: PCBaseDFileInfo {
        return _fileInfo
    }
    
    required init(fileInfo: PCBaseDFileInfo) throws {
        self._fileInfo = fileInfo
        if let fileInfoImpl = fileInfo as? PCBaseDFileInfoImpl {
            fileInfoImpl.occupiedCount += 1
        }
    }
    
    /// 由具体子类实现
    /// 该方法在 decodeFrame 方法即将被调用时调用，如果返回 true 则停止解码工作
    /// - Parameter nextFrameIndex: 将要解码的帧索引
    /// - Returns: 是否需要继续解码
    func shouldStopDecode(_ nextFrameIndex: Int) -> Bool {
        // 子类实现
        return false
    }
    
    func isFrameIndexBeyondEnd(_ frameIndex: Int) -> Bool {
        return false
    }
    
    /// 在专用线程内解码指定帧并放入对应的缓冲区内
    /// - Parameters:
    ///   - frameIndex: 帧索引
    ///   - buffers: 缓冲
    func decodeFrame(_ frameIndex: Int, buffers: NSMutableArray) throws {
        // 子类实现
        fatalError("Subclass must implement decodeFrame(_:buffers:)")
    }
}

