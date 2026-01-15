//
//  PCVAPMaskInfo.swift
//  PCVapPlayer
//
//  Created by converting from Objective-C
//  Copyright © 2024. All rights reserved.
//

import Foundation
import UIKit
import Metal

/// VAP 遮罩信息
/// 如果要更新 data、rect、size 必须重新创建 PCVAPMaskInfo 对象
public class PCVAPMaskInfo {
    /// mask 数据 0/1 Byte
    public var data: Data
    
    /// 采样范围，与 dataSize 单位一致
    public var sampleRect: CGRect
    
    /// mask 大小，单位 pixel
    public var dataSize: CGSize
    
    /// 模糊范围，单位 pixel
    public var blurLength: Int
    
    /// mask 纹理（懒加载）
    private var _texture: MTLTexture?
    
    public var texture: MTLTexture? {
        if _texture == nil {
            // 需要 PCTextureLoader 和 MetalRenderer 的实现
            // _texture = PCTextureLoader.loadTexture(with: data, device: MetalRenderer.device, width: Int(dataSize.width), height: Int(dataSize.height))
        }
        return _texture
    }
    
    public init(data: Data, sampleRect: CGRect, dataSize: CGSize, blurLength: Int) {
        self.data = data
        self.sampleRect = sampleRect
        self.dataSize = dataSize
        self.blurLength = blurLength
    }
}

