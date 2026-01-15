//
//  PCMetalUtil.swift
//  PCVapPlayer
//
//  Created by converting from Objective-C
//  Copyright © 2024. All rights reserved.
//

import Foundation
import UIKit
import AVFoundation

// MARK: - Constants

let kHWDAttachmentVertexFunctionName = "hwdAttachment_vertexShader"
let kVAPAttachmentVertexFunctionName = "vapAttachment_vertexShader"
let kVAPAttachmentFragmentFunctionName = "vapAttachment_FragmentShader"
let kVAPVertexFunctionName = "vap_vertexShader"
let kVAPYUVFragmentFunctionName = "vap_yuvFragmentShader"
let kVAPMaskFragmentFunctionName = "vap_maskFragmentShader"
let kVAPMaskBlurFragmentFunctionName = "vap_maskBlurFragmentShader"

let kVAPMTLVerticesIdentity: [Float] = [-1.0, -1.0, 0.0, 1.0, -1.0, 1.0, 0.0, 1.0, 1.0, -1.0, 0.0, 1.0, 1.0, 1.0, 0.0, 1.0]
let kVAPMTLTextureCoordinatesIdentity: [Float] = [0.0, 1.0, 0.0, 0.0, 1.0, 1.0, 1.0, 0.0]
let kVAPMTLTextureCoordinatesFor90: [Float] = [0.0, 0.0, 1.0, 0.0, 0.0, 1.0, 1.0, 1.0]

// MARK: - Metal Utility Functions

/// 替换数组元素
/// - Parameters:
///   - arr0: 目标数组
///   - arr1: 源数组
///   - size: 大小
func replaceArrayElements(_ arr0: inout [Float], _ arr1: [Float], size: Int) {
    guard arr0.count >= size && arr1.count >= size && size >= 0 else {
        assertionFailure("replaceArrayElements params illegal")
        return
    }
    for i in 0..<size {
        arr0[i] = arr1[i]
    }
}

/// 生成 Metal 顶点坐标（倒N形）
/// - Parameters:
///   - rect: 矩形
///   - containerSize: 容器大小
///   - vertices: 输出的顶点数组（16个元素）
///   - reverse: 是否反转
func genMTLVertices(_ rect: CGRect, containerSize: CGSize, vertices: inout [Float], reverse: Bool) {
    guard vertices.count >= 16 else {
        PCVAPError(kPCVAPModuleCommon, "generateMTLVertices params illegal.")
        assertionFailure("generateMTLVertices params illegal")
        return
    }
    
    guard containerSize.width > 0 && containerSize.height > 0 else {
        PCVAPError(kPCVAPModuleCommon, "generateMTLVertices params containerSize illegal.")
        assertionFailure("generateMTLVertices params containerSize illegal")
        return
    }
    
    let originX = -1.0 + 2.0 * Float(rect.origin.x / containerSize.width)
    let originY = 1.0 - 2.0 * Float(rect.origin.y / containerSize.height)
    let width = 2.0 * Float(rect.size.width / containerSize.width)
    let height = 2.0 * Float(rect.size.height / containerSize.height)
    
    if reverse {
        let tempVertices: [Float] = [
            originX, originY - height, 0.0, 1.0,
            originX, originY, 0.0, 1.0,
            originX + width, originY - height, 0.0, 1.0,
            originX + width, originY, 0.0, 1.0
        ]
        replaceArrayElements(&vertices, tempVertices, size: 16)
    } else {
        let tempVertices: [Float] = [
            originX, originY, 0.0, 1.0,
            originX, originY - height, 0.0, 1.0,
            originX + width, originY, 0.0, 1.0,
            originX + width, originY - height, 0.0, 1.0
        ]
        replaceArrayElements(&vertices, tempVertices, size: 16)
    }
}

/// 生成 Metal 纹理坐标（N形）
/// - Parameters:
///   - rect: 矩形
///   - containerSize: 容器大小
///   - coordinates: 输出的纹理坐标数组（8个元素）
///   - reverse: 是否反转
///   - degree: 旋转角度（预留字段）
func genMTLTextureCoordinates(_ rect: CGRect, containerSize: CGSize, coordinates: inout [Float], reverse: Bool, degree: Int) {
    guard coordinates.count >= 8 else {
        PCVAPError(kPCVAPModuleCommon, "generateMTLTextureCoordinates params coordinates illegal.")
        assertionFailure("generateMTLTextureCoordinates params coordinates illegal")
        return
    }
    
    guard containerSize.width > 0 && containerSize.height > 0 else {
        PCVAPError(kPCVAPModuleCommon, "generateMTLTextureCoordinates params containerSize illegal.")
        assertionFailure("generateMTLTextureCoordinates params containerSize illegal")
        return
    }
    
    let originX = Float(rect.origin.x / containerSize.width)
    let originY = Float(rect.origin.y / containerSize.height)
    let width = Float(rect.size.width / containerSize.width)
    let height = Float(rect.size.height / containerSize.height)
    
    if reverse {
        let tempCoordinates: [Float] = [
            originX, originY,
            originX, originY + height,
            originX + width, originY,
            originX + width, originY + height
        ]
        replaceArrayElements(&coordinates, tempCoordinates, size: 8)
    } else {
        let tempCoordinates: [Float] = [
            originX, originY + height,
            originX, originY,
            originX + width, originY + height,
            originX + width, originY
        ]
        replaceArrayElements(&coordinates, tempCoordinates, size: 8)
    }
}

