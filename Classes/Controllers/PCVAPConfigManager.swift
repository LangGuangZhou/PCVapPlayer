//
//  PCVAPConfigManager.swift
//  PCVapPlayer
//
//  Created by converting from Objective-C
//  Copyright © 2024. All rights reserved.
//

import Foundation
import UIKit
import Metal

/// VAP 配置委托协议
protocol VAPConfigDelegate: AnyObject {
    /// 配置资源加载完成
    /// - Parameters:
    ///   - config: 配置模型
    ///   - error: 错误信息
    func onVAPConfigResourcesLoaded(_ config: PCVAPConfigModel, error: Error?)
    
    /// 替换配置中的资源占位符（可选）
    /// - Parameters:
    ///   - tag: 标签
    ///   - resource: 资源信息
    /// - Returns: 替换后的内容，不处理直接返回 tag
    func vap_contentForTag(_ tag: String, resource: VAPSourceInfo) -> String?
    
    /// 加载图片（可选）
    /// - Parameters:
    ///   - urlStr: 图片 URL
    ///   - context: 上下文
    ///   - completion: 完成回调
    func vap_loadImage(with urlStr: String, context: [String: Any], completion: @escaping PCVAPImageCompletionBlock)
}

// 提供默认实现（可选方法）
extension VAPConfigDelegate {
    func vap_contentForTag(_ tag: String, resource: VAPSourceInfo) -> String? {
        return tag
    }
    
    func vap_loadImage(with urlStr: String, context: [String: Any], completion: @escaping PCVAPImageCompletionBlock) {
        completion(nil, NSError(domain: "PCVAPConfigManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not implemented"]), urlStr)
    }
}

/// VAP 配置管理器
class PCVAPConfigManager {
    weak var delegate: VAPConfigDelegate?
    var hasValidConfig: Bool = false
    var model: PCVAPConfigModel?
    
    private let fileInfo: PCMP4HWDFileInfo
    
    init(fileInfo: PCMP4HWDFileInfo) {
        self.fileInfo = fileInfo
        setupConfig()
    }
    
    /// 设置配置
    private func setupConfig() {
        // 注意：需要完整实现 PCMP4Parser 后才能正常工作
        guard let mp4Parser = fileInfo.mp4Parser,
              let rootBox = mp4Parser.rootBox else {
            hasValidConfig = false
            PCVAPError(kPCVAPModuleCommon, "config can not find mp4Parser or rootBox")
            return
        }
        
        guard let vapc = rootBox.subBoxOfType(.vapc) else {
            hasValidConfig = false
            PCVAPError(kPCVAPModuleCommon, "config can not find vapc box")
            return
        }
        
        hasValidConfig = true
        
        guard let vapcData = mp4Parser.readDataOfBox(vapc, length: Int(vapc.length) - 8, offset: 8) else {
            PCVAPError(kPCVAPModuleCommon, "fail to read vapc box data")
            return
        }
        
        do {
            guard let configDictionary = try JSONSerialization.jsonObject(with: vapcData, options: []) as? [String: Any] else {
                PCVAPError(kPCVAPModuleCommon, "fail to parse config as dictionary")
                return
            }
            parseConfigDictionary(configDictionary)
        } catch {
            PCVAPError(kPCVAPModuleCommon, "fail to parse config as dictionary: \(error)")
        }
    }
    
    // MARK: - Resource Loader
    
