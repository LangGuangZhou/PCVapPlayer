//
//  PCHWDMetalView.swift
//  PCVapPlayer
//
//  Created by converting from Objective-C
//  Copyright © 2024. All rights reserved.
//

import UIKit
import Metal
import MetalKit
import CoreVideo

/// HWD Metal 视图委托协议
protocol PCHWDMetelViewDelegate: AnyObject {
    func onMetalViewUnavailable()
}

#if targetEnvironment(simulator)
// 模拟器不支持 Metal
class PCHWDMetalView: UIView {
    weak var delegate: PCHWDMetelViewDelegate?
    var blendMode: PCTextureBlendMode = .alphaLeft
    
    init(frame: CGRect, blendMode: PCTextureBlendMode) {
        self.blendMode = blendMode
        super.init(frame: frame)
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    func display(_ pixelBuffer: CVPixelBuffer) {
        // 模拟器不支持
    }
    
    func dispose() {
        // 模拟器不支持
    }
}
#else

/// HWD Metal 视图
class PCHWDMetalView: UIView {
    weak var delegate: PCHWDMetelViewDelegate?
    var blendMode: PCTextureBlendMode = .alphaLeft
    
    private var metalLayer: CAMetalLayer {
        return layer as! CAMetalLayer
    }
    
    private var renderer: PCHWDMetalRenderer?
    private var drawableSizeShouldUpdate = true
    
    override class var layerClass: AnyClass {
        return CAMetalLayer.self
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        drawableSizeShouldUpdate = true
        blendMode = .alphaLeft
    }
    
    required init?(coder: NSCoder) {
        assertionFailure("initWithCoder: has not been implemented")
        return nil
    }
    
    init(frame: CGRect, blendMode: PCTextureBlendMode) {
        super.init(frame: frame)
        drawableSizeShouldUpdate = true
        self.blendMode = .alphaLeft
        
        metalLayer.frame = self.frame
        metalLayer.isOpaque = false
        self.blendMode = blendMode
        renderer = PCHWDMetalRenderer(metalLayer: metalLayer, blendMode: blendMode)
        metalLayer.contentsScale = UIScreen.main.scale
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = true
    }
    
    override func didMoveToWindow() {
        super.didMoveToWindow()
        drawableSizeShouldUpdate = true
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        drawableSizeShouldUpdate = true
    }
    
    deinit {
        notifyMetalViewUnavailable()
    }
    
    /// 显示像素缓冲区
    /// - Parameter pixelBuffer: 像素缓冲区
    func display(_ pixelBuffer: CVPixelBuffer) {
        guard window != nil else {
            PCVAPEvent(kPCVAPModuleCommon, "quit display pixelbuffer, cuz window is nil!")
            notifyMetalViewUnavailable()
            return
        }
        
        if drawableSizeShouldUpdate {
            let nativeScale = UIScreen.main.nativeScale
            let drawableSize = CGSize(
                width: bounds.width * nativeScale,
                height: bounds.height * nativeScale
            )
            metalLayer.drawableSize = drawableSize
            PCVAPEvent(kPCVAPModuleCommon, "update drawablesize :\(drawableSize)")
            drawableSizeShouldUpdate = false
        }
        
        renderer?.blendMode = blendMode
        renderer?.renderPixelBuffer(pixelBuffer, metalLayer: metalLayer)
    }
    
    /// 资源回收
    func dispose() {
        renderer?.dispose()
    }
    
    /// 通知 Metal 视图不可用
    private func notifyMetalViewUnavailable() {
        delegate?.onMetalViewUnavailable()
    }
}

#endif

