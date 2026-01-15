//
//  PCVAPConfigModel.swift
//  PCVapPlayer
//
//  Created by converting from Objective-C
//  Copyright © 2024. All rights reserved.
//

import Foundation
import UIKit
import Metal

// MARK: - Enums

/// VAP 方向
enum VAPOrientation: Int {
    case none = 0          // 兼容
    case portrait = 1      // 竖屏
    case landscape = 2     // 横屏
}

// MARK: - Type Aliases

typealias AttachmentSourceType = String      // 资源类型
typealias AttachmentSourceLoadType = String  // 资源加载类型
typealias AttachmentSourceStyle = String     // 字体
typealias AttachmentFitType = String         // 资源适配类型

// MARK: - Constants

let kQGAGAttachmentFitTypeFitXY: AttachmentFitType = "fitXY"              // 按指定尺寸缩放
let kQGAGAttachmentFitTypeCenterFull: AttachmentFitType = "centerFull"     // 默认按资源尺寸展示，如果资源尺寸小于遮罩，则等比缩放至可填满

let kQGAGAttachmentSourceTypeTextStr: AttachmentSourceType = "textStr"     // 文字
let kQGAGAttachmentSourceTypeImgUrl: AttachmentSourceType = "imgUrl"       // 图片
let kQGAGAttachmentSourceTypeText: AttachmentSourceType = "txt"             // 文字
let kQGAGAttachmentSourceTypeImg: AttachmentSourceType = "img"             // 图片

let QGAGAttachmentSourceLoadTypeLocal: AttachmentSourceLoadType = "local"
let QGAGAttachmentSourceLoadTypeNet: AttachmentSourceLoadType = "net"

let kQGAGAttachmentSourceStyleBoldText: AttachmentSourceStyle = "b"         // 粗体

// MARK: - PCVAPConfigModel

/// VAP 配置模型
public class PCVAPConfigModel {
    var info: VAPCommonInfo?
    var resources: [VAPSourceInfo] = []
    var mergedConfig: [Int: [VAPMergedInfo]] = [:]  // 帧索引 -> 融合信息数组
}

// MARK: - VAPCommonInfo

/// VAP 通用信息
class VAPCommonInfo {
    var version: Int = 0
    var framesCount: Int = 0
    var size: CGSize = .zero
    var videoSize: CGSize = .zero
    var targetOrientaion: VAPOrientation = .none
    var fps: Int = 0
    var isMerged: Bool = false
    var alphaAreaRect: CGRect = .zero
    var rgbAreaRect: CGRect = .zero
}

// MARK: - VAPSourceInfo

/// VAP 资源信息
public class VAPSourceInfo {
    // 原始信息
    var type: AttachmentSourceType = ""
    var loadType: AttachmentSourceLoadType = ""
    var contentTag: String = ""
    var contentTagValue: String = ""
    var color: UIColor?
    var style: AttachmentSourceStyle = ""
    var size: CGSize = .zero
    var fitType: AttachmentFitType = ""
    
    // 加载内容
    var sourceImage: UIImage?
    var texture: MTLTexture?
    var colorParamsBuffer: MTLBuffer?
}

// MARK: - PCVAPSourceDisplayItem

/// VAP 资源显示项
class PCVAPSourceDisplayItem {
    var frame: CGRect = .zero
    var sourceInfo: VAPSourceInfo?
}

// MARK: - VAPMergedInfo

/// VAP 融合信息
class VAPMergedInfo {
    var source: VAPSourceInfo?
    var renderIndex: Int = 0
    var renderRect: CGRect = .zero
    var needMask: Bool = false
    var maskRect: CGRect = .zero
    var maskRotation: Int = 0
    
    /// 生成顶点缓冲区
    /// - Parameters:
    ///   - size: 容器大小
    ///   - maskContainerSize: 遮罩容器大小
    ///   - device: Metal 设备
    /// - Returns: 顶点缓冲区
    func vertexBuffer(containerSize size: CGSize, maskContainerSize mSize: CGSize, device: MTLDevice) -> MTLBuffer? {
        if size.width <= 0 || size.height <= 0 || mSize.width <= 0 || mSize.height <= 0 {
            PCVAPError(kPCVAPModuleCommon, "vertexBufferWithContainerSize size error! :\(size) - \(mSize)")
            assertionFailure("vertexBufferWithContainerSize size error!")
            return nil
        }
        
        let columnCountForVertices = 4
        let columnCountForCoordinate = 2
        let vertexDataLength = 32
        
        var vertices: [Float] = Array(repeating: 0, count: 16)
        var maskCoordinates: [Float] = Array(repeating: 0, count: 8)
        var sourceCoordinates: [Float] = Array(repeating: 0, count: 8)
        
        genMTLVertices(renderRect, containerSize: size, vertices: &vertices, reverse: false)
        genMTLTextureCoordinates(maskRect, containerSize: mSize, coordinates: &maskCoordinates, reverse: true, degree: maskRotation)
        
        if let source = source, source.fitType == kQGAGAttachmentFitTypeCenterFull {
            let sourceRect = vapRectForCenterFull(source.size, renderRect.size)
            let sourceSize = vapSourceSizeForCenterFull(source.size, renderRect.size)
            genMTLTextureCoordinates(sourceRect, containerSize: sourceSize, coordinates: &sourceCoordinates, reverse: false, degree: 0)
        } else {
            sourceCoordinates = Array(kVAPMTLTextureCoordinatesIdentity)
        }
        
        var vertexData: [Float] = Array(repeating: 0, count: vertexDataLength)
        var indexForVertexData = 0
        
        // 顶点数据 + 纹理坐标 + 遮罩纹理坐标
        for i in 0..<16 {
            vertexData[indexForVertexData] = vertices[i]
            indexForVertexData += 1
            
            if i % columnCountForVertices == columnCountForVertices - 1 {
                let row = i / columnCountForVertices
                vertexData[indexForVertexData] = sourceCoordinates[row * columnCountForCoordinate]
                indexForVertexData += 1
                vertexData[indexForVertexData] = sourceCoordinates[row * columnCountForCoordinate + 1]
                indexForVertexData += 1
                vertexData[indexForVertexData] = maskCoordinates[row * columnCountForCoordinate]
                indexForVertexData += 1
                vertexData[indexForVertexData] = maskCoordinates[row * columnCountForCoordinate + 1]
                indexForVertexData += 1
            }
        }
        
        let allocationSize = vertexDataLength * MemoryLayout<Float>.size
        return device.makeBuffer(bytes: vertexData, length: allocationSize, options: kDefaultMTLResourceOption)
    }
}