    /// 加载配置资源
    func loadConfigResources() {
        guard let model = model else {
            delegate?.onVAPConfigResourcesLoaded(PCVAPConfigModel(), error: nil)
            return
        }
        
        if model.resources.isEmpty {
            delegate?.onVAPConfigResourcesLoaded(model, error: nil)
            return
        }
        
        // 处理标签替换
        if let delegate = delegate {
            for resource in model.resources {
                if let content = delegate.vap_contentForTag(resource.contentTag, resource: resource) {
                    resource.contentTagValue = content
                }
            }
        }
        
        guard let delegate = delegate else {
            return
        }
        
        var loadError: Error?
        let group = DispatchGroup()
        
        for resource in model.resources {
            let tagContent = resource.contentTagValue
            
            PCVAPInfo(kPCVAPModuleCommon, "loadConfigResources: processing resource type=\(resource.type), loadType=\(resource.loadType), tagContent=\(tagContent)")
            
            // 处理文本资源
            if resource.type == kQGAGAttachmentSourceTypeText && resource.loadType == QGAGAttachmentSourceLoadTypeLocal {
                if let color = resource.color {
                    resource.sourceImage = PCTextureLoader.drawingImageForText(tagContent, color: color, size: resource.size, bold: resource.style == kQGAGAttachmentSourceStyleBoldText)
                    PCVAPInfo(kPCVAPModuleCommon, "loadConfigResources: generated text image for tag=\(tagContent)")
                }
            }
            
            // 处理本地图片资源
            if resource.type == kQGAGAttachmentSourceTypeImg && resource.loadType == QGAGAttachmentSourceLoadTypeLocal {
                // 本地图片资源应该通过 delegate 的 contentForVapTag 方法获取实际路径
                // 或者直接使用 tagContent 作为本地路径
                // 这里暂时跳过，因为本地图片通常不需要异步加载
                PCVAPInfo(kPCVAPModuleCommon, "loadConfigResources: skipping local image resource tag=\(tagContent) (should be handled by contentForVapTag)")
            }
            
            // 处理网络图片资源
            if resource.type == kQGAGAttachmentSourceTypeImg && resource.loadType == QGAGAttachmentSourceLoadTypeNet {
                let imageURL = tagContent
                let context: [String: Any] = ["resource": resource]
                
                var hasLeftGroup = false
                let lock = NSLock()
                
                group.enter()
                delegate.vap_loadImage(with: imageURL, context: context) { image, error, imageURL in
                    lock.lock()
                    defer { lock.unlock() }
                    
                    if hasLeftGroup {
                        return
                    }
                    hasLeftGroup = true
                    
                    if image == nil || error != nil {
                        // 图片加载失败不应该阻止播放，只记录警告
                        // 因为图片资源是可选的，只有当所有必需资源都失败时才应该阻止播放
                        let errorMsg = error?.localizedDescription ?? "Unknown error"
                        if errorMsg.contains("Not implemented") {
                            PCVAPEvent(kPCVAPModuleCommon, "loadImageWithURL [\(imageURL ?? "")] skipped: delegate not implemented (optional resource)")
                        } else {
                            PCVAPError(kPCVAPModuleCommon, "loadImageWithURL [\(imageURL ?? "")] error: \(errorMsg)")
                        }
                        // 注意：暂时不设置 loadError，允许播放继续
                        // 如果后续需要严格检查，可以在这里添加逻辑
                    }
                    resource.sourceImage = image
                    group.leave()
                }
            }
            
            // 如果 loadType 为空或未知，且是图片资源，记录警告
            if resource.type == kQGAGAttachmentSourceTypeImg && 
               resource.loadType != QGAGAttachmentSourceLoadTypeNet && 
               resource.loadType != QGAGAttachmentSourceLoadTypeLocal {
                PCVAPEvent(kPCVAPModuleCommon, "loadConfigResources: image resource with unknown loadType=\(resource.loadType), tagContent=\(tagContent)")
            }
        }
        
        group.notify(queue: DispatchQueue.main) { [weak self] in
            guard let self = self, let model = self.model else { return }
            self.delegate?.onVAPConfigResourcesLoaded(model, error: loadError)
        }
    }
    
    /// 加载 Metal 纹理
    /// - Parameter device: Metal 设备
    func loadMTLTextures(device: MTLDevice) {
        guard let model = model else { return }
        
        for resource in model.resources {
            if let image = resource.sourceImage {
                resource.texture = PCTextureLoader.loadTexture(with: image, device: device)
                resource.sourceImage = nil
            }
        }
    }
    
    /// 加载 Metal 缓冲区
    /// - Parameter device: Metal 设备
    func loadMTLBuffers(device: MTLDevice) {
        guard let model = model else { return }
        
        for resource in model.resources {
            if let color = resource.color {
                resource.colorParamsBuffer = PCTextureLoader.loadVapColorFillBuffer(with: color, device: device)
            }
        }
    }
    
    // MARK: - Parse JSON
    
