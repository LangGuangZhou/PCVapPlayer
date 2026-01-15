//
//  PCVAPMetalRenderer.swift
//  PCVapPlayer
//
//  Created by converting from Objective-C
//  Copyright © 2024. All rights reserved.
//

import Foundation
import UIKit
import Metal
import MetalKit
import CoreVideo
import simd

#if targetEnvironment(simulator)
// 模拟器不支持 Metal
class PCVAPMetalRenderer {
    var commonInfo: VAPCommonInfo?
    var maskInfo: PCVAPMaskInfo?
    
    init(metalLayer: Any) {
        // 模拟器不支持
    }
    
    func renderPixelBuffer(_ pixelBuffer: CVPixelBuffer, metalLayer: Any, mergeInfos: [VAPMergedInfo]?) {
        // 模拟器不支持
    }
    
    func dispose() {
        // 模拟器不支持
    }
}
#else

// MARK: - Constants
// 注意：kQGBlurWeightMatrixDefault 已在 PCHWDMetalRenderer.swift 中定义

/// VAP Metal 渲染器
class PCVAPMetalRenderer {
    var commonInfo: VAPCommonInfo? {
        didSet {
            updateMainVertexBuffer()
        }
    }
    
    var maskInfo: PCVAPMaskInfo? {
        didSet {
            if let maskInfo = maskInfo {
                if maskInfo.data == nil || maskInfo.dataSize.width <= 0 || maskInfo.dataSize.height <= 0 {
                    PCVAPError(kPCVAPModuleCommon, "setMaskInfo fail: data:\(String(describing: maskInfo.data)), size:\(maskInfo.dataSize)")
                    return
                }
            }
            if _maskInfo === maskInfo {
                return
            }
            _maskInfo = maskInfo
            if vertexBuffer != nil {
                updateMainVertexBuffer()
            }
        }
    }
    
    private var _maskInfo: PCVAPMaskInfo?
    
    private var renderingResourcesDisposed = false
    private var currentColorConversionMatrix: matrix_float3x3 = kQGColorConversionMatrix601FullRangeDefault
    
    private var vertexBuffer: MTLBuffer?
    private var yuvMatrixBuffer: MTLBuffer?
    private var _defaultMainPipelineState: MTLRenderPipelineState?
    private var _mainPipelineStateForMask: MTLRenderPipelineState?
    private var _mainPipelineStateForMaskBlur: MTLRenderPipelineState?
    private var commandQueue: MTLCommandQueue?
    private var videoTextureCache: CVMetalTextureCache?
    private var shaderFuncLoader: PCMetalShaderFunctionLoader?
    private weak var metalLayer: CAMetalLayer?
    
    init(metalLayer: CAMetalLayer) {
        if kPCHWDMetalRendererDevice == nil {
            kPCHWDMetalRendererDevice = MTLCreateSystemDefaultDevice()
        }
        
        metalLayer.device = kPCHWDMetalRendererDevice
        self.metalLayer = metalLayer
        setupRenderContext()
    }
    
    /// 回收渲染数据，减少内存占用
    func dispose() {
        commandQueue = nil
        vertexBuffer = nil
        yuvMatrixBuffer = nil
        _maskBlurBuffer = nil
        _attachmentPipelineState = nil
        shaderFuncLoader = nil
        
        if let cache = videoTextureCache {
            CVMetalTextureCacheFlush(cache, 0)
            videoTextureCache = nil
        }
        
        renderingResourcesDisposed = true
        _mainPipelineStateForMask = nil
        _mainPipelineStateForMaskBlur = nil
        _defaultMainPipelineState = nil
    }
    
    deinit {
        dispose()
    }
    
