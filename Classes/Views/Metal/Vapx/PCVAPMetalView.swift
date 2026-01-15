//
//  PCVAPMetalView.swift
//  PCVapPlayer
//
//  Created by converting from Objective-C
//  Copyright © 2024. All rights reserved.
//

import UIKit
import Metal
import MetalKit
import CoreVideo

/// VAP Metal 视图委托协议
protocol PCVAPMetalViewDelegate: AnyObject {
    func onMetalViewUnavailable()
}

#if targetEnvironment(simulator)
// 模拟器不支持 Metal
class PCVAPMetalView: UIView {
    weak var delegate: PCVAPMetalViewDelegate?
    var commonInfo: VAPCommonInfo?
    var maskInfo: PCVAPMaskInfo?
    
    func display(_ pixelBuffer: CVPixelBuffer, mergeInfos: [VAPMergedInfo]?) {
        // 模拟器不支持
    }
    
    func dispose() {
        // 模拟器不支持
    }
}
#else

/// VAP Metal 视图
class PCVAPMetalView: UIView {
    weak var delegate: PCVAPMetalViewDelegate?
    
    private var metalLayer: CAMetalLayer {
        return layer as! CAMetalLayer
    }
    
    private var renderer: PCVAPMetalRenderer?
    private var drawableSizeShouldUpdate = true
    
    var commonInfo: VAPCommonInfo? {
        get {
            return renderer?.commonInfo
        }
        set {
            renderer?.commonInfo = newValue
        }
    }
    
    var maskInfo: PCVAPMaskInfo? {
        didSet {
            renderer?.maskInfo = maskInfo
        }
    }
    
    override class var layerClass: AnyClass {
        return CAMetalLayer.self
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        drawableSizeShouldUpdate = true
        
        metalLayer.frame = self.frame
        metalLayer.isOpaque = false
        renderer = PCVAPMetalRenderer(metalLayer: metalLayer)
        metalLayer.contentsScale = UIScreen.main.scale
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = true
    }
    
    required init?(coder: NSCoder) {
        assertionFailure("initWithCoder: has not been implemented")
        return nil
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
    
    /// 显示像素缓冲区和融合信息
    /// - Parameters:
    ///   - pixelBuffer: 像素缓冲区
    ///   - mergeInfos: 融合信息数组
    func display(_ pixelBuffer: CVPixelBuffer, mergeInfos: [VAPMergedInfo]?) {
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
        
        renderer?.renderPixelBuffer(pixelBuffer, mergeInfos: mergeInfos, metalLayer: metalLayer)
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
