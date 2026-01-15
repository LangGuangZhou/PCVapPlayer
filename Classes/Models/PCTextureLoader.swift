//
//  PCTextureLoader.swift
//  PCVapPlayer
//
//  Created by converting from Objective-C
//  Copyright © 2024. All rights reserved.
//

import Foundation
import UIKit
import Metal
import MetalKit

/// VAP 纹理加载器
class PCTextureLoader {
    
    #if targetEnvironment(simulator)
    // 模拟器不支持 Metal，返回 nil
    static func loadVapColorFillBuffer(with color: UIColor?, device: MTLDevice) -> MTLBuffer? {
        return nil
    }
    
    static func loadTexture(with image: UIImage, device: MTLDevice) -> MTLTexture? {
        return nil
    }
    
    static func drawingImageForText(_ textStr: String, color: UIColor, size: CGSize, bold: Bool) -> UIImage? {
        return nil
    }
    
    static func getAppropriateFont(with text: String, rect: CGRect, designedSize: CGFloat, isBold: Bool, textSize: inout CGSize) -> UIFont? {
        return nil
    }
    #else
    
    /// 加载 VAP 颜色填充缓冲区
    /// - Parameters:
    ///   - color: 颜色
    ///   - device: Metal 设备
    /// - Returns: Metal 缓冲区
    static func loadVapColorFillBuffer(with color: UIColor?, device: MTLDevice) -> MTLBuffer? {
        var red: CGFloat = 0.0
        var green: CGFloat = 0.0
        var blue: CGFloat = 0.0
        var alpha: CGFloat = 0.0
        
        if let color = color {
            color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        }
        
        // PCVapAttachmentFragmentParameter 结构体定义
        // 注意：needOriginRGB: 0 表示使用颜色，1 表示使用原始 RGB
        let needOriginRGB: Int32 = (color != nil) ? 0 : 1
        let colorParams = PCVapAttachmentFragmentParameter(
            needOriginRGB: needOriginRGB,
            fillColor: simd_float4(Float(red), Float(green), Float(blue), Float(alpha))
        )
        
        let colorParamsSize = MemoryLayout<PCVapAttachmentFragmentParameter>.size
        return device.makeBuffer(bytes: [colorParams], length: colorParamsSize, options: kDefaultMTLResourceOption)
    }
    
    /// 从图片加载纹理
    /// - Parameters:
    ///   - image: 图片
    ///   - device: Metal 设备
    /// - Returns: Metal 纹理
    static func loadTexture(with image: UIImage, device: MTLDevice) -> MTLTexture? {
        guard image != nil else {
            PCVAPError(kPCVAPModuleCommon, "attemp to loadTexture with nil image")
            return nil
        }
        
        if #available(iOS 10.0, *) {
            let loader = MTKTextureLoader(device: device)
            let options: [MTKTextureLoader.Option: Any] = [
                .origin: MTKTextureLoader.Origin.flippedVertically,
                .SRGB: false
            ]
            
            do {
                guard let cgImage = image.cgImage else {
                    PCVAPError(kPCVAPModuleCommon, "attemp to loadTexture with nil cgImage")
                    return nil
                }
                let texture = try loader.newTexture(cgImage: cgImage, options: options)
                return texture
            } catch {
                PCVAPError(kPCVAPModuleCommon, "loadTexture error:\(error)")
                return nil
            }
        }
        