    private func setupRenderContext() {
        guard let device = kPCHWDMetalRendererDevice else { return }
        
        // constants
        currentColorConversionMatrix = kQGColorConversionMatrix601FullRangeDefault
        let yuvMatrixs = [PCColorParameters(matrix: currentColorConversionMatrix, offset: simd_float2(0.5, 0.5))]
        // 修复：使用 stride 而不是 size，因为 Metal 着色器需要对齐到 16 字节边界
        // size=56, stride=64，Metal 着色器期望 64 字节
        let yuvMatrixsDataSize = MemoryLayout<PCColorParameters>.stride
        yuvMatrixBuffer = device.makeBuffer(bytes: yuvMatrixs, length: yuvMatrixsDataSize, options: kDefaultMTLResourceOption)
        
        // function loader
        shaderFuncLoader = PCMetalShaderFunctionLoader(device: device)
        
        // command queue
        commandQueue = device.makeCommandQueue()
        
        // texture cache
        var textureCache: CVMetalTextureCache?
        let textureCacheError = CVMetalTextureCacheCreate(
            kCFAllocatorDefault,
            nil,
            device,
            nil,
            &textureCache
        )
        
        if textureCacheError != kCVReturnSuccess {
            PCVAPError(kPCVAPModuleCommon, "create texture cache fail!:\(textureCacheError)")
        }
        
        videoTextureCache = textureCache
    }
    
    /// 渲染像素缓冲区和融合信息
    /// - Parameters:
    ///   - pixelBuffer: 像素缓冲区
    ///   - mergeInfos: 融合信息数组
    ///   - metalLayer: Metal 层
    func renderPixelBuffer(_ pixelBuffer: CVPixelBuffer, mergeInfos: [VAPMergedInfo]?, metalLayer: CAMetalLayer) {
        guard let device = kPCHWDMetalRendererDevice else { return }
        
        if metalLayer.superlayer == nil || metalLayer.bounds.size.width <= 0 || metalLayer.bounds.size.height <= 0 {
            PCVAPError(kPCVAPModuleCommon, "quit rendering cuz layer.superlayer or size error is nil! superlayer:\(String(describing: metalLayer.superlayer)) height:\(metalLayer.bounds.size.height) width:\(metalLayer.bounds.size.width)")
            return
        }
        
        reconstructIfNeed(metalLayer: metalLayer)
        
        guard pixelBuffer != nil, commandQueue != nil else {
            PCVAPError(kPCVAPModuleCommon, "quit rendering cuz pixelbuffer is nil!")
            return
        }
        
        updateMetalPropertiesIfNeed(pixelBuffer)
        
        if let cache = videoTextureCache {
            CVMetalTextureCacheFlush(cache, 0)
        }
        
        let yWidth = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let yHeight = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        let uvWidth = CVPixelBufferGetWidthOfPlane(pixelBuffer, 1)
        let uvHeight = CVPixelBufferGetHeightOfPlane(pixelBuffer, 1)
        
        var yTextureRef: CVMetalTexture?
        var uvTextureRef: CVMetalTexture?
        
        let yStatus = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            videoTextureCache!,
            pixelBuffer,
            nil,
            .r8Unorm,
            yWidth,
            yHeight,
            0,
            &yTextureRef
        )
        
