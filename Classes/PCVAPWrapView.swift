//
//  PCVAPWrapView.swift
//  PCVapPlayer
//
//  Created by converting from Objective-C
//  Copyright © 2024. All rights reserved.
//

import UIKit

// MARK: - Enums

/// VAP 包装视图内容模式
public enum PCVAPWrapViewContentMode: UInt {
    case scaleToFill = 0
    case aspectFit = 1
    case aspectFill = 2
}

// MARK: - Protocols

/// VAP 包装视图委托协议
public protocol PCVAPWrapViewDelegate: AnyObject {
    /// 即将开始播放时询问，true 马上开始播放，false 放弃播放
    func vapWrap_viewshouldStartPlayMP4(_ container: PCVAPView, config: PCVAPConfigModel) -> Bool
    
    /// 开始播放
    func vapWrap_viewDidStartPlayMP4(_ container: PCVAPView)
    
    /// 播放到指定帧
    func vapWrap_viewDidPlayMP4AtFrame(_ frame: PCMP4AnimatedImageFrame, view: PCVAPView)
    
    /// 停止播放
    func vapWrap_viewDidStopPlayMP4(_ lastFrameIndex: Int, view: PCVAPView)
    
    /// 播放完成
    func vapWrap_viewDidFinishPlayMP4(_ totalFrameCount: Int, view: PCVAPView)
    
    /// 播放失败
    func vapWrap_viewDidFailPlayMP4(_ error: Error)
    
    /// 替换配置中的资源占位符（不处理直接返回 tag）
    func vapWrapview_contentForVapTag(_ tag: String, resource: VAPSourceInfo) -> String?
    
    /// 加载 VAP 图片
    func vapWrapView_loadVapImage(with urlStr: String, context: [String: Any], completion: @escaping PCVAPImageCompletionBlock)
}

// 提供默认实现（可选方法）
extension PCVAPWrapViewDelegate {
    func vapWrap_viewshouldStartPlayMP4(_ container: PCVAPView, config: PCVAPConfigModel) -> Bool { return true }
    func vapWrap_viewDidStartPlayMP4(_ container: PCVAPView) {}
    func vapWrap_viewDidPlayMP4AtFrame(_ frame: PCMP4AnimatedImageFrame, view: PCVAPView) {}
    func vapWrap_viewDidStopPlayMP4(_ lastFrameIndex: Int, view: PCVAPView) {}
    func vapWrap_viewDidFinishPlayMP4(_ totalFrameCount: Int, view: PCVAPView) {}
    func vapWrap_viewDidFailPlayMP4(_ error: Error) {}
    func vapWrapview_contentForVapTag(_ tag: String, resource: VAPSourceInfo) -> String? { return tag }
    func vapWrapView_loadVapImage(with urlStr: String, context: [String: Any], completion: @escaping PCVAPImageCompletionBlock) {
        completion(nil, NSError(domain: "PCVAPWrapView", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not implemented"]), urlStr)
    }
}

// 注意：PCHWDMP4PlayDelegate 协议已在 UIView+PCVAP.swift 中声明

// MARK: - PCVAPWrapView

/// 封装 PCVAPView，本身不响应手势
/// 提供 ContentMode 功能
/// 播放完成后会自动移除内部的 PCVAPView（可选）
public class PCVAPWrapView: UIView {
    /// VAP 内容模式，默认为 scaleToFill
    public var vapContentMode: PCVAPWrapViewContentMode = .scaleToFill
    
    /// 是否在播放完成后自动移除内部 PCVAPView
    /// 如果外部用法会复用当前 View，可以不移除
    public var autoDestoryAfterFinish: Bool = true
    
    private weak var delegate: PCVAPWrapViewDelegate?
    internal var vapView: PCVAPView?
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }
    
    required public init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }
    
    private func commonInit() {
        autoDestoryAfterFinish = true
    }
    
    /// 因为播放停止后可能移除 PCVAPView，这里需要加回来
    internal func initPCVAPViewIfNeed() {
        if vapView == nil {
            vapView = PCVAPView(frame: bounds)
            addSubview(vapView!)
        }
    }
    
    /// 播放 MP4
    /// - Parameters:
    ///   - filePath: 文件路径
    ///   - repeatCount: 重复次数（-1 表示无限循环）
    ///   - delegate: 委托
    public func playHWDMP4(_ filePath: String, repeatCount: Int, delegate: PCVAPWrapViewDelegate?) {
        self.delegate = delegate
        initPCVAPViewIfNeed()
        vapView?.playHWDMP4(filePath, repeatCount: repeatCount, delegate: self)
    }
    
