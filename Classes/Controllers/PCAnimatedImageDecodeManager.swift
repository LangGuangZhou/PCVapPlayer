//
//  PCAnimatedImageDecodeManager.swift
//  PCVapPlayer
//
//  Created by converting from Objective-C
//  Copyright © 2024. All rights reserved.
//

import Foundation
import AVFoundation

/// 音频播放位置监听协议
protocol AudioPlaybackPositionDelegate: AnyObject {
    /// 音频播放位置更新
    /// - Parameters:
    ///   - currentTime: 当前播放时间（秒）
    ///   - duration: 总时长（秒）
    func audioPlaybackPositionDidUpdate(currentTime: TimeInterval, duration: TimeInterval)
}

/// 解码器委托协议
protocol AnimatedImageDecoderDelegate: AnyObject {
    /// 必须实现该方法，用以实例化解码器
    /// - Parameter manager: 解码控制器
    /// - Returns: 解码器类型
    func decoderClass(for manager: PCAnimatedImageDecodeManager) -> PCBaseDecoder.Type
    
    /// 是否应该设置音频播放器（可选）
    func shouldSetupAudioPlayer() -> Bool
    
    /// 到文件末尾时被调用（可选）
    /// - Parameter decoder: 解码器
    func decoderDidFinishDecode(_ decoder: PCBaseDecoder)
    
    /// 解码失败时被调用（可选）
    /// - Parameters:
    ///   - decoder: 解码器
    ///   - error: 错误信息
    func decoderDidFailDecode(_ decoder: PCBaseDecoder?, error: Error)
}

// 提供默认实现（可选方法）
extension AnimatedImageDecoderDelegate {
    func shouldSetupAudioPlayer() -> Bool { return true }
    func decoderDidFinishDecode(_ decoder: PCBaseDecoder) {}
    func decoderDidFailDecode(_ decoder: PCBaseDecoder?, error: Error) {}
}

/// 音频播放器委托类（用于实现 AVAudioPlayerDelegate）
private class AudioPlayerDelegate: NSObject, AVAudioPlayerDelegate {
    weak var manager: PCAnimatedImageDecodeManager?
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        PCVAPInfo(kPCVAPModuleCommon, "audioPlayerDidFinishPlaying: finished successfully=\(flag)")
        manager?.stopAudioPositionMonitoring()
    }
    
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        PCVAPError(kPCVAPModuleCommon, "audioPlayerDecodeErrorDidOccur: \(error?.localizedDescription ?? "unknown error")")
        manager?.stopAudioPositionMonitoring()
    }
}

/// 动画图像解码管理器
class PCAnimatedImageDecodeManager {
    weak var decoderDelegate: AnimatedImageDecoderDelegate?
    weak var audioPositionDelegate: AudioPlaybackPositionDelegate?
    
    private let config: PCAnimatedImageDecodeConfig
    private let fileInfo: PCBaseDFileInfo
    private var decoders: PCSafeMutableArray<Any>
    private let bufferManager: PCAnimatedImageBufferManager
    private var audioPlayer: AVAudioPlayer?
    private var audioPlayerDelegate: AudioPlayerDelegate?
    private var audioPositionTimer: Timer?
    private let lock = NSRecursiveLock()
    /// 标记是否已经完成首次播放（用于优化首次播放的等待逻辑）
    private var hasStartedPlayback: Bool = false
    /// 保存暂停时的音频播放位置（用于恢复播放时确保位置正确）
    private var pausedAudioTime: TimeInterval?
    
    init(fileInfo: PCBaseDFileInfo, config: PCAnimatedImageDecodeConfig, delegate: AnimatedImageDecoderDelegate) {
        self.config = config
        self.fileInfo = fileInfo
        self.decoderDelegate = delegate
        self.decoders = PCSafeMutableArray()
        self.bufferManager = PCAnimatedImageBufferManager(config: config)
        
        createDecoders(by: config)
        initializeBuffers(from: 0)
        setupAudioPlayerIfNeed()
        setupAudioPositionMonitoring()
    }
    