    /// 解析配置字典
    private func parseConfigDictionary(_ configDic: [String: Any]) {
        guard let commonInfoDic = configDic.hwd_dicValue(for: "info") else {
            PCVAPError(kPCVAPModuleCommon, "has no commonInfoDic:\(configDic)")
            return
        }
        
        let sourcesArr = configDic.hwd_arrValue(for: "src")
        let framesArr = configDic.hwd_arrValue(for: "frame")
        
        let configModel = PCVAPConfigModel()
        self.model = configModel
        
        // 解析通用信息
        let version = commonInfoDic.hwd_integerValue(for: "v")
        let frameCount = commonInfoDic.hwd_integerValue(for: "f")
        let w = commonInfoDic.hwd_floatValue(for: "w")
        let h = commonInfoDic.hwd_floatValue(for: "h")
        let video_w = commonInfoDic.hwd_floatValue(for: "videoW")
        let video_h = commonInfoDic.hwd_floatValue(for: "videoH")
        let orientation = commonInfoDic.hwd_integerValue(for: "orien")
        let fps = commonInfoDic.hwd_integerValue(for: "fps")
        let isMerged = (commonInfoDic.hwd_integerValue(for: "isVapx") == 1)
        let a_frame = commonInfoDic.hwd_arrValue(for: "aFrame")
        let rgb_frame = commonInfoDic.hwd_arrValue(for: "rgbFrame")
        
        let commonInfo = VAPCommonInfo()
        commonInfo.version = version
        commonInfo.framesCount = frameCount
        commonInfo.size = CGSize(width: w, height: h)
        commonInfo.videoSize = CGSize(width: video_w, height: video_h)
        commonInfo.targetOrientaion = VAPOrientation(rawValue: orientation) ?? .none
        commonInfo.fps = fps
        commonInfo.isMerged = isMerged
        commonInfo.alphaAreaRect = a_frame?.hwd_rectValue() ?? .zero
        commonInfo.rgbAreaRect = rgb_frame?.hwd_rectValue() ?? .zero
        configModel.info = commonInfo
        
        // 注意：fps 是只读的计算属性，无法赋值
        // fileInfo.mp4Parser?.fps = fps
        
        // 解析资源信息
        guard let sourcesArr = sourcesArr else {
            PCVAPError(kPCVAPModuleCommon, "has no sourcesArr:\(configDic)")
            return
        }
        
        var sources: [String: VAPSourceInfo] = [:]
        for sourceDic in sourcesArr {
            guard let sourceDic = sourceDic as? [String: Any] else {
                PCVAPError(kPCVAPModuleCommon, "sourceDic is not dic:\(sourceDic)")
                continue
            }
            
            let sourceID = sourceDic.hwd_stringValue(for: "srcId")
            guard !sourceID.isEmpty else {
                PCVAPError(kPCVAPModuleCommon, "has no sourceID:\(sourceDic)")
                continue
            }
            
            let sourceType = sourceDic.hwd_stringValue(for: "srcType")
            let loadType = sourceDic.hwd_stringValue(for: "loadType")
            let contentTag = sourceDic.hwd_stringValue(for: "srcTag")
            let colorHex = sourceDic.hwd_stringValue(for: "color")
            let color = UIColor(hexString: colorHex)
            let style = sourceDic.hwd_stringValue(for: "style")
            let width = sourceDic.hwd_floatValue(for: "w")
            let height = sourceDic.hwd_floatValue(for: "h")
            let fitType = sourceDic.hwd_stringValue(for: "fitType")
            
            let sourceInfo = VAPSourceInfo()
            sourceInfo.type = sourceType
            sourceInfo.style = style
            sourceInfo.contentTag = contentTag
            sourceInfo.color = color
            sourceInfo.size = CGSize(width: width, height: height)
            sourceInfo.fitType = fitType
            sourceInfo.loadType = loadType
            sources[sourceID] = sourceInfo
        }
        configModel.resources = Array(sources.values)
        
        // 解析融合信息
        guard let framesArr = framesArr else {
            PCVAPError(kPCVAPModuleCommon, "has no framesArr:\(configDic)")
            return
        }
        
        var mergedConfig: [Int: [VAPMergedInfo]] = [:]
        for frameMergedDic in framesArr {
            guard let frameMergedDic = frameMergedDic as? [String: Any] else {
                PCVAPError(kPCVAPModuleCommon, "frameMergedDic is not dic:\(frameMergedDic)")
                continue
            }
            
            let frameIndex = frameMergedDic.hwd_integerValue(for: "i")
            var mergedInfos: [VAPMergedInfo] = []
            
            guard let mergedObjs = frameMergedDic.hwd_arrValue(for: "obj") else {
                continue
            }
            
            for mergeInfoDic in mergedObjs {
                guard let mergeInfoDic = mergeInfoDic as? [String: Any] else {
                    PCVAPError(kPCVAPModuleCommon, "mergeInfoDic is not dic:\(mergeInfoDic)")
                    continue
                }
                
                let sourceID = mergeInfoDic.hwd_stringValue(for: "srcId")
                guard let sourceInfo = sources[sourceID] else {
                    PCVAPError(kPCVAPModuleCommon, "sourceInfo is nil:\(mergeInfoDic)")
                    continue
                }
                
                let frame = mergeInfoDic.hwd_arrValue(for: "frame")
                let m_frame = mergeInfoDic.hwd_arrValue(for: "mFrame")
                let renderIndex = mergeInfoDic.hwd_integerValue(for: "z")
                let rotationAngle = mergeInfoDic.hwd_integerValue(for: "mt")
                
                let mergeInfo = VAPMergedInfo()
                mergeInfo.source = sourceInfo
                mergeInfo.renderIndex = renderIndex
                mergeInfo.needMask = (m_frame != nil)
                mergeInfo.renderRect = frame?.hwd_rectValue() ?? .zero
                mergeInfo.maskRect = m_frame?.hwd_rectValue() ?? .zero
                mergeInfo.maskRotation = rotationAngle
                mergedInfos.append(mergeInfo)
            }
            
            let sortedMergeInfos = mergedInfos.sorted { $0.renderIndex < $1.renderIndex }
            mergedConfig[frameIndex] = sortedMergeInfos
        }
        configModel.mergedConfig = mergedConfig
    }
}