        let uvStatus = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            videoTextureCache!,
            pixelBuffer,
            nil,
            .rg8Unorm,
            uvWidth,
            uvHeight,
            1,
            &uvTextureRef
        )
        
        guard yStatus == kCVReturnSuccess, uvStatus == kCVReturnSuccess,
              let yTextureRef = yTextureRef,
              let uvTextureRef = uvTextureRef else {
            PCVAPError(kPCVAPModuleCommon, "quit rendering cuz failing getting yuv texture-yStatus:\(yStatus):uvStatus:\(uvStatus)")
            return
        }
        
        guard let yTexture = CVMetalTextureGetTexture(yTextureRef),
              let uvTexture = CVMetalTextureGetTexture(uvTextureRef) else {
            PCVAPError(kPCVAPModuleCommon, "quit rendering cuz content is nil!")
            return
        }
        
        if metalLayer.drawableSize.width <= 0 || metalLayer.drawableSize.height <= 0 {
            PCVAPError(kPCVAPModuleCommon, "quit rendering cuz drawableSize is 0")
            return
        }
        
        guard let drawable = metalLayer.nextDrawable() else {
            PCVAPError(kPCVAPModuleCommon, "quit rendering cuz nextDrawable is nil!")
            return
        }
        
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = drawable.texture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.0)
        
        guard let commandBuffer = commandQueue?.makeCommandBuffer(),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            PCVAPError(kPCVAPModuleCommon, "quit rendering cuz renderEncoder is nil!")
            return
        }
        
        guard vertexBuffer != nil, yuvMatrixBuffer != nil else {
            PCVAPError(kPCVAPModuleCommon, "quit rendering cuz vertexBuffer or yuvMatrixBuffer is nil!")
            renderEncoder.endEncoding()
            return
        }
        
        drawBackground(yTexture: yTexture, uvTexture: uvTexture, encoder: renderEncoder)
        drawMergedAttachments(mergeInfos, yTexture: yTexture, uvTexture: uvTexture, renderEncoder: renderEncoder, metalLayer: metalLayer)
        
        renderEncoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
    
    // MARK: - Drawing Methods
    
    private func drawBackground(yTexture: MTLTexture, uvTexture: MTLTexture, encoder: MTLRenderCommandEncoder) {
        if let maskInfo = maskInfo {
            guard let maskTexture = maskInfo.texture else {
                PCVAPError(kPCVAPModuleCommon, "maskTexture error! maskTexture is nil")
                return
            }
            
            guard let maskPipelineState = mainPipelineStateForMask else {
                PCVAPError(kPCVAPModuleCommon, "maskPipelineState error! maskTexture is nil")
                return
            }
            
            if maskInfo.blurLength > 0 {
                guard let blurPipelineState = mainPipelineStateForMaskBlur else {
                    PCVAPError(kPCVAPModuleCommon, "maskBlurPipelineState error!")
                    return
                }
                
                encoder.setRenderPipelineState(blurPipelineState)
                encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
                encoder.setFragmentBuffer(yuvMatrixBuffer, offset: 0, index: 0)
                encoder.setFragmentBuffer(maskBlurBuffer, offset: 0, index: 1)
                encoder.setFragmentTexture(yTexture, index: PCYUVFragmentTextureIndex.luma.rawValue)
                encoder.setFragmentTexture(uvTexture, index: PCYUVFragmentTextureIndex.chroma.rawValue)
                encoder.setFragmentTexture(maskTexture, index: PCYUVFragmentTextureIndex.attachmentStart.rawValue)
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: 1)
            } else {
                encoder.setRenderPipelineState(maskPipelineState)
                encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
                encoder.setFragmentBuffer(yuvMatrixBuffer, offset: 0, index: 0)
                encoder.setFragmentTexture(yTexture, index: PCYUVFragmentTextureIndex.luma.rawValue)
                encoder.setFragmentTexture(uvTexture, index: PCYUVFragmentTextureIndex.chroma.rawValue)
                encoder.setFragmentTexture(maskTexture, index: PCYUVFragmentTextureIndex.attachmentStart.rawValue)
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: 1)
            }
        } else {
            guard let defaultPipelineState = defaultMainPipelineState else {
                PCVAPError(kPCVAPModuleCommon, "yuvPipelineState error! maskTexture is nil")
                return
            }
            
            encoder.setRenderPipelineState(defaultPipelineState)
            encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            encoder.setFragmentBuffer(yuvMatrixBuffer, offset: 0, index: 0)
            encoder.setFragmentTexture(yTexture, index: PCYUVFragmentTextureIndex.luma.rawValue)
            encoder.setFragmentTexture(uvTexture, index: PCYUVFragmentTextureIndex.chroma.rawValue)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: 1)
        }
    }
    
    private func drawMergedAttachments(_ infos: [VAPMergedInfo]?, yTexture: MTLTexture, uvTexture: MTLTexture, renderEncoder: MTLRenderCommandEncoder, metalLayer: CAMetalLayer) {
        guard let infos = infos, !infos.isEmpty else { return }
        
        guard let commonInfo = commonInfo, let attachmentPipelineState = attachmentPipelineState else {
            PCVAPError(kPCVAPModuleCommon, "renderMergedAttachments error! infos:\(infos.count) encoder:\(renderEncoder) commonInfo:\(String(describing: commonInfo)) attachmentPipelineState:\(String(describing: attachmentPipelineState))")
            return
        }
        
        guard yTexture != nil, uvTexture != nil else {
            PCVAPError(kPCVAPModuleCommon, "renderMergedAttachments error! cuz yTexture:\(String(describing: yTexture)) or uvTexture:\(String(describing: uvTexture)) is nil!")
            return
        }
        
        guard let device = kPCHWDMetalRendererDevice else { return }
        
        for mergeInfo in infos {
            renderEncoder.setRenderPipelineState(attachmentPipelineState)
            
            guard let sourceTexture = mergeInfo.source?.texture else {
                continue
            }
            
            guard let vertexBuffer = mergeInfo.vertexBuffer(containerSize: commonInfo.size, maskContainerSize: commonInfo.videoSize, device: device) else {
                continue
            }
            
            guard let colorParamsBuffer = mergeInfo.source?.colorParamsBuffer,
                  let yuvMatrixBuffer = yuvMatrixBuffer else {
                continue
            }
            
            renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            renderEncoder.setFragmentBuffer(yuvMatrixBuffer, offset: 0, index: 0)
            renderEncoder.setFragmentBuffer(colorParamsBuffer, offset: 0, index: 1)
            
            // 遮罩信息在视频流中
            renderEncoder.setFragmentTexture(yTexture, index: PCYUVFragmentTextureIndex.luma.rawValue)
            renderEncoder.setFragmentTexture(uvTexture, index: PCYUVFragmentTextureIndex.chroma.rawValue)
            renderEncoder.setFragmentTexture(sourceTexture, index: PCYUVFragmentTextureIndex.attachmentStart.rawValue)
            renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: 1)
        }
    }
    
    // MARK: - Pipeline State Creation
    
    private func createPipelineState(vertexFunction: String, fragmentFunction: String) -> MTLRenderPipelineState? {
        guard let device = kPCHWDMetalRendererDevice,
              let shaderFuncLoader = shaderFuncLoader,
              let metalLayer = metalLayer else {
            return nil
        }
        
        guard let vertexProgram = shaderFuncLoader.loadFunction(withName: vertexFunction),
              let fragmentProgram = shaderFuncLoader.loadFunction(withName: fragmentFunction) else {
            PCVAPError(kPCVAPModuleCommon, "setupPipelineStatesWithMetalLayer fail! cuz: shader load fail!")
            assertionFailure("check if .metal files been compiled to correct target!")
            return nil
        }
        
        // 融混方程
        // https://objccn.io/issue-3-1/
        // https://www.andersriggelsen.dk/glblendfunc.php
        let pipelineStateDescriptor = MTLRenderPipelineDescriptor()
        pipelineStateDescriptor.vertexFunction = vertexProgram
        pipelineStateDescriptor.fragmentFunction = fragmentProgram
        pipelineStateDescriptor.colorAttachments[0].pixelFormat = metalLayer.pixelFormat
        pipelineStateDescriptor.colorAttachments[0].isBlendingEnabled = true
        pipelineStateDescriptor.colorAttachments[0].rgbBlendOperation = .add
        pipelineStateDescriptor.colorAttachments[0].alphaBlendOperation = .add
        pipelineStateDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        pipelineStateDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        pipelineStateDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        pipelineStateDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        
        do {
            let pipelineState = try device.makeRenderPipelineState(descriptor: pipelineStateDescriptor)
            return pipelineState
        } catch {
            PCVAPError(kPCVAPModuleCommon, "newRenderPipelineStateWithDescriptor error!:\(error)")
            return nil
        }
    }
    
    // MARK: - Pipeline State Properties
    
    private var defaultMainPipelineState: MTLRenderPipelineState? {
        if _defaultMainPipelineState == nil {
            _defaultMainPipelineState = createPipelineState(vertexFunction: kVAPVertexFunctionName, fragmentFunction: kVAPYUVFragmentFunctionName)
        }
        return _defaultMainPipelineState
    }
    
    private var mainPipelineStateForMask: MTLRenderPipelineState? {
        if _mainPipelineStateForMask == nil {
            _mainPipelineStateForMask = createPipelineState(vertexFunction: kVAPVertexFunctionName, fragmentFunction: kVAPMaskFragmentFunctionName)
        }
        return _mainPipelineStateForMask
    }
    
    private var mainPipelineStateForMaskBlur: MTLRenderPipelineState? {
        if _mainPipelineStateForMaskBlur == nil {
            _mainPipelineStateForMaskBlur = createPipelineState(vertexFunction: kVAPVertexFunctionName, fragmentFunction: kVAPMaskBlurFragmentFunctionName)
        }
        return _mainPipelineStateForMaskBlur
    }
    
    private var _attachmentPipelineState: MTLRenderPipelineState?
    private var attachmentPipelineState: MTLRenderPipelineState? {
        if _attachmentPipelineState == nil {
            _attachmentPipelineState = createPipelineState(vertexFunction: kVAPAttachmentVertexFunctionName, fragmentFunction: kVAPAttachmentFragmentFunctionName)
        }
        return _attachmentPipelineState
    }
    
    // MARK: - Mask Blur Buffer
    
    private var _maskBlurBuffer: MTLBuffer?
    private var maskBlurBuffer: MTLBuffer? {
        if _maskBlurBuffer == nil {
            guard let device = kPCHWDMetalRendererDevice else { return nil }
            let parameters = [PCMaskParameters(weightMatrix: kQGBlurWeightMatrixDefault, coreSize: 3, texelOffset: 0.01)]
            let parametersSize = MemoryLayout<PCMaskParameters>.size
            _maskBlurBuffer = device.makeBuffer(bytes: parameters, length: parametersSize, options: kDefaultMTLResourceOption)
        }
        return _maskBlurBuffer
    }
    
    // MARK: - Private Methods
    
    private func updateMetalPropertiesIfNeed(_ pixelBuffer: CVPixelBuffer) {
        guard let device = kPCHWDMetalRendererDevice else { return }
        
        // 修复：CVBufferGetAttachment 在 Swift 中返回 Unmanaged<CFTypeRef>?，需要解包
        // 而且 CFTypeRef 可能不是 CFString，不能使用强制转换 as!
        let yCbCrMatrixTypeUnmanaged = CVBufferGetAttachment(pixelBuffer, kCVImageBufferYCbCrMatrixKey, nil)
        var matrix = kQGColorConversionMatrix601FullRangeDefault
        
        if let yCbCrMatrixTypeUnmanaged = yCbCrMatrixTypeUnmanaged {
            // 解包 Unmanaged，获取 CFTypeRef
            let yCbCrMatrixType = yCbCrMatrixTypeUnmanaged.takeUnretainedValue()
            // 检查类型是否为 CFString，然后安全转换
            if CFGetTypeID(yCbCrMatrixType) == CFStringGetTypeID() {
                // 使用 unsafeBitCast 进行类型转换（因为我们已经确认了类型）
                let matrixTypeCFString = unsafeBitCast(yCbCrMatrixType, to: CFString.self)
                if CFStringCompare(matrixTypeCFString, kCVImageBufferYCbCrMatrix_ITU_R_709_2, []) == .compareEqualTo {
                    matrix = kQGColorConversionMatrix709FullRangeDefault
                }
            } else {
                // 如果不是 CFString 类型，记录警告但继续使用默认矩阵
                PCVAPEvent(kPCVAPModuleCommon, "updateMetalPropertiesIfNeed: yCbCrMatrixType is not CFString, typeID=\(CFGetTypeID(yCbCrMatrixType))")
            }
        }
        
        // 检查矩阵是否相等（使用近似比较）
        var isEqual = true
        for i in 0..<3 {
            for j in 0..<3 {
                if abs(currentColorConversionMatrix[i][j] - matrix[i][j]) > 0.0001 {
                    isEqual = false
                    break
                }
            }
            if !isEqual { break }
        }
        if isEqual {
            return
        }
        
        currentColorConversionMatrix = matrix
        let yuvMatrixs = [PCColorParameters(matrix: currentColorConversionMatrix, offset: simd_float2(0.5, 0.5))]
        // 修复：使用 stride 而不是 size，因为 Metal 着色器需要对齐到 16 字节边界
        // size=56, stride=64，Metal 着色器期望 64 字节
        let yuvMatrixsDataSize = MemoryLayout<PCColorParameters>.stride
        yuvMatrixBuffer = device.makeBuffer(bytes: yuvMatrixs, length: yuvMatrixsDataSize, options: kDefaultMTLResourceOption)
    }
    
    private func reconstructIfNeed(metalLayer: CAMetalLayer) {
        if renderingResourcesDisposed {
            setupRenderContext()
            renderingResourcesDisposed = false
        }
    }
    
    private func updateMainVertexBuffer() {
        guard let commonInfo = commonInfo,
              let device = kPCHWDMetalRendererDevice else {
            return
        }
        
        let columnCountForVertices = 4
        let columnCountForCoordinate = 2
        let vertexDataLength = 40  // 顶点(x,y,z,w),纹理坐标(x,x),数组长度
        
        var vertexData = [Float](repeating: 0, count: vertexDataLength)
        var rgbCoordinates = [Float](repeating: 0, count: 8)
        var alphaCoordinates = [Float](repeating: 0, count: 8)
        var maskCoordinates = [Float](repeating: 0, count: 8)
        
        let vertices = kVAPMTLVerticesIdentity
        
        genMTLTextureCoordinates(commonInfo.rgbAreaRect, containerSize: commonInfo.videoSize, coordinates: &rgbCoordinates, reverse: false, degree: 0)
        genMTLTextureCoordinates(commonInfo.alphaAreaRect, containerSize: commonInfo.videoSize, coordinates: &alphaCoordinates, reverse: false, degree: 0)
        
        if let maskInfo = maskInfo {
            genMTLTextureCoordinates(maskInfo.sampleRect, containerSize: maskInfo.dataSize, coordinates: &maskCoordinates, reverse: false, degree: 0)
        }
        
        var indexForVertexData = 0
        // 顶点数据+坐标
        for i in 0..<(4 * columnCountForVertices) {
            // 顶点数据
            vertexData[indexForVertexData] = vertices[i]
            indexForVertexData += 1
            
            // 逐行处理
            if i % columnCountForVertices == columnCountForVertices - 1 {
                let row = i / columnCountForVertices
                // rgb纹理坐标
                vertexData[indexForVertexData] = rgbCoordinates[row * columnCountForCoordinate]
                indexForVertexData += 1
                vertexData[indexForVertexData] = rgbCoordinates[row * columnCountForCoordinate + 1]
                indexForVertexData += 1
                // alpha纹理坐标
                vertexData[indexForVertexData] = alphaCoordinates[row * columnCountForCoordinate]
                indexForVertexData += 1
                vertexData[indexForVertexData] = alphaCoordinates[row * columnCountForCoordinate + 1]
                indexForVertexData += 1
                // mask纹理坐标
                vertexData[indexForVertexData] = maskCoordinates[row * columnCountForCoordinate]
                indexForVertexData += 1
                vertexData[indexForVertexData] = maskCoordinates[row * columnCountForCoordinate + 1]
                indexForVertexData += 1
            }
        }
        
        let allocationSize = vertexDataLength * MemoryLayout<Float>.size
        vertexBuffer = device.makeBuffer(bytes: vertexData, length: allocationSize, options: kDefaultMTLResourceOption)
    }
}

#endif