    /// 取出已解码的一帧并准备下一帧
    /// - Parameter frameIndex: 帧索引
    /// - Returns: 帧内容
    func consumeDecodedFrame(_ frameIndex: Int) -> PCBaseAnimatedImageFrameImpl? {
        lock.lock()
        defer { lock.unlock() }
        
        // 控制何时命中第一帧，缓存满了才命中（仅在首次播放时等待）
        // 优化：播放过程中（包括 seek 后重新开始）不再等待，因为已经有持续提前解码机制
        if frameIndex == 0 && !hasStartedPlayback && bufferManager.buffers.count < config.bufferCount {
            PCVAPEvent(kPCVAPModuleCommon, "consumeDecodedFrame(0): waiting for buffer to fill - current count=\(bufferManager.buffers.count), required=\(config.bufferCount)")
            return nil
        }
        
        // 标记已经开始播放
        if frameIndex == 0 {
            hasStartedPlayback = true
        }
        
        let decodeFinish = checkIfDecodeFinish(frameIndex)
        let frame = bufferManager.popVideoFrame()
        
        if let frame = frame {
            // pts 顺序
            frame.frameIndex = frameIndex
            decodeFrame(frameIndex + config.bufferCount)
        } else if !decodeFinish {
            // buffer 已经空了，但还没有结束（退后台时可能出现这种情况）
            PCVAPEvent(kPCVAPModuleCommon, "consumeDecodedFrame(\(frameIndex)): buffer empty but not finished, attempting to initialize buffers")
            let decoderIndex = decoders.count == 1 ? 0 : frameIndex % decoders.count
            if let decoder = decoders.object(at: decoderIndex) as? PCBaseDecoder {
                if decoder.shouldStopDecode(frameIndex) {
                    // 其实已经该结束了
                    PCVAPInfo(kPCVAPModuleCommon, "consumeDecodedFrame(\(frameIndex)): decoder should stop, finishing decode")
                    decoderDelegate?.decoderDidFinishDecode(decoder)
                    return nil
                }
                PCVAPInfo(kPCVAPModuleCommon, "consumeDecodedFrame(\(frameIndex)): initializing buffers from frame \(frameIndex)")
                initializeBuffers(from: frameIndex)
            } else {
                PCVAPError(kPCVAPModuleCommon, "consumeDecodedFrame(\(frameIndex)): decoder not found at index \(decoderIndex), decoders count=\(decoders.count)")
            }
        } else {
            PCVAPInfo(kPCVAPModuleCommon, "consumeDecodedFrame(\(frameIndex)): decode finished")
        }
        
        return frame
    }
    
    /// 尝试开始音频播放
    func tryToStartAudioPlay() {
        guard let player = audioPlayer else { return }
        
        let currentTimeBeforePlay = player.currentTime
        PCVAPInfo(kPCVAPModuleCommon, "tryToStartAudioPlay: starting from currentTime=\(currentTimeBeforePlay)s, duration=\(player.duration)s")
        
        player.play()
        startAudioPositionMonitoring()
    }
    
    /// 尝试停止音频播放
    func tryToStopAudioPlay() {
        // CoreAudio（AVAudioPlayer）回调 audioPlayerDidFinishPlaying:successfully: 时在子线程，
        // 恰巧此时释放将可能导致野指针问题
        // 如果只是 stop 不能解决，可以考虑产生循环持有并延迟释放 audioPlayer
        stopAudioPositionMonitoring()
        pausedAudioTime = nil // 清除保存的暂停位置
        audioPlayer?.stop()
    }
    
    /// 尝试暂停音频播放
    func tryToPauseAudioPlay() {
        guard let player = audioPlayer else { return }
        let currentTimeBeforePause = player.currentTime
        // 保存暂停时的位置，以便恢复时使用
        pausedAudioTime = currentTimeBeforePause
        PCVAPInfo(kPCVAPModuleCommon, "tryToPauseAudioPlay: pausing at currentTime=\(currentTimeBeforePause)s, saved pausedAudioTime=\(pausedAudioTime!)")
        player.pause()
        stopAudioPositionMonitoring()
    }
    
