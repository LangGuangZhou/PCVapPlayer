//
//  UIView+VAP.swift
//  PCVapPlayer
//
//  Created by converting from Objective-C
//  Copyright © 2024. All rights reserved.
//

import UIKit
import Foundation
import CoreVideo

// MARK: - Protocols

/// MP4 播放委托协议
/// 注意：回调方法会在子线程被执行
public protocol PCHWDMP4PlayDelegate: AnyObject {
    /// 即将开始播放时询问，true 马上开始播放，false 放弃播放
    func shouldStartPlayMP4(_ container: PCVAPView, config: PCVAPConfigModel) -> Bool
    
    /// 开始播放
    func viewDidStartPlayMP4(_ container: PCVAPView)
    
    /// 播放到指定帧
    func viewDidPlayMP4AtFrame(_ frame: PCMP4AnimatedImageFrame, view: PCVAPView)
    
    /// 停止播放
    func viewDidStopPlayMP4(_ lastFrameIndex: Int, view: PCVAPView)
    
    /// 播放完成
    func viewDidFinishPlayMP4(_ totalFrameCount: Int, view: PCVAPView)
    
    /// 播放失败
    func viewDidFailPlayMP4(_ error: Error)
    
    // MARK: - VAP APIs
    
    /// 替换配置中的资源占位符（不处理直接返回 tag）
    func contentForVapTag(_ tag: String, resource: VAPSourceInfo) -> String?
    
    /// 由于组件内不包含网络图片加载的模块，因此需要外部支持图片加载
    func loadVapImage(withURL urlStr: String, context: [String: Any]?, completion: @escaping PCVAPImageCompletionBlock)
}

// MARK: - Default Implementations

extension PCHWDMP4PlayDelegate {
    func shouldStartPlayMP4(_ container: PCVAPView, config: PCVAPConfigModel) -> Bool { return true }
    func viewDidStartPlayMP4(_ container: PCVAPView) {}
    func viewDidPlayMP4AtFrame(_ frame: PCMP4AnimatedImageFrame, view: PCVAPView) {}
    func viewDidStopPlayMP4(_ lastFrameIndex: Int, view: PCVAPView) {}
    func viewDidFinishPlayMP4(_ totalFrameCount: Int, view: PCVAPView) {}
    func viewDidFailPlayMP4(_ error: Error) {}
    func contentForVapTag(_ tag: String, resource: VAPSourceInfo) -> String? { return nil }
    func loadVapImage(withURL urlStr: String, context: [String: Any]?, completion: @escaping PCVAPImageCompletionBlock) {}
}

// MARK: - UIView VAP Extension

public extension UIView {
    // MARK: - Associated Object Keys
    
    private struct AssociatedKeys {
        static var hwdDelegate = "MP4PlayDelegate"
        static var hwdCurrentFrameInstance = "hwd_currentFrameInstance"
        static var hwdFileInfo = "hwd_fileInfo"
        static var hwdDecodeManager = "hwd_decodeManager"
        static var hwdDecodeConfig = "hwd_decodeConfig"
        static var hwdCallbackQueue = "hwd_callbackQueue"
        static var hwdMetalView = "hwd_metalView"
        static var vapMetalView = "vap_metalView"
        static var hwdConfigManager = "hwd_configManager"
        static var vapRenderQueue = "vap_renderQueue"
        static var hwdMP4FilePath = "hwd_MP4FilePath"
        
        // C types
        static var hwdOnPause = "hwd_onPause"
        static var hwdOnSeek = "hwd_onSeek"
        static var hwdWasPausedBeforeSeek = "hwd_wasPausedBeforeSeek"
        static var hwdSeekTargetFrame = "hwd_seekTargetFrame"
        static var hwdEnterBackgroundOP = "hwd_enterBackgroundOP"
        static var hwdRenderByOpenGL = "hwd_renderByOpenGL"
        static var hwdIsFinish = "hwd_isFinish"
        static var hwdFps = "hwd_fps"
        static var hwdBlendMode = "hwd_blendMode"
        static var hwdRepeatCount = "hwd_repeatCount"
        static var vapEnableOldVersion = "vap_enableOldVersion"
        static var vapIsMute = "vap_isMute"
    }
    
    // MARK: - Properties
    
