//
//  PCHWDMetalRenderer.swift
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

// MARK: - Constants

let kPCHWDVertexFunctionName = "hwd_vertexShader"
let kPCHWDYUVFragmentFunctionName = "hwd_yuvFragmentShader"

let kQGQuadVerticesConstantsRow = 4
let kQGQuadVerticesConstantsColumn = 32
let kPCHWDVertexCount = 4

// 注意：kPCHWDMetalRendererDevice 已在 PCMacros.swift 中定义

// BT.601, which is the standard for SDTV.
let kQGColorConversionMatrix601Default = matrix_float3x3(
    simd_float3(1.164, 1.164, 1.164),
    simd_float3(0.0, -0.392, 2.017),
    simd_float3(1.596, -0.813, 0.0)
)

// ITU BT.601 Full Range
let kQGColorConversionMatrix601FullRangeDefault = matrix_float3x3(
    simd_float3(1.0, 1.0, 1.0),
    simd_float3(0.0, -0.34413, 1.772),
    simd_float3(1.402, -0.71414, 0.0)
)

// BT.709, which is the standard for HDTV.
let kQGColorConversionMatrix709Default = matrix_float3x3(
    simd_float3(1.164, 1.164, 1.164),
    simd_float3(0.0, -0.213, 2.112),
    simd_float3(1.793, -0.533, 0.0)
)

// BT.709 Full Range.
let kQGColorConversionMatrix709FullRangeDefault = matrix_float3x3(
    simd_float3(1.0, 1.0, 1.0),
    simd_float3(0.0, -0.18732, 1.8556),
    simd_float3(1.57481, -0.46813, 0.0)
)

// Blur weight matrix.
let kQGBlurWeightMatrixDefault = matrix_float3x3(
    simd_float3(0.0625, 0.125, 0.0625),
    simd_float3(0.125, 0.25, 0.125),
    simd_float3(0.0625, 0.125, 0.0625)
)

// PCHWDVertex 顶点坐标+纹理坐标（rgb+alpha）
let kQGQuadVerticesConstants: [[Float]] = [
    // 左侧alpha
    [-1.0, -1.0, 0.0, 1.0, 0.5, 1.0, 0.0, 1.0,
     -1.0, 1.0, 0.0, 1.0, 0.5, 0.0, 0.0, 0.0,
     1.0, -1.0, 0.0, 1.0, 1.0, 1.0, 0.5, 1.0,
     1.0, 1.0, 0.0, 1.0, 1.0, 0.0, 0.5, 0.0],
    // 右侧alpha
    [-1.0, -1.0, 0.0, 1.0, 0.0, 1.0, 0.5, 1.0,
     -1.0, 1.0, 0.0, 1.0, 0.0, 0.0, 0.5, 0.0,
     1.0, -1.0, 0.0, 1.0, 0.5, 1.0, 1.0, 1.0,
     1.0, 1.0, 0.0, 1.0, 0.5, 0.0, 1.0, 0.0],
    // 顶部alpha
    [-1.0, -1.0, 0.0, 1.0, 0.0, 1.0, 0.0, 0.5,
     -1.0, 1.0, 0.0, 1.0, 0.0, 0.5, 0.0, 0.0,
     1.0, -1.0, 0.0, 1.0, 1.0, 1.0, 1.0, 0.5,
     1.0, 1.0, 0.0, 1.0, 1.0, 0.5, 1.0, 0.0],
    // 底部alpha
    [-1.0, -1.0, 0.0, 1.0, 0.0, 0.5, 0.0, 1.0,
     -1.0, 1.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.5,
     1.0, -1.0, 0.0, 1.0, 1.0, 0.5, 1.0, 1.0,
     1.0, 1.0, 0.0, 1.0, 1.0, 0.0, 1.0, 0.5]
]

#if targetEnvironment(simulator)
// 模拟器不支持 Metal
class PCHWDMetalRenderer {
    var blendMode: PCTextureBlendMode = .alphaLeft
    
    init(metalLayer: Any, blendMode: PCTextureBlendMode) {
        self.blendMode = blendMode
    }
    
    func renderPixelBuffer(_ pixelBuffer: CVPixelBuffer, metalLayer: Any) {
        // 模拟器不支持
    }
    
    func dispose() {
        // 模拟器不支持
    }
}
#else

/// HWD Metal 渲染器
class PCHWDMetalRenderer {
    var blendMode: PCTextureBlendMode = .alphaLeft
    
    private var renderingResourcesDisposed = false
    private var currentColorConversionMatrix: matrix_float3x3 = kQGColorConversionMatrix601FullRangeDefault
    
    private var vertexBuffer: MTLBuffer?
    private var yuvMatrixBuffer: MTLBuffer?
    private var pipelineState: MTLRenderPipelineState?
    private var commandQueue: MTLCommandQueue?
    private var vertexCount: Int = 0
    private var videoTextureCache: CVMetalTextureCache?
    private var shaderFuncLoader: PCMetalShaderFunctionLoader?
    
    init(metalLayer: CAMetalLayer, blendMode: PCTextureBlendMode) {
        self.blendMode = blendMode
        
        if kPCHWDMetalRendererDevice == nil {
            kPCHWDMetalRendererDevice = MTLCreateSystemDefaultDevice()
        }
        
        metalLayer.device = kPCHWDMetalRendererDevice
        setupConstants()
        setupPipelineStates(metalLayer: metalLayer)
    }
    