    /// 尝试恢复音频播放
    /// - Parameter frameIndex: 当前视频帧索引（可选），如果提供则根据帧索引计算音频时间
    func tryToResumeAudioPlay(frameIndex: Int? = nil) {
        guard let player = audioPlayer else { return }
        
        var targetTime: TimeInterval?
        
        // 优先使用帧索引计算音频时间（确保视频和音频同步）
        if let frameIndex = frameIndex {
            // 根据帧索引计算对应的音频时间
            if let mp4FileInfo = fileInfo as? PCMP4HWDFileInfo,
               let mp4Parser = mp4FileInfo.mp4Parser {
                // 方法1: 使用 fps 计算
                let fps = mp4Parser.fps
                if fps > 0 {
                    targetTime = Double(frameIndex) / Double(fps)
                } else {
                    // 方法2: 使用 duration 和总帧数计算（备用方法）
                    let duration = mp4Parser.duration
                    let totalFrames = mp4Parser.videoSamples.count
                    if totalFrames > 0 && duration > 0 {
                        targetTime = (Double(frameIndex) / Double(totalFrames)) * duration
                    }
                }
                if let calculatedTime = targetTime {
                    PCVAPInfo(kPCVAPModuleCommon, "tryToResumeAudioPlay: calculated time from frame \(frameIndex) = \(calculatedTime)s (fps=\(fps))")
                }
            }
        }
        
        // 如果没有通过帧索引计算出时间，使用保存的暂停位置
        if targetTime == nil, let savedPausedTime = pausedAudioTime {
            targetTime = savedPausedTime
            PCVAPInfo(kPCVAPModuleCommon, "tryToResumeAudioPlay: using saved paused time = \(savedPausedTime)s")
        }
        
        // 如果还是没有目标时间，使用当前播放器的时间
        guard let targetTime = targetTime else {
            targetTime = player.currentTime
            PCVAPInfo(kPCVAPModuleCommon, "tryToResumeAudioPlay: using current player time = \(targetTime!)s")
            return
        }
        
        // 确保时间在有效范围内
        if targetTime > player.duration {
            PCVAPInfo(kPCVAPModuleCommon, "tryToResumeAudioPlay: using current player time outtime : duration:\(player.duration) = \(targetTime)s")
            return
        }
        
        let validTime = max(0, targetTime)
        
        // 设置音频播放位置,太小没必要修正
        if abs(player.currentTime - validTime) > 0.01 {
            PCVAPInfo(kPCVAPModuleCommon, "tryToResumeAudioPlay: setting audio currentTime from \(player.currentTime)s to \(validTime)s")
            player.currentTime = validTime
        }
        
        let actualTimeBeforePlay = player.currentTime
        PCVAPInfo(kPCVAPModuleCommon, "tryToResumeAudioPlay: resuming from currentTime=\(actualTimeBeforePlay)s, duration=\(player.duration)s, frameIndex=\(frameIndex?.description ?? "nil")")
        
        // 播放音频
        player.play()
        
        // 验证播放后的位置（延迟一小段时间检查，因为 play() 是异步的）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self = self, let player = self.audioPlayer else { return }
            let timeAfterPlay = player.currentTime
            if abs(timeAfterPlay - actualTimeBeforePlay) > 0.2 {
                PCVAPEvent(kPCVAPModuleCommon, "tryToResumeAudioPlay: WARNING - audio jumped from \(actualTimeBeforePlay)s to \(timeAfterPlay)s after play()")
                // 如果位置不正确，重新设置
                player.currentTime = actualTimeBeforePlay
            }
        }
        