    /// 播放委托
    public var hwd_Delegate: PCHWDMP4PlayDelegate? {
        get {
            if let proxy = objc_getAssociatedObject(self, &AssociatedKeys.hwdDelegate) as? PCWeakProxy {
                return proxy.target as? PCHWDMP4PlayDelegate
            }
            return objc_getAssociatedObject(self, &AssociatedKeys.hwdDelegate) as? PCHWDMP4PlayDelegate
        }
        set {
            // 解决循环播放问题，本身已经是一个 weakproxy 对象，就不再处理
            var weakDelegate: Any? = newValue
            if let delegate = newValue, !(delegate is PCWeakProxy) {
                weakDelegate = PCWeakProxy(target: delegate)
            }
            objc_setAssociatedObject(self, &AssociatedKeys.hwdDelegate, weakDelegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    /// 当前帧
    public var hwd_currentFrame: PCMP4AnimatedImageFrame? {
        return hwd_currentFrameInstance
    }
    
    /// MP4 文件路径
    public var hwd_MP4FilePath: String? {
        get {
            return objc_getAssociatedObject(self, &AssociatedKeys.hwdMP4FilePath) as? String
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.hwdMP4FilePath, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    /// FPS for display
    public var hwd_fps: Int {
        get {
            if let value = objc_getAssociatedObject(self, &AssociatedKeys.hwdFps) as? NSNumber {
                return value.intValue
            }
            return 0
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.hwdFps, NSNumber(value: newValue), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    /// 是否使用 OpenGL 渲染（iOS 15+ 已废弃，默认使用 Metal）
    public var hwd_renderByOpenGL: Bool {
        get {
            if let value = objc_getAssociatedObject(self, &AssociatedKeys.hwdRenderByOpenGL) as? NSNumber {
                return value.boolValue
            }
            return false
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.hwdRenderByOpenGL, NSNumber(value: newValue), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    /// 在退后台时的行为，默认为结束
    public var hwd_enterBackgroundOP: PCHWDMP4EBOperationType {
        get {
            if let value = objc_getAssociatedObject(self, &AssociatedKeys.hwdEnterBackgroundOP) as? NSNumber,
               let type = PCHWDMP4EBOperationType(rawValue: value.uintValue) {
                return type
            }
            return .stop
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.hwdEnterBackgroundOP, NSNumber(value: newValue.rawValue), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    // MARK: - Private Properties
    
    private var hwd_currentFrameInstance: PCMP4AnimatedImageFrame? {
        get {
            return objc_getAssociatedObject(self, &AssociatedKeys.hwdCurrentFrameInstance) as? PCMP4AnimatedImageFrame
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.hwdCurrentFrameInstance, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    private var hwd_fileInfo: PCMP4HWDFileInfo? {
        get {
            return objc_getAssociatedObject(self, &AssociatedKeys.hwdFileInfo) as? PCMP4HWDFileInfo
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.hwdFileInfo, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    private var hwd_decodeManager: PCAnimatedImageDecodeManager? {
        get {
            return objc_getAssociatedObject(self, &AssociatedKeys.hwdDecodeManager) as? PCAnimatedImageDecodeManager
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.hwdDecodeManager, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    private var hwd_decodeConfig: PCAnimatedImageDecodeConfig? {
        get {
            return objc_getAssociatedObject(self, &AssociatedKeys.hwdDecodeConfig) as? PCAnimatedImageDecodeConfig
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.hwdDecodeConfig, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    private var hwd_callbackQueue: OperationQueue? {
        get {
            return objc_getAssociatedObject(self, &AssociatedKeys.hwdCallbackQueue) as? OperationQueue
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.hwdCallbackQueue, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    private var hwd_metalView: PCHWDMetalView? {
        get {
            return objc_getAssociatedObject(self, &AssociatedKeys.hwdMetalView) as? PCHWDMetalView
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.hwdMetalView, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    private var vap_metalView: PCVAPMetalView? {
        get {
            return objc_getAssociatedObject(self, &AssociatedKeys.vapMetalView) as? PCVAPMetalView
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.vapMetalView, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    private var hwd_configManager: PCVAPConfigManager? {
        get {
            return objc_getAssociatedObject(self, &AssociatedKeys.hwdConfigManager) as? PCVAPConfigManager
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.hwdConfigManager, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    private var vap_renderQueue: DispatchQueue? {
        get {
            return objc_getAssociatedObject(self, &AssociatedKeys.vapRenderQueue) as? DispatchQueue
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.vapRenderQueue, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    private var hwd_onPause: Bool {
        get {
            if let value = objc_getAssociatedObject(self, &AssociatedKeys.hwdOnPause) as? NSNumber {
                return value.boolValue
            }
            return false
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.hwdOnPause, NSNumber(value: newValue), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    private var hwd_onSeek: Bool {
        get {
            if let value = objc_getAssociatedObject(self, &AssociatedKeys.hwdOnSeek) as? NSNumber {
                return value.boolValue
            }
            return false
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.hwdOnSeek, NSNumber(value: newValue), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    private var hwd_isFinish: Bool {
        get {
            if let value = objc_getAssociatedObject(self, &AssociatedKeys.hwdIsFinish) as? NSNumber {
                return value.boolValue
            }
            return false
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.hwdIsFinish, NSNumber(value: newValue), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    private var hwd_blendMode: PCTextureBlendMode {
        get {
            if let value = objc_getAssociatedObject(self, &AssociatedKeys.hwdBlendMode) as? NSNumber,
               let mode = PCTextureBlendMode(rawValue: value.intValue) {
                return mode
            }
            return .alphaLeft
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.hwdBlendMode, NSNumber(value: newValue.rawValue), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    private var hwd_repeatCount: Int {
        get {
            if let value = objc_getAssociatedObject(self, &AssociatedKeys.hwdRepeatCount) as? NSNumber {
                return value.intValue
            }
            return 0
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.hwdRepeatCount, NSNumber(value: newValue), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    private var vap_enableOldVersion: Bool {
        get {
            if let value = objc_getAssociatedObject(self, &AssociatedKeys.vapEnableOldVersion) as? NSNumber {
                return value.boolValue
            }
            return false
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.vapEnableOldVersion, NSNumber(value: newValue), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    private var vap_isMute: Bool {
        get {
            if let value = objc_getAssociatedObject(self, &AssociatedKeys.vapIsMute) as? NSNumber {
                return value.boolValue
            }
            return false
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.vapIsMute, NSNumber(value: newValue), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    private var useVapMetalView: Bool {
        return hwd_configManager?.hasValidConfig ?? false
    }
    
    // MARK: - Public Methods
    
    /// 播放 MP4（播放一遍，alpha 数据在左边，不需要回调）
    public func playHWDMp4(_ filePath: String) {
        playHWDMP4(filePath, delegate: nil as PCHWDMP4PlayDelegate?)
    }
    
    /// 播放 MP4（播放一遍，alpha 数据在左边，设置回调）
    public func playHWDMP4(_ filePath: String, delegate: PCHWDMP4PlayDelegate?) {
        p_playHWDMP4(filePath, fps: 0, blendMode: PCTextureBlendMode.alphaLeft, repeatCount: 0, delegate: delegate)
    }
    
    /// 播放 MP4（alpha 数据在左边）
    public func playHWDMP4(_ filePath: String, repeatCount: Int, delegate: PCHWDMP4PlayDelegate?) {
        p_playHWDMP4(filePath, fps: 0, blendMode: PCTextureBlendMode.alphaLeft, repeatCount: repeatCount, delegate: delegate)
    }
    
    /// 停止播放
    public func stopHWDMP4() {
        hwd_stopHWDMP4()
    }
    
    /// 暂停播放
    public func pauseHWDMP4() {
        PCVAPInfo(kPCVAPModuleCommon, "pauseHWDMP4")
        hwd_onPause = true
        hwd_decodeManager?.tryToPauseAudioPlay()
    }
    
    /// 恢复播放
    public func resumeHWDMP4() {
        PCVAPInfo(kPCVAPModuleCommon, "resumeHWDMP4")
        hwd_onPause = false
        
        // 获取当前帧索引，用于计算音频播放位置
        let currentFrameIndex: Int?
        if let currentFrame = hwd_currentFrame {
            currentFrameIndex = currentFrame.frameIndex
        } else {
            currentFrameIndex = nil
        }
        
        // 根据当前帧索引恢复音频播放（确保视频和音频同步）
        hwd_decodeManager?.tryToResumeAudioPlay(frameIndex: currentFrameIndex)
    }
    
    /// 根据帧索引计算对应的时间（用于音频同步）
    private func calculateTimeForFrame(_ frameIndex: Int) -> TimeInterval? {
        guard let fileInfo = hwd_fileInfo,
              let mp4Parser = fileInfo.mp4Parser else {
            return nil
        }
        
        // 方法1: 使用 fps 计算
        let fps = mp4Parser.fps
        if fps > 0 {
            return Double(frameIndex) / Double(fps)
        }
        
        // 方法2: 使用 duration 和总帧数计算（备用方法）
        let duration = mp4Parser.duration
        let totalFrames = mp4Parser.videoSamples.count
        if totalFrames > 0 && duration > 0 {
            return (Double(frameIndex) / Double(totalFrames)) * duration
        }
        
        return nil
    }
    
    /// Seek 到指定帧
    /// - Parameter frameIndex: 目标帧索引（从 0 开始）
    /// - Note: 此方法会暂停当前播放，执行 seek 操作。seek 完成后，如果之前是播放状态，会自动恢复播放
    public func seekToFrame(_ frameIndex: Int) {
        guard frameIndex >= 0 else {
            PCVAPError(kPCVAPModuleCommon, "seekToFrame: invalid frame index \(frameIndex)")
            return
        }
        
        guard let decodeManager = hwd_decodeManager else {
            PCVAPError(kPCVAPModuleCommon, "seekToFrame: decodeManager is nil, cannot seek")
            return
        }
        
        guard !hwd_isFinish else {
            PCVAPError(kPCVAPModuleCommon, "seekToFrame: playback is finished, cannot seek")
            return
        }
        
        PCVAPInfo(kPCVAPModuleCommon, "seekToFrame: seeking to frame \(frameIndex)")
        
        // 记录 seek 前的暂停状态（用于 seek 完成后恢复播放）
        let wasPausedBeforeSeek = hwd_onPause
        
        // 暂停播放（如果还没有暂停）
        if !wasPausedBeforeSeek {
            pauseHWDMP4()
        }
        
        // 使用关联对象存储 seek 的目标帧索引和暂停状态
        objc_setAssociatedObject(self, &AssociatedKeys.hwdWasPausedBeforeSeek, NSNumber(value: wasPausedBeforeSeek), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        objc_setAssociatedObject(self, &AssociatedKeys.hwdSeekTargetFrame, NSNumber(value: frameIndex), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        
        // 清空当前帧（在 seek 完成后会重新设置）
        hwd_currentFrameInstance = nil
        
        // 执行 seek（这会触发 seek 通知，hwd_onSeek 会被设置为 true）
        decodeManager.seekToFrame(frameIndex)
    }
    
    /// 注册日志回调
    public static func registerHWDLog(_ logger: @escaping PCLoggerFunc) {
        PCLogger.registerExternalLog(logger)
    }
    
    /// 当素材不包含 vapc box 时，只有在播放素材前调用此接口设置 enable 才可播放素材，否则素材无法播放
    public func enableOldVersion(_ enable: Bool) {
        vap_enableOldVersion = enable
    }
    
    /// 设置是否静音播放素材，注：在播放开始时进行设置，播放过程中设置无效，循环播放则设置后的下一次播放开始生效
    public func setMute(_ isMute: Bool) {
        vap_isMute = isMute
    }
    
    // MARK: - Private Methods
    
    private func p_playHWDMP4(_ filePath: String, fps: Int, blendMode: PCTextureBlendMode, repeatCount: Int, delegate: PCHWDMP4PlayDelegate?) {
        PCVAPInfo(kPCVAPModuleCommon, "try to display mp4:\(filePath) blendMode:\(blendMode.rawValue) fps:\(fps) repeatCount:\(repeatCount)")
        assert(Thread.isMainThread, "HWDMP4 needs to be accessed on the main thread.")
        
        // 文件路径检查
        guard !filePath.isEmpty else {
            PCVAPError(kPCVAPModuleCommon, "playHWDMP4 error! has no filePath!")
            return
        }
        
        guard FileManager.default.fileExists(atPath: filePath) else {
            PCVAPError(kPCVAPModuleCommon, "playHWDMP4 error! fileNotExistsAtPath filePath:\(filePath)")
            return
        }
        
        hwd_isFinish = false
        hwd_blendMode = blendMode
        hwd_fps = fps
        hwd_repeatCount = repeatCount
        hwd_Delegate = delegate
        
        if hwd_Delegate != nil && hwd_callbackQueue == nil {
            let queue = OperationQueue()
            queue.maxConcurrentOperationCount = 1
            hwd_callbackQueue = queue
        }
        
        // MP4 info
        let fileInfo = PCMP4HWDFileInfo(filePath: filePath)
        fileInfo.mp4Parser?.parse()
        hwd_fileInfo = fileInfo
        
        // Config manager
        let configManager = PCVAPConfigManager(fileInfo: fileInfo)
        configManager.delegate = self
        hwd_configManager = configManager
        
        // 修复：与 OC 版本保持一致，直接访问 model.info.version（OC 版本假设 model 一定存在）
        if let model = configManager.model, let version = model.info?.version, version > PCVapMaxCompatibleVersion {
            PCVAPError(kPCVAPModuleCommon, "playHWDMP4 error! not compatible vap version:\(version)!")
            stopHWDMP4()
            return
        }
        
        if !configManager.hasValidConfig && !vap_enableOldVersion {
            PCVAPError(kPCVAPModuleCommon, "playHWDMP4 error! don't has vapc box and enableOldVersion is false!")
            let error = NSError(domain: "PCVapPlayer", code: -1, userInfo: [NSLocalizedDescriptionKey: "视频文件不包含 vapc box，且未启用旧版本支持。请在播放前调用 enableOldVersion(true)"])
            hwd_callbackQueue?.addOperation {
                self.hwd_Delegate?.viewDidFailPlayMP4(error)
            }
            stopHWDMP4()
            return
        }
        
        // Reset
        hwd_currentFrameInstance = nil
        hwd_decodeManager = nil
        hwd_onPause = false
        
        if hwd_decodeConfig == nil {
            hwd_decodeConfig = PCAnimatedImageDecodeConfig.defaultConfig()
        }
        
        // Metal view (iOS 15+ 只使用 Metal)
        hwd_loadMetalViewIfNeed(mode: blendMode)
        
        if UIDevice.current.hwd_isSimulator {
            PCVAPError(kPCVAPModuleCommon, "playHWDMP4 error! not allowed in Simulator!")
            stopHWDMP4()
            return
        }
        
        if vap_renderQueue == nil {
            vap_renderQueue = DispatchQueue(label: "com.qgame.vap.render", qos: .default, attributes: [], autoreleaseFrequency: .inherit)
        }
        
        hwd_decodeManager = PCAnimatedImageDecodeManager(fileInfo: hwd_fileInfo!, config: hwd_decodeConfig!, delegate: self)
        // 设置音频播放位置监听
        hwd_decodeManager?.audioPositionDelegate = self
        hwd_configManager?.loadConfigResources() // 必须按先加载必要资源才能播放 - onVAPConfigResourcesLoaded
    }
    
    private func hwd_registerNotification() {
        NotificationCenter.default.hwd_addSafeObserver(self, selector: #selector(hwd_didReceiveEnterBackgroundNotification(_:)), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.hwd_addSafeObserver(self, selector: #selector(hwd_didReceiveWillEnterForegroundNotification(_:)), name: UIApplication.willEnterForegroundNotification, object: nil)
        
        NotificationCenter.default.hwd_addSafeObserver(self, selector: #selector(hwd_didReceiveSeekStartNotification(_:)), name: kPCVAPDecoderSeekStart, object: nil)
        NotificationCenter.default.hwd_addSafeObserver(self, selector: #selector(hwd_didReceiveSeekFinishNotification(_:)), name: kPCVAPDecoderSeekFinish, object: nil)
    }
    
    @objc private func hwd_didReceiveEnterBackgroundNotification(_ notification: Notification) {
        switch hwd_enterBackgroundOP {
        case .pauseAndResume:
            pauseHWDMP4()
        case .doNothing:
            break
        case .stop:
            stopHWDMP4()
        }
    }
    
    @objc private func hwd_didReceiveWillEnterForegroundNotification(_ notification: Notification) {
        switch hwd_enterBackgroundOP {
        case .pauseAndResume:
            resumeHWDMP4()
        default:
            break
        }
    }
    
    @objc private func hwd_didReceiveSeekStartNotification(_ notification: Notification) {
        if let decoder = notification.object as? PCBaseDecoder,
           hwd_decodeManager?.containsThisDecoder(decoder) == true {
            hwd_onSeek = true
        }
    }
    
    @objc private func hwd_didReceiveSeekFinishNotification(_ notification: Notification) {
        if let decoder = notification.object as? PCBaseDecoder,
           hwd_decodeManager?.containsThisDecoder(decoder) == true {
            hwd_onSeek = false
            PCVAPInfo(kPCVAPModuleCommon, "hwd_didReceiveSeekFinishNotification: seek finished")
            
            // 获取 seek 的目标帧索引
            var targetFrameIndex: Int? = nil
            if let targetFrame = objc_getAssociatedObject(self, &AssociatedKeys.hwdSeekTargetFrame) as? NSNumber {
                targetFrameIndex = targetFrame.intValue
                PCVAPInfo(kPCVAPModuleCommon, "hwd_didReceiveSeekFinishNotification: seek target frame = \(targetFrameIndex!)")
                
                // 设置当前帧为目标帧的前一帧，这样 hwd_displayNext 会从目标帧开始
                // 创建一个虚拟的帧对象，frameIndex = targetFrame - 1
                if targetFrameIndex! > 0 {
                    let virtualFrame = PCMP4AnimatedImageFrame()
                    virtualFrame.frameIndex = targetFrameIndex! - 1
                    hwd_currentFrameInstance = virtualFrame
                    PCVAPInfo(kPCVAPModuleCommon, "hwd_didReceiveSeekFinishNotification: set virtual current frame to \(targetFrameIndex! - 1), next will be \(targetFrameIndex!)")
                } else {
                    // 如果目标帧是 0，保持 nil，让 hwd_displayNext 从 0 开始
                    hwd_currentFrameInstance = nil
                    PCVAPInfo(kPCVAPModuleCommon, "hwd_didReceiveSeekFinishNotification: target frame is 0, current frame set to nil")
                }
            }
            
            // 恢复 seek 前的播放状态
            if let wasPausedBeforeSeek = objc_getAssociatedObject(self, &AssociatedKeys.hwdWasPausedBeforeSeek) as? NSNumber {
                let wasPaused = wasPausedBeforeSeek.boolValue
                
                // 在恢复播放前，确保音频位置正确（重新设置一次，因为 AVAudioPlayer 在暂停状态下设置 currentTime 可能不会立即生效）
                if let targetFrameIndex = targetFrameIndex,
                   let targetTime = calculateTimeForFrame(targetFrameIndex) {
                    PCVAPInfo(kPCVAPModuleCommon, "hwd_didReceiveSeekFinishNotification: setting audio time to \(targetTime)s for frame \(targetFrameIndex) before resuming")
                    hwd_decodeManager?.seekAudioToTime(targetTime)
                }
                
                if !wasPaused {
                    // 如果 seek 前是播放状态，自动恢复播放
                    PCVAPInfo(kPCVAPModuleCommon, "hwd_didReceiveSeekFinishNotification: resuming playback (was playing before seek)")
                    resumeHWDMP4()
                } else {
                    PCVAPInfo(kPCVAPModuleCommon, "hwd_didReceiveSeekFinishNotification: keeping paused (was paused before seek)")
                }
                // 清除存储的状态
                objc_setAssociatedObject(self, &AssociatedKeys.hwdWasPausedBeforeSeek, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                objc_setAssociatedObject(self, &AssociatedKeys.hwdSeekTargetFrame, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            }
        }
    }
    
    private func hwd_stopHWDMP4() {
        PCVAPInfo(kPCVAPModuleCommon, "hwd stop playing")
        hwd_repeatCount = 0
        
        if hwd_isFinish {
            PCVAPInfo(kPCVAPModuleCommon, "isFinish already set")
            return
        }
        
        hwd_isFinish = true
        hwd_onPause = true
        
        if let metalView = hwd_metalView {
            metalView.dispose()
        }
        
        if let vapMetalView = vap_metalView {
            vapMetalView.dispose()
        }
        
        hwd_decodeManager?.tryToStopAudioPlay()
        
        hwd_callbackQueue?.addOperation {
            if let delegate = self.hwd_Delegate {
                delegate.viewDidStopPlayMP4(self.hwd_currentFrame?.frameIndex ?? 0, view: self)
            }
        }
        
        hwd_decodeManager = nil
        hwd_decodeConfig = nil
        hwd_currentFrameInstance = nil
        hwd_fileInfo = nil
    }
    
    private func hwd_didFinishDisplay() {
        PCVAPInfo(kPCVAPModuleCommon, "hwd didFinishDisplay")
        
        hwd_callbackQueue?.addOperation {
            if let delegate = self.hwd_Delegate {
                delegate.viewDidFinishPlayMP4((self.hwd_currentFrame?.frameIndex ?? 0) + 1, view: self)
            }
        }
        
        // 修复：与 OC 版本保持一致，在条件判断中减1
        // OC: if (currentCount == -1 || currentCount-- > 0)
        // 这意味着：如果是 -1（无限循环）或者 currentCount > 0，则继续播放，并在条件中减1
        var currentCount = hwd_repeatCount
        if currentCount == -1 {
            // 无限循环，不减1
            PCVAPInfo(kPCVAPModuleCommon, "continue to display. currentCount:\(currentCount)")
            p_playHWDMP4(hwd_fileInfo?.filePath ?? "", fps: hwd_fps, blendMode: hwd_blendMode, repeatCount: currentCount, delegate: hwd_Delegate)
            return
        } else if currentCount > 0 {
            // 先减1再继续播放
            currentCount -= 1
            PCVAPInfo(kPCVAPModuleCommon, "continue to display. currentCount:\(currentCount)")
            p_playHWDMP4(hwd_fileInfo?.filePath ?? "", fps: hwd_fps, blendMode: hwd_blendMode, repeatCount: currentCount, delegate: hwd_Delegate)
            return
        }
        
        hwd_stopHWDMP4()
    }
    
    private func hwd_loadMetalViewIfNeed(mode: PCTextureBlendMode) {
        // iOS 15+ 只使用 Metal，不再支持 OpenGL
        
        // Use VAP metal
        if useVapMetalView {
            if let existingView = vap_metalView {
                existingView.commonInfo = hwd_configManager?.model?.info
                return
            }
            
            let vapMetalView = PCVAPMetalView(frame: bounds)
            vapMetalView.commonInfo = hwd_configManager?.model?.info
            vapMetalView.maskInfo = vap_maskInfo
            vapMetalView.delegate = self
            addSubview(vapMetalView)
            vapMetalView.translatesAutoresizingMaskIntoConstraints = false
            
            NSLayoutConstraint.activate([
                vapMetalView.topAnchor.constraint(equalTo: topAnchor),
                vapMetalView.leadingAnchor.constraint(equalTo: leadingAnchor),
                vapMetalView.trailingAnchor.constraint(equalTo: trailingAnchor),
                vapMetalView.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
            
            self.vap_metalView = vapMetalView
            hwd_registerNotification()
            return
        }
        
        // Use HWD metal
        if let existingView = hwd_metalView {
            existingView.blendMode = mode
            return
        }
        
        let metalView = PCHWDMetalView(frame: bounds, blendMode: mode)
        
        metalView.blendMode = mode
        metalView.delegate = self
        addSubview(metalView)
        metalView.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            metalView.topAnchor.constraint(equalTo: topAnchor),
            metalView.leadingAnchor.constraint(equalTo: leadingAnchor),
            metalView.trailingAnchor.constraint(equalTo: trailingAnchor),
            metalView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        
        hwd_metalView = metalView
        hwd_registerNotification()
    }
    
    private func hwd_loadMetalDataIfNeed() {
        guard let device = kPCHWDMetalRendererDevice else { return }
        hwd_configManager?.loadMTLTextures(device: device) // 加载所需的纹理数据
        hwd_configManager?.loadMTLBuffers(device: device) // 加载所需的 buffer
    }
    
    private func hwd_appropriateDurationForFrame(_ frame: PCMP4AnimatedImageFrame) -> TimeInterval {
        var fps = hwd_fps
        if fps < kPCHWDMP4MinFPS || fps > PCHWDMP4MaxFPS {
            if frame.defaultFps >= kPCHWDMP4MinFPS && frame.defaultFps <= PCHWDMP4MaxFPS {
                fps = frame.defaultFps
            } else {
                fps = kPCHWDMP4DefaultFPS
            }
        }
        return 1000.0 / Double(fps)
    }
    
    private func hwd_renderVideoRun() {
        let durationForWaitingFrame: TimeInterval = 16.0 / 1000.0
        let minimumDurationForLoop: TimeInterval = 1.0 / 1000.0
        var lastRenderingInterval: TimeInterval = 0
        var lastRenderingDuration: TimeInterval = 0
        
        PCVAPInfo(kPCVAPModuleCommon, "hwd_renderVideoRun started")
        
        vap_renderQueue?.async {
            if self.hwd_onPause || self.hwd_isFinish {
                PCVAPInfo(kPCVAPModuleCommon, "hwd_renderVideoRun: already paused or finished")
                return
            }
            
            // 不能将 self.hwd_onPause 判断加到 while 语句中！会导致 releasepool 不断上涨
            var loopCount = 0
            var shouldBreak = false
            while true {
                autoreleasepool {
                    loopCount += 1
                    
                    if self.hwd_isFinish {
                        PCVAPInfo(kPCVAPModuleCommon, "hwd_renderVideoRun loop [\(loopCount)]: finished, exiting")
                        shouldBreak = true
                        return // 退出 autoreleasepool，然后在 while 循环中检查 shouldBreak
                    }
                    
                    if self.hwd_onPause || self.hwd_onSeek {
                        PCVAPInfo(kPCVAPModuleCommon, "hwd_renderVideoRun loop [\(loopCount)]: paused or seeking, waiting")
                        lastRenderingInterval = Date.timeIntervalSinceReferenceDate
                        Thread.sleep(forTimeInterval: durationForWaitingFrame)
                        return // 退出 autoreleasepool，继续 while 循环（与 OC 版本的 continue 效果相同）
                    }
                    
                    var nextFrame: PCMP4AnimatedImageFrame?
                    DispatchQueue.main.sync {
                        nextFrame = self.hwd_displayNext()
                    }
                    
                    if let frame = nextFrame {
                        var duration: TimeInterval = frame.duration / 1000.0
                        if duration == 0 {
                            duration = durationForWaitingFrame
                        }
                        
                        let currentTimeInterval = Date.timeIntervalSinceReferenceDate
                        if frame.frameIndex != 0 {
                            duration -= ((currentTimeInterval - lastRenderingInterval) - lastRenderingDuration) // 追回时间
                        }
                        
                        duration = max(minimumDurationForLoop, duration)
                        lastRenderingInterval = currentTimeInterval
                        lastRenderingDuration = duration
                        
                        if loopCount % 30 == 0 || frame.frameIndex < 5 {
                            PCVAPInfo(kPCVAPModuleCommon, "hwd_renderVideoRun loop [\(loopCount)]: frameIndex=\(frame.frameIndex), duration=\(duration*1000)ms, frameDuration=\(frame.duration)ms")
                        }
                        
                        Thread.sleep(forTimeInterval: duration)
                    } else {
                        if loopCount % 30 == 0 {
                            PCVAPInfo(kPCVAPModuleCommon, "hwd_renderVideoRun loop [\(loopCount)]: no frame available, waiting")
                        }
                        Thread.sleep(forTimeInterval: durationForWaitingFrame)
                    }
                }
                
                // 检查是否需要退出循环（与 OC 版本的 break 效果相同）
                if shouldBreak {
                    break
                }
            }
            
            PCVAPInfo(kPCVAPModuleCommon, "hwd_renderVideoRun: loop ended, total loops: \(loopCount)")
        }
    }
    
    private func hwd_displayNext() -> PCMP4AnimatedImageFrame? {
        if hwd_onPause || hwd_isFinish {
            return nil
        }
        
        // 修复：与 OC 版本保持一致，先检查是否为 nil
        var nextIndex: Int
        if let currentFrame = hwd_currentFrame {
            nextIndex = currentFrame.frameIndex + 1
        } else {
            nextIndex = 0
        }
        
        guard let decodeManager = hwd_decodeManager else {
            PCVAPError(kPCVAPModuleCommon, "hwd_displayNext: decodeManager is nil")
            return nil
        }
        
        // 修复：与 OC 版本保持一致，检查类型和索引
        // OC: if (!nextFrame || nextFrame.frameIndex != nextIndex || ![nextFrame isKindOfClass:[QGMP4AnimatedImageFrame class]])
        let rawFrame = decodeManager.consumeDecodedFrame(nextIndex)
        
        guard let nextFrame = rawFrame as? PCMP4AnimatedImageFrame else {
            // 没取到预期的帧 - 添加详细日志
            if rawFrame == nil {
                PCVAPEvent(kPCVAPModuleCommon, "hwd_displayNext: consumeDecodedFrame(\(nextIndex)) returned nil - buffer may be empty or decoding not started")
            } else {
                PCVAPError(kPCVAPModuleCommon, "hwd_displayNext: consumeDecodedFrame(\(nextIndex)) returned wrong type: \(type(of: rawFrame))")
            }
            return nil
        }
        
        guard nextFrame.frameIndex == nextIndex else {
            // 帧索引不匹配
            PCVAPError(kPCVAPModuleCommon, "hwd_displayNext: frame index mismatch - expected \(nextIndex), got \(nextFrame.frameIndex)")
            return nil
        }
        
        // 音频播放
        if nextIndex == 0 {
            hwd_decodeManager?.tryToStartAudioPlay()
        }
        
        nextFrame.duration = hwd_appropriateDurationForFrame(nextFrame)
        
        // 渲染 - 与 OC 版本保持一致
        if hwd_renderByOpenGL {
            // OpenGL 渲染（iOS 15+ 已废弃，但保留兼容性）
            // hwd_openGLView?.displayPixelBuffer(nextFrame.pixelBuffer)
        } else if useVapMetalView {
            let mergeInfos = hwd_configManager?.model?.mergedConfig[nextIndex]
            if let pixelBuffer = nextFrame.pixelBuffer {
                vap_metalView?.display(pixelBuffer, mergeInfos: mergeInfos)
            }
        } else {
            if let pixelBuffer = nextFrame.pixelBuffer {
                hwd_metalView?.display(pixelBuffer)
            }
        }
        
        hwd_currentFrameInstance = nextFrame
        
        hwd_callbackQueue?.addOperation {
            if nextIndex == 0 {
                self.hwd_Delegate?.viewDidStartPlayMP4(self)
            }
            // 此处必须延迟释放，避免野指针
            self.hwd_Delegate?.viewDidPlayMP4AtFrame(self.hwd_currentFrame!, view: self)
        }
        
        return nextFrame
    }
}

// MARK: - AnimatedImageDecoderDelegate

extension UIView: AnimatedImageDecoderDelegate {
    func decoderClass(for manager: PCAnimatedImageDecodeManager) -> PCBaseDecoder.Type {
        return PCMP4FrameHWDecoder.self
    }
    
    func shouldSetupAudioPlayer() -> Bool {
        return !vap_isMute
    }
    
    func decoderDidFinishDecode(_ decoder: PCBaseDecoder) {
        PCVAPInfo(kPCVAPModuleCommon, "decoderDidFinishDecode.")
        hwd_didFinishDisplay()
    }
    
    func decoderDidFailDecode(_ decoder: PCBaseDecoder, error: Error) {
        PCVAPError(kPCVAPModuleCommon, "decoderDidFailDecode:\(error)")
        hwd_stopHWDMP4()
        hwd_callbackQueue?.addOperation {
            self.hwd_Delegate?.viewDidFailPlayMP4(error)
        }
    }
}

// MARK: - AudioPlaybackPositionDelegate
extension UIView: AudioPlaybackPositionDelegate {
    func audioPlaybackPositionDidUpdate(currentTime: TimeInterval, duration: TimeInterval) {
        // 可以在这里添加音频播放位置的监听逻辑
        // 例如：更新 UI、同步视频帧等
        // 目前只记录日志，每 1 秒输出一次（在 PCAnimatedImageDecodeManager 中已实现）
    }
}

// MARK: - PCHWDMetelViewDelegate & PCVAPMetalViewDelegate

extension UIView: PCHWDMetelViewDelegate, PCVAPMetalViewDelegate {
    func onMetalViewUnavailable() {
        PCVAPError(kPCVAPModuleCommon, "onMetalViewUnavailable")
        stopHWDMP4()
    }
}

// MARK: - VAPConfigDelegate

extension UIView: VAPConfigDelegate {
    func onVAPConfigResourcesLoaded(_ config: PCVAPConfigModel, error: Error?) {
        if let error = error {
            PCVAPError(kPCVAPModuleCommon, "onVAPConfigResourcesLoaded error: \(error.localizedDescription)")
            hwd_callbackQueue?.addOperation {
                self.hwd_Delegate?.viewDidFailPlayMP4(error)
            }
            hwd_stopHWDMP4()
            return
        }
        
        // 检查解码器是否初始化成功
        if hwd_decodeManager == nil {
            let error = NSError(domain: "PCVapPlayer", code: -1, userInfo: [NSLocalizedDescriptionKey: "解码器初始化失败，无法播放视频"])
            PCVAPError(kPCVAPModuleCommon, "onVAPConfigResourcesLoaded: decodeManager is nil, cannot start playback")
            hwd_callbackQueue?.addOperation {
                self.hwd_Delegate?.viewDidFailPlayMP4(error)
            }
            hwd_stopHWDMP4()
            return
        }
        
        PCVAPInfo(kPCVAPModuleCommon, "onVAPConfigResourcesLoaded success, starting render")
        hwd_loadMetalDataIfNeed()
        
        if let delegate = hwd_Delegate {
            let shouldStart = delegate.shouldStartPlayMP4(self, config: config)
            if !shouldStart {
                PCVAPEvent(kPCVAPModuleCommon, "shouldStartPlayMP4 return no!")
                hwd_stopHWDMP4()
                return
            }
        }
        hwd_renderVideoRun()
    }
    
    func vapContent(forTag tag: String, resource info: VAPSourceInfo) -> String? {
        return hwd_Delegate?.contentForVapTag(tag, resource: info)
    }
    
    func vapLoadImage(withURL urlStr: String, context: [String: Any]?, completion: @escaping PCVAPImageCompletionBlock) {
        if let delegate = hwd_Delegate {
            delegate.loadVapImage(withURL: urlStr, context: context, completion: completion)
        } else {
            // 图片加载是可选的，如果delegate未实现，返回nil但不报错
            // 这样不会阻止视频播放
            PCVAPEvent(kPCVAPModuleCommon, "vapLoadImage: delegate not implemented for URL [\(urlStr)], skipping (optional resource)")
            completion(nil, nil, urlStr)
        }
    }
}

// MARK: - UIView VAPGesture Extension

extension UIView {
    /// 手势识别通用接口
    /// - Parameters:
    ///   - gestureRecognizer: 需要的手势识别器
    ///   - handler: 手势识别事件回调，按照 gestureRecognizer 回调时机回调
    /// - Note: 例：`mp4View.addVapGesture(UILongPressGestureRecognizer()) { gestureRecognizer, insideSource, source in print("long press") }`
    public func addVapGesture(_ gestureRecognizer: UIGestureRecognizer, callback handler: @escaping PCVAPGestureEventBlock) {
        guard gestureRecognizer != nil else {
            PCVAPEvent(kPCVAPModuleCommon, "addVapTapGesture with empty gestureRecognizer!")
            return
        }
        
        // 如果是 PCVAPWrapView，转发给内部的 vapView
        if let wrapView = self as? PCVAPWrapView {
            wrapView.initPCVAPViewIfNeed()
            wrapView.vapView?.addVapGesture(gestureRecognizer, callback: handler)
            return
        }
        
        gestureRecognizer.addVapActionBlock { [weak self] sender in
            guard let self = self,
                  let gesture = sender as? UIGestureRecognizer else { return }
            let location = gesture.location(in: self)
            let displaySource = self.displayingSource(at: location)
            if let source = displaySource {
                handler(gesture, true, source)
            } else {
                handler(gesture, false, nil)
            }
        }
        addGestureRecognizer(gestureRecognizer)
    }
    
    /// 增加点击的手势识别
    /// - Parameter handler: 点击事件回调
    public func addVapTapGesture(_ handler: @escaping PCVAPGestureEventBlock) {
        // 如果是 PCVAPWrapView，转发给内部的 vapView
        if let wrapView = self as? PCVAPWrapView {
            wrapView.initPCVAPViewIfNeed()
            wrapView.vapView?.addVapTapGesture(handler)
            return
        }
        
        let tapGesture = UITapGestureRecognizer()
        addVapGesture(tapGesture, callback: handler)
    }
    
    /// 获取当前视图中 point 位置最近的一个 source，没有的话返回 nil
    /// - Parameter point: 当前 view 坐标系下的某一个位置
    /// - Returns: 显示项
    public func displayingSource(at point: CGPoint) -> PCVAPSourceDisplayItem? {
        guard let configManager = hwd_configManager,
              let model = configManager.model,
              let currentFrame = hwd_currentFrame else {
            return nil
        }
        
        guard var mergeInfos = model.mergedConfig[currentFrame.frameIndex] else {
            return nil
        }
        
        // 按 renderIndex 降序排序（从后往前，后渲染的在上面）
        mergeInfos.sort { $0.renderIndex > $1.renderIndex }
        
        guard let renderingPixelSize = model.info?.size,
              renderingPixelSize.width > 0,
              renderingPixelSize.height > 0 else {
            return nil
        }
        
        let viewSize = frame.size
        let xRatio = viewSize.width / renderingPixelSize.width
        let yRatio = viewSize.height / renderingPixelSize.height
        
        var targetMergeInfo: VAPMergedInfo?
        var targetSourceFrame: CGRect = .zero
        
        for mergeInfo in mergeInfos {
            let sourceRenderingRect = mergeInfo.renderRect
            let sourceRenderingFrame = CGRect(
                x: sourceRenderingRect.minX * xRatio,
                y: sourceRenderingRect.minY * yRatio,
                width: sourceRenderingRect.width * xRatio,
                height: sourceRenderingRect.height * yRatio
            )
            
            if sourceRenderingFrame.contains(point) {
                targetMergeInfo = mergeInfo
                targetSourceFrame = sourceRenderingFrame
                break
            }
        }
        
        guard let mergeInfo = targetMergeInfo else {
            return nil
        }
        
        let displayItem = PCVAPSourceDisplayItem()
        displayItem.sourceInfo = mergeInfo.source
        displayItem.frame = targetSourceFrame
        return displayItem
    }
}

// MARK: - UIView VAPMask Extension

public extension UIView {
    private struct VAPMaskAssociatedKeys {
        static var maskInfo = "PCVAPMaskInfo"
    }
    
    /// VAP 遮罩信息
    public var vap_maskInfo: PCVAPMaskInfo? {
        get {
            return objc_getAssociatedObject(self, &VAPMaskAssociatedKeys.maskInfo) as? PCVAPMaskInfo
        }
        set {
            objc_setAssociatedObject(self, &VAPMaskAssociatedKeys.maskInfo, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            vap_metalView?.maskInfo = newValue
        }
    }
}