/// 计算源大小（CenterFull 模式）
/// - Parameters:
///   - sourceSize: 源大小
///   - renderSize: 渲染大小
/// - Returns: 计算后的源大小
func vapSourceSizeForCenterFull(_ sourceSize: CGSize, _ renderSize: CGSize) -> CGSize {
    // source 大小完全包含 render 大小，直接返回中间部分
    if sourceSize.width >= renderSize.width && sourceSize.height >= renderSize.height {
        return sourceSize
    }
    let rectForAspectFill = vapRectWithContentModeInsideRect(
        CGRect(x: 0, y: 0, width: renderSize.width, height: renderSize.height),
        aspectRatio: sourceSize,
        contentMode: .scaleAspectFill
    )
    return rectForAspectFill.size
}

/// 计算矩形（CenterFull 模式）
/// - Parameters:
///   - sourceSize: 源大小
///   - renderSize: 渲染大小
/// - Returns: 计算后的矩形
func vapRectForCenterFull(_ sourceSize: CGSize, _ renderSize: CGSize) -> CGRect {
    // source 大小完全包含 render 大小，直接返回中间部分
    if sourceSize.width >= renderSize.width && sourceSize.height >= renderSize.height {
        return CGRect(
            x: (sourceSize.width - renderSize.width) / 2.0,
            y: (sourceSize.height - renderSize.height) / 2.0,
            width: renderSize.width,
            height: renderSize.height
        )
    }
    
    let rectForAspectFill = vapRectWithContentModeInsideRect(
        CGRect(x: 0, y: 0, width: renderSize.width, height: renderSize.height),
        aspectRatio: sourceSize,
        contentMode: .scaleAspectFill
    )
    
    let intersection = CGRect(
        x: -rectForAspectFill.origin.x,
        y: -rectForAspectFill.origin.y,
        width: renderSize.width,
        height: renderSize.height
    )
    return intersection
}

/// 根据内容模式计算矩形
/// - Parameters:
///   - boundingRect: 边界矩形
///   - aspectRatio: 宽高比
///   - contentMode: 内容模式
/// - Returns: 计算后的矩形
func vapRectWithContentModeInsideRect(_ boundingRect: CGRect, aspectRatio: CGSize, contentMode: UIView.ContentMode) -> CGRect {
    guard aspectRatio.width > 0 && aspectRatio.height > 0 else {
        return boundingRect
    }
    
    var desRect = CGRect.zero
    
    switch contentMode {
    case .scaleToFill:
        desRect = boundingRect
        
    case .scaleAspectFit:
        desRect = AVMakeRect(aspectRatio: aspectRatio, insideRect: boundingRect)
        
    case .scaleAspectFill:
        let ratio = max(boundingRect.width / aspectRatio.width, boundingRect.height / aspectRatio.height)
        let contentSize = CGSize(width: aspectRatio.width * ratio, height: aspectRatio.height * ratio)
        desRect = CGRect(
            x: boundingRect.origin.x + (boundingRect.width - contentSize.width) / 2.0,
            y: boundingRect.origin.y + (boundingRect.height - contentSize.height) / 2.0,
            width: contentSize.width,
            height: contentSize.height
        )
        
    case .center:
        desRect = CGRect(
            x: boundingRect.origin.x + (boundingRect.width - aspectRatio.width) / 2.0,
            y: boundingRect.origin.y + (boundingRect.height - aspectRatio.height) / 2.0,
            width: aspectRatio.width,
            height: aspectRatio.height
        )
        
    case .top:
        desRect = CGRect(
            x: boundingRect.origin.x + (boundingRect.width - aspectRatio.width) / 2.0,
            y: boundingRect.origin.y,
            width: aspectRatio.width,
            height: aspectRatio.height
        )
        
    case .bottom:
        desRect = CGRect(
            x: boundingRect.origin.x + (boundingRect.width - aspectRatio.width) / 2.0,
            y: boundingRect.origin.y + boundingRect.height - aspectRatio.height,
            width: aspectRatio.width,
            height: aspectRatio.height
        )
        
    case .left:
        desRect = CGRect(
            x: boundingRect.origin.x,
            y: boundingRect.origin.y + (boundingRect.height - aspectRatio.height) / 2.0,
            width: aspectRatio.width,
            height: aspectRatio.height
        )
        
    case .right:
        desRect = CGRect(
            x: boundingRect.origin.x + boundingRect.width - aspectRatio.width,
            y: boundingRect.origin.y + (boundingRect.height - aspectRatio.height) / 2.0,
            width: aspectRatio.width,
            height: aspectRatio.height
        )
        
    case .topLeft:
        desRect = CGRect(
            x: boundingRect.origin.x,
            y: boundingRect.origin.y,
            width: aspectRatio.width,
            height: aspectRatio.height
        )
        
    case .topRight:
        desRect = CGRect(
            x: boundingRect.origin.x + boundingRect.width - aspectRatio.width,
            y: boundingRect.origin.y,
            width: aspectRatio.width,
            height: aspectRatio.height
        )
        
    case .bottomLeft:
        desRect = CGRect(
            x: boundingRect.origin.x,
            y: boundingRect.origin.y + boundingRect.height - aspectRatio.height,
            width: aspectRatio.width,
            height: aspectRatio.height
        )
        
    case .bottomRight:
        desRect = CGRect(
            x: boundingRect.origin.x + boundingRect.width - aspectRatio.width,
            y: boundingRect.origin.y + boundingRect.height - aspectRatio.height,
            width: aspectRatio.width,
            height: aspectRatio.height
        )
        
    case .redraw:
        desRect = boundingRect
        
    @unknown default:
        desRect = boundingRect
    }
    
    return desRect
}

/// Metal 工具类
class PCMetalUtil {
    // 空类，用于命名空间
}