    /// 回收渲染数据，减少内存占用
    func dispose() {
        commandQueue = nil
        pipelineState = nil
        vertexBuffer = nil
        yuvMatrixBuffer = nil
        shaderFuncLoader = nil
        
        if let cache = videoTextureCache {
            CVMetalTextureCacheFlush(cache, 0)
            videoTextureCache = nil
        }
        
        renderingResourcesDisposed = true
    }
    
    deinit {
        dispose()
    }
    
    private func setupConstants() {
        guard let device = kPCHWDMetalRendererDevice else { return }
        
        let vertices = suitableQuadVertices()
        let allocationSize = kQGQuadVerticesConstantsColumn * MemoryLayout<Float>.size
        vertexBuffer = device.makeBuffer(bytes: vertices, length: allocationSize, options: kDefaultMTLResourceOption)
        vertexCount = kPCHWDVertexCount
        currentColorConversionMatrix = kQGColorConversionMatrix601FullRangeDefault
        
        let yuvMatrixs = [PCColorParameters(matrix: currentColorConversionMatrix, offset: simd_float2(0.5, 0.5))]
        // 修复：使用 stride 而不是 size，因为 Metal 着色器需要对齐到 16 字节边界
        // size=56, stride=64，Metal 着色器期望 64 字节
        let yuvMatrixsDataSize = MemoryLayout<PCColorParameters>.stride
        yuvMatrixBuffer = device.makeBuffer(bytes: yuvMatrixs, length: yuvMatrixsDataSize, options: kDefaultMTLResourceOption)
    }
    
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
    
    private func setupPipelineStates(metalLayer: CAMetalLayer) {
        guard let device = kPCHWDMetalRendererDevice else { return }
        
        shaderFuncLoader = PCMetalShaderFunctionLoader(device: device)
        
        guard let vertexProgram = shaderFuncLoader?.loadFunction(withName: kPCHWDVertexFunctionName),
              let fragmentProgram = shaderFuncLoader?.loadFunction(withName: kPCHWDYUVFragmentFunctionName) else {
            PCVAPError(kPCVAPModuleCommon, "setupPipelineStatesWithMetalLayer fail! cuz: shader load fail")
            assertionFailure("check if .metal files been compiled to correct target!")
            return
        }
        
        let pipelineStateDescriptor = MTLRenderPipelineDescriptor()
        pipelineStateDescriptor.vertexFunction = vertexProgram
        pipelineStateDescriptor.fragmentFunction = fragmentProgram
        pipelineStateDescriptor.colorAttachments[0].pixelFormat = metalLayer.pixelFormat
        
        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineStateDescriptor)
        } catch {
            PCVAPError(kPCVAPModuleCommon, "newRenderPipelineStateWithDescriptor error!:\(error)")
            return
        }
        
        commandQueue = device.makeCommandQueue()
        
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
            return
        }
        
        videoTextureCache = textureCache
    }
    
    /// 使用 metal 渲染管线渲染 CVPixelBufferRef
    /// - Parameters:
    ///   - pixelBuffer: 图像数据
    ///   - metalLayer: metalLayer
    func renderPixelBuffer(_ pixelBuffer: CVPixelBuffer, metalLayer: CAMetalLayer) {
        guard let device = kPCHWDMetalRendererDevice else { return }
        
        if metalLayer.superlayer == nil || metalLayer.bounds.size.width <= 0 || metalLayer.bounds.size.height <= 0 {
            PCVAPError(kPCVAPModuleCommon, "quit rendering cuz layer.superlayer or size error is nil! superlayer:\(String(describing: metalLayer.superlayer)) height:\(metalLayer.bounds.size.height) width:\(metalLayer.bounds.size.width)")
            return
        }
        
        reconstructIfNeed(metalLayer: metalLayer)
        
        guard pixelBuffer != nil, commandQueue != nil, pipelineState != nil else {
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
        
        // 注意格式！r8Unorm
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
        
        // 注意格式！rg8Unorm
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
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
        
        guard let commandBuffer = commandQueue?.makeCommandBuffer(),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }
        
        renderEncoder.setRenderPipelineState(pipelineState!)
        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        renderEncoder.setFragmentBuffer(yuvMatrixBuffer, offset: 0, index: 0)
        renderEncoder.setFragmentTexture(yTexture, index: PCYUVFragmentTextureIndex.luma.rawValue)
        renderEncoder.setFragmentTexture(uvTexture, index: PCYUVFragmentTextureIndex.chroma.rawValue)
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: vertexCount, instanceCount: 1)
        renderEncoder.endEncoding()
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
    
    /// 在必要的时候重建渲染数据，以便渲染
    private func reconstructIfNeed(metalLayer: CAMetalLayer) {
        if renderingResourcesDisposed {
            setupConstants()
            setupPipelineStates(metalLayer: metalLayer)
            renderingResourcesDisposed = false
        }
    }
    
    /// 获取合适的四边形顶点
    private func suitableQuadVertices() -> [Float] {
        switch blendMode {
        case .alphaLeft:
            return kQGQuadVerticesConstants[0]
        case .alphaRight:
            return kQGQuadVerticesConstants[1]
        case .alphaTop:
            return kQGQuadVerticesConstants[2]
        case .alphaBottom:
            return kQGQuadVerticesConstants[3]
        }
    }
}

#endif