    /// 停止播放
    public override func stopHWDMP4() {
        vapView?.stopHWDMP4()
    }
    
    /// 暂停播放
    public override func pauseHWDMP4() {
        vapView?.pauseHWDMP4()
    }
    
    /// 恢复播放
    public override func resumeHWDMP4() {
        vapView?.resumeHWDMP4()
    }
    
    /// 设置是否静音播放素材
    /// 注：在播放开始时进行设置，播放过程中设置无效
    /// - Parameter isMute: 是否静音
    public override func setMute(_ isMute: Bool) {
        initPCVAPViewIfNeed()
        vapView?.setMute(isMute)
    }
    
    
    // MARK: - UIView Override
    
    /// 自身不响应，仅子视图响应
    public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if !isUserInteractionEnabled || isHidden || alpha < 0.01 {
            return nil
        }
        
        if bounds.contains(point) {
            for subview in subviews.reversed() {
                let convertedPoint = convert(point, to: subview)
                if let hitView = subview.hitTest(convertedPoint, with: event) {
                    return hitView
                }
            }
            return nil
        }
        return nil
    }
    
    // MARK: - Private Methods
    
    /// 设置内容模式
    private func setupContentMode(with config: PCVAPConfigModel) {
        guard let info = config.info else { return }
        
        let layoutWidth = bounds.width
        let layoutHeight = bounds.height
        let layoutRatio = layoutWidth / layoutHeight
        let videoRatio = info.size.width / info.size.height
        
        var realWidth: CGFloat = 0
        var realHeight: CGFloat = 0
        
        switch vapContentMode {
        case .scaleToFill:
            // 不做处理，使用默认大小
            break
            
        case .aspectFit:
            if layoutRatio < videoRatio {
                realWidth = layoutWidth
                realHeight = realWidth / videoRatio
            } else {
                realHeight = layoutHeight
                realWidth = videoRatio * realHeight
            }
            vapView?.frame = CGRect(x: 0, y: 0, width: realWidth, height: realHeight)
            vapView?.center = center
            
        case .aspectFill:
            if layoutRatio > videoRatio {
                realWidth = layoutWidth
                realHeight = realWidth / videoRatio
            } else {
                realHeight = layoutHeight
                realWidth = videoRatio * realHeight
            }
            vapView?.frame = CGRect(x: 0, y: 0, width: realWidth, height: realHeight)
            vapView?.center = center
        }
    }
}

// MARK: - PCHWDMP4PlayDelegate

extension PCVAPWrapView: PCHWDMP4PlayDelegate {
    public func shouldStartPlayMP4(_ container: PCVAPView, config: PCVAPConfigModel) -> Bool {
        setupContentMode(with: config)
        
        if let delegate = delegate {
            return delegate.vapWrap_viewshouldStartPlayMP4(container, config: config)
        }
        return true
    }
    
    public func viewDidStartPlayMP4(_ container: PCVAPView) {
        delegate?.vapWrap_viewDidStartPlayMP4(container)
    }
    
    @objc public func viewDidPlayMP4AtFrame(_ frame: PCMP4AnimatedImageFrame, view: PCVAPView) {
        delegate?.vapWrap_viewDidPlayMP4AtFrame(frame, view: view)
    }
    
    public func viewDidStopPlayMP4(_ lastFrameIndex: Int, view: PCVAPView) {
        delegate?.vapWrap_viewDidStopPlayMP4(lastFrameIndex, view: view)
        
        if autoDestoryAfterFinish {
            DispatchQueue.main.async { [weak self] in
                self?.vapView?.removeFromSuperview()
                self?.vapView = nil
            }
        }
    }
    
    public func viewDidFinishPlayMP4(_ totalFrameCount: Int, view: PCVAPView) {
        delegate?.vapWrap_viewDidFinishPlayMP4(totalFrameCount, view: view)
    }
    
    public func viewDidFailPlayMP4(_ error: Error) {
        delegate?.vapWrap_viewDidFailPlayMP4(error)
    }
    
    public func contentForVapTag(_ tag: String, resource: VAPSourceInfo) -> String? {
        return delegate?.vapWrapview_contentForVapTag(tag, resource: resource)
    }
    
    public func loadVapImage(withURL urlStr: String, context: [String: Any]?, completion: @escaping PCVAPImageCompletionBlock) {
        delegate?.vapWrapView_loadVapImage(with: urlStr, context: context ?? [:], completion: completion)
    }
}