        return cg_loadTexture(with: image, device: device)
    }
    
    /// 从数据加载纹理
    /// - Parameters:
    ///   - data: 数据
    ///   - device: Metal 设备
    ///   - width: 宽度
    ///   - height: 高度
    /// - Returns: Metal 纹理
    static func loadTexture(with data: Data, device: MTLDevice, width: CGFloat, height: CGFloat) -> MTLTexture? {
        guard !data.isEmpty else {
            PCVAPError(kPCVAPModuleCommon, "attemp to loadTexture with nil data")
            return nil
        }
        
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm,
            width: Int(width),
            height: Int(height),
            mipmapped: false
        )
        
        guard let texture = device.makeTexture(descriptor: textureDescriptor) else {
            PCVAPError(kPCVAPModuleCommon, "load texture fail, cuz fail getting texture")
            return nil
        }
        
        let region = MTLRegionMake3D(0, 0, 0, Int(width), Int(height), 1)
        data.withUnsafeBytes { bytes in
            texture.replace(region: region, mipmapLevel: 0, withBytes: bytes.baseAddress!, bytesPerRow: Int(width))
        }
        
        return texture
    }
    
    /// 为文本绘制图片
    /// - Parameters:
    ///   - textStr: 文本字符串
    ///   - color: 颜色
    ///   - size: 大小
    ///   - bold: 是否粗体
    /// - Returns: 绘制的图片
    static func drawingImageForText(_ textStr: String, color: UIColor, size: CGSize, bold: Bool) -> UIImage? {
        guard !textStr.isEmpty else {
            PCVAPError(kPCVAPModuleCommon, "draw text resource fail cuz text is nil !!")
            return nil
        }
        
        let textColor = color ?? .black
        let rect = CGRect(x: 0, y: 0, width: size.width / 2.0, height: size.height / 2.0)
        var textSize = CGSize.zero
        
        guard let font = getAppropriateFont(with: textStr, rect: rect, designedSize: rect.size.height * 0.8, isBold: bold, textSize: &textSize) else {
            PCVAPError(kPCVAPModuleCommon, "draw text resource:\(textStr) fail cuz font is nil !!")
            return nil
        }
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byTruncatingTail
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraphStyle,
            .foregroundColor: textColor
        ]
        
        let scale = UIScreen.main.scale
        UIGraphicsBeginImageContextWithOptions(rect.size, false, scale)
        defer { UIGraphicsEndImageContext() }
        
        var drawRect = rect
        drawRect.origin.y = (rect.size.height - font.lineHeight) / 2.0
        
        textStr.draw(with: drawRect, options: .usesLineFragmentOrigin, attributes: attributes, context: nil)
        
        guard let image = UIGraphicsGetImageFromCurrentImageContext() else {
            PCVAPError(kPCVAPModuleCommon, "draw text resource:\(textStr) fail cuz UIGraphics fail.")
            return nil
        }
        
        return image
    }
    
    /// 使用 Core Graphics 加载纹理（iOS 9 兼容）
    private static func cg_loadTexture(with image: UIImage, device: MTLDevice) -> MTLTexture? {
        guard let imageRef = image.cgImage, device != nil else {
            PCVAPError(kPCVAPModuleCommon, "load texture fail, cuz device/image is nil")
            return nil
        }
        
        let width = CGFloat(imageRef.width)
        let height = CGFloat(imageRef.height)
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * Int(width)
        let bitsPerComponent = 8
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        
        let dataSize = Int(height) * Int(width) * bytesPerPixel
        guard let rawData = calloc(dataSize, MemoryLayout<UInt8>.size) else {
            PCVAPError(kPCVAPModuleCommon, "load texture fail, cuz alloc mem fail! width:\(width) height:\(height) bytesPerPixel:\(bytesPerPixel)")
            return nil
        }
        defer { free(rawData) }
        
        guard let context = CGContext(
            data: rawData,
            width: Int(width),
            height: Int(height),
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue).rawValue
        ) else {
            PCVAPError(kPCVAPModuleCommon, "CGBitmapContextCreate error width:\(width) height:\(height) bitsPerComponent:\(bitsPerComponent) bytesPerRow:\(bytesPerRow)")
            return nil
        }
        
        context.translateBy(x: 0, y: height)
        context.scaleBy(x: 1, y: -1)
        context.draw(imageRef, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: Int(width),
            height: Int(height),
            mipmapped: false
        )
        
        guard let texture = device.makeTexture(descriptor: textureDescriptor) else {
            PCVAPError(kPCVAPModuleCommon, "load texture fail, cuz fail getting texture")
            return nil
        }
        
        let region = MTLRegionMake3D(0, 0, 0, Int(width), Int(height), 1)
        texture.replace(region: region, mipmapLevel: 0, withBytes: rawData, bytesPerRow: bytesPerRow)
        
        return texture
    }
    
    /// 根据指定的字符内容和容器大小计算合适的字体
    /// - Parameters:
    ///   - text: 文本
    ///   - fitFrame: 适配框架
    ///   - designedSize: 设计字体大小
    ///   - isBold: 是否粗体
    ///   - textSize: 输出文本大小
    /// - Returns: 合适的字体
    static func getAppropriateFont(with text: String, rect: CGRect, designedSize: CGFloat, isBold: Bool, textSize: inout CGSize) -> UIFont? {
        let designedFont = isBold ? UIFont.boldSystemFont(ofSize: designedSize) : UIFont.systemFont(ofSize: designedSize)
        
        guard !text.isEmpty, !rect.equalTo(.zero), designedFont != nil else {
            textSize = rect.size
            return designedFont
        }
        
        var stringSize = text.size(withAttributes: [.font: designedFont])
        var fontSize = designedSize
        var remainExecuteCount = 100
        
        while stringSize.width > rect.size.width && fontSize > 2.0 && remainExecuteCount > 0 {
            fontSize *= 0.9
            remainExecuteCount -= 1
            let font = isBold ? UIFont.boldSystemFont(ofSize: fontSize) : UIFont.systemFont(ofSize: fontSize)
            stringSize = text.size(withAttributes: [.font: font])
        }
        
        if remainExecuteCount < 1 || fontSize < 5.0 {
            PCVAPEvent(kPCVAPModuleCommon, "data exception content:\(text) rect:\(rect) designedSize:\(designedSize) isBold:\(isBold)")
        }
        
        textSize = stringSize
        return isBold ? UIFont.boldSystemFont(ofSize: fontSize) : UIFont.systemFont(ofSize: fontSize)
    }
    
    #endif
}