        // 清除保存的暂停位置
        pausedAudioTime = nil
        startAudioPositionMonitoring()
    }
    
    /// 设置音频播放器的时间位置（用于 Seek 同步）
    /// - Parameter time: 时间（秒）
    func seekAudioToTime(_ time: TimeInterval) {
        guard let player = audioPlayer else {
            PCVAPInfo(kPCVAPModuleCommon, "seekAudioToTime: audioPlayer is nil, skipping audio seek")
            return
        }
        
        // 记录 seek 前的时间位置
        let timeBeforeSeek = player.currentTime
        let wasPlaying = player.isPlaying
        
        // 确保时间在有效范围内
        let validTime = max(0, min(time, player.duration))
        
        // 如果音频正在播放，需要先暂停，设置时间，然后恢复播放
        if wasPlaying {
            player.pause()
        }
        
        // 设置时间位置
        player.currentTime = validTime
        
        // 验证设置是否成功
        let actualTime = player.currentTime
        PCVAPInfo(kPCVAPModuleCommon, "seekAudioToTime: seek from \(timeBeforeSeek)s to \(validTime)s (actual: \(actualTime)s, requested: \(time)s, duration: \(player.duration)s, wasPlaying: \(wasPlaying))")
        
        // 如果设置的时间与预期不符，记录警告
        if abs(actualTime - validTime) > 0.1 {
            PCVAPEvent(kPCVAPModuleCommon, "seekAudioToTime: WARNING - actual time (\(actualTime)s) differs from requested time (\(validTime)s) by more than 0.1s")
        }
        
        // 如果之前正在播放，恢复播放
        if wasPlaying {
            // 延迟一小段时间再播放，确保 currentTime 设置生效
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { [weak self] in
                guard let self = self, let player = self.audioPlayer else { return }
                let timeAfterDelay = player.currentTime
                PCVAPInfo(kPCVAPModuleCommon, "seekAudioToTime: resuming playback after delay, currentTime=\(timeAfterDelay)s")
                player.play()
                self.startAudioPositionMonitoring()
            }
        }
    }
    
    /// 检查是否包含此解码器
    /// - Parameter decoder: 解码器
    /// - Returns: 是否包含
    func containsThisDecoder(_ decoder: Any) -> Bool {
        for i in 0..<decoders.count {
            if let d = decoders.object(at: i) as? PCBaseDecoder,
               d === decoder as? PCBaseDecoder {
                return true
            }
        }
        return false
    }
    
    /// 清空缓冲区
    func clearBuffers() {
        lock.lock()
        defer { lock.unlock() }
        bufferManager.buffers.removeAllObjects()
        PCVAPInfo(kPCVAPModuleCommon, "clearBuffers: all buffers cleared")
    }
    
    /// Seek 到指定帧
    /// - Parameter frameIndex: 目标帧索引
    func seekToFrame(_ frameIndex: Int) {
        lock.lock()
        defer { lock.unlock() }
        
        PCVAPInfo(kPCVAPModuleCommon, "seekToFrame: seeking to frame \(frameIndex)")
        
        // 计算目标帧对应的时间，用于同步音频
        var targetTime: TimeInterval = 0
        if let mp4FileInfo = fileInfo as? PCMP4HWDFileInfo,
           let mp4Parser = mp4FileInfo.mp4Parser {
            // 方法1: 使用 fps 计算
            let fps = mp4Parser.fps
            if fps > 0 {
                targetTime = Double(frameIndex) / Double(fps)
            } else {
                // 方法2: 使用 duration 和总帧数计算（备用方法）
                let duration = mp4Parser.duration
                let totalFrames = mp4Parser.videoSamples.count
                if totalFrames > 0 && duration > 0 {
                    targetTime = (Double(frameIndex) / Double(totalFrames)) * duration
                }
            }
            PCVAPInfo(kPCVAPModuleCommon, "seekToFrame: calculated target time = \(targetTime)s for frame \(frameIndex) (fps=\(fps), duration=\(mp4Parser.duration)s)")
        }
        
        // 同步音频播放器的时间位置
        if targetTime > 0 {
            seekAudioToTime(targetTime)
        }
        
        // 清空缓冲区
        clearBuffers()
        
        // Seek 后重置播放状态，允许立即开始播放（不再等待缓冲区填满）
        // 因为 seek 后会立即调用 initializeBuffers 填充缓冲区
        hasStartedPlayback = true
        
        // 获取解码器并调用 seek
        let decoderIndex = decoders.count == 1 ? 0 : frameIndex % decoders.count
        guard let decoder = decoders.object(at: decoderIndex) as? PCMP4FrameHWDecoder else {
            PCVAPError(kPCVAPModuleCommon, "seekToFrame: decoder not found or wrong type at index \(decoderIndex)")
            return
        }
        
        // 重置解码器的 lastDecodeFrame，以便 seek 后可以正确解码
        decoder.resetLastDecodeFrame()
        
        // 调用解码器的 seek 方法（同步执行，确保 seek 完成）
        decoder.findKeyFrameAndDecodeToCurrent(frameIndex)
        
        // 重新初始化缓冲区（从目标帧开始填充缓冲区）
        // 注意：findKeyFrameAndDecodeToCurrent 已经解码了目标帧，所以缓冲区应该已经有目标帧了
        // 但为了确保缓冲区有足够的帧，我们需要继续解码后续帧
        initializeBuffers(from: frameIndex)
        PCVAPInfo(kPCVAPModuleCommon, "seekToFrame: buffers initialized from frame \(frameIndex), buffer count=\(bufferManager.buffers.count)")
    }
    
    // MARK: - Private Methods
    
    private func checkIfDecodeFinish(_ frameIndex: Int) -> Bool {
        let decoderIndex = decoders.count == 1 ? 0 : frameIndex % decoders.count
        guard let decoder = decoders.object(at: decoderIndex) as? PCBaseDecoder else {
            return false
        }
        
        if decoder.isFrameIndexBeyondEnd(frameIndex) {
            decoderDelegate?.decoderDidFinishDecode(decoder)
            return true
        }
        return false
    }
    
    private func decodeFrame(_ frameIndex: Int) {
        if decoders.count == 0 {
            return
        }
        
        let decoderIndex = decoders.count == 1 ? 0 : frameIndex % decoders.count
        guard let decoder = decoders.object(at: decoderIndex) as? PCBaseDecoder else {
            return
        }
        
        if decoder.shouldStopDecode(frameIndex) {
            return
        }
        
        do {
            try decoder.decodeFrame(frameIndex, buffers: bufferManager.buffers)
        } catch {
            decoderDelegate?.decoderDidFailDecode(decoder, error: error)
        }
    }
    
    private func createDecoders(by config: PCAnimatedImageDecodeConfig) {
        guard let delegate = decoderDelegate else {
            PCVAPEvent(kPCVAPModuleCommon, "you MUST implement the delegate in invoker!")
            assertionFailure("you MUST implement the delegate in invoker!")
            return
        }
        
        decoders = PCSafeMutableArray()
        
        for _ in 0..<config.threadCount {
            let decoderClass = delegate.decoderClass(for: self)
            
            do {
                let decoder = try decoderClass.init(fileInfo: fileInfo)
                decoders.add(decoder)
            } catch {
                decoderDelegate?.decoderDidFailDecode(nil, error: error)
                break
            }
        }
    }
    
    private func initializeBuffers(from start: Int) {
        PCVAPInfo(kPCVAPModuleCommon, "initializeBuffers: starting from frame \(start), bufferCount=\(config.bufferCount)")
        for i in 0..<config.bufferCount {
            let frameIndex = start + i
            PCVAPInfo(kPCVAPModuleCommon, "initializeBuffers: calling decodeFrame(\(frameIndex))")
            decodeFrame(frameIndex)
        }
        PCVAPInfo(kPCVAPModuleCommon, "initializeBuffers: completed, all decodeFrame calls dispatched")
    }
    
    private func setupAudioPlayerIfNeed() {
        if let delegate = decoderDelegate,
           !delegate.shouldSetupAudioPlayer() {
            return
        }
        
        if let mp4FileInfo = fileInfo as? PCMP4HWDFileInfo,
           let mp4Parser = mp4FileInfo.mp4Parser {
            // 注意：需要实现 PCMP4ParserProxy 的 audioTrackBox 属性
            // 暂时注释，等待 PCMP4Parser 转换完成
            // if mp4Parser.audioTrackBox != nil {
            if let url = URL(string: fileInfo.filePath) {
                do {
                    let player = try AVAudioPlayer(contentsOf: url)
                    let delegate = AudioPlayerDelegate()
                    delegate.manager = self
                    player.delegate = delegate
                    audioPlayer = player
                    audioPlayerDelegate = delegate // 保持强引用，避免 delegate 被释放
                    PCVAPInfo(kPCVAPModuleCommon, "setupAudioPlayerIfNeed: created audio player, duration=\(player.duration)s")
                } catch {
                    PCVAPEvent(kPCVAPModuleCommon, "Failed to create audio player: \(error)")
                }
            }
            // }
        }
    }
    
    /// 设置音频播放位置监听
    private func setupAudioPositionMonitoring() {
        // 监听功能通过定时器实现
    }
    
    /// 开始监听音频播放位置
    func startAudioPositionMonitoring() {
        stopAudioPositionMonitoring() // 先停止之前的定时器
        
        guard audioPlayer != nil else { return }
        
        // 每 0.1 秒更新一次播放位置
        audioPositionTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self,
                  let player = self.audioPlayer,
                  player.isPlaying else {
                return
            }
            
            let currentTime = player.currentTime
            let duration = player.duration
            self.audioPositionDelegate?.audioPlaybackPositionDidUpdate(currentTime: currentTime, duration: duration)
            
            // 每 1 秒打印一次日志
            if Int(currentTime * 10) % 10 == 0 {
                PCVAPInfo(kPCVAPModuleCommon, "Audio playback position: \(String(format: "%.2f", currentTime))s / \(String(format: "%.2f", duration))s")
            }
        }
    }
    
    /// 停止监听音频播放位置
    func stopAudioPositionMonitoring() {
        audioPositionTimer?.invalidate()
        audioPositionTimer = nil
    }
}

