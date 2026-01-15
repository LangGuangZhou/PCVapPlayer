//
//  PCMP4ParserProxy.swift
//  PCVapPlayer
//
//  Created by converting from Objective-C
//  Copyright © 2024. All rights reserved.
//

import Foundation

// Note: PCMP4Box and PCMP4Parser types are defined in PCMP4Box.swift and PCMP4Parser.swift
// PCLogger functions are defined in PCLogger.swift
// This file depends on those types being available in the same module

/// MP4 解析器代理
/// 提供高级接口来访问 MP4 文件信息
class PCMP4ParserProxy: PCMP4ParserDelegate {
    var picWidth: Int {
        if _picWidth == 0 {
            _picWidth = readPicWidth()
        }
        return _picWidth
    }
    
    var picHeight: Int {
        if _picHeight == 0 {
            _picHeight = readPicHeight()
        }
        return _picHeight
    }
    
    var fps: Int {
        if _fps == 0 {
            let samples = videoSamples
            if samples.isEmpty {
                return 0
            }
            
            let calculatedDuration = duration
            // 修复：检查 duration 是否为 0 或无效，避免除零错误
            if calculatedDuration > 0 && calculatedDuration.isFinite {
                _fps = Int(round(Double(samples.count) / calculatedDuration))
            } else {
                // 如果 duration 无效，尝试从 stts box 计算 fps
                _fps = calculateFpsFromStts() ?? 30  // 默认 30 fps
                PCVAPEvent(kPCVAPModuleCommon, "fps: duration is invalid(\(calculatedDuration)), calculated from stts: \(_fps)")
            }
        }
        return _fps
    }
    
    var duration: Double {
        if _duration == 0 {
            _duration = readDuration()
            PCVAPInfo(kPCVAPModuleCommon, "duration getter: _duration=\(_duration)")
        }
        return _duration
    }
    
    var spsData: Data?           // sps
    var ppsData: Data?           // pps
    var vpsData: Data?           // vps (H.265)
    var rootBox: PCMP4Box?         // 根 Box
    var videoTrackBox: MP4TrackBox?   // 视频轨道 Box
    var audioTrackBox: MP4TrackBox?   // 音频轨道 Box
    
    var videoSamples: [MP4Sample] {
        if let samples = _videoSamples {
            return samples
        }
        let samples = calculateVideoSamples()
        _videoSamples = samples
        return samples
    }
    
    var videoSyncSampleIndexes: [Int] {
        guard let videoTrackBox = videoTrackBox,
              let stssBox = videoTrackBox.subBoxOfType(.stss) as? MP4StssBox else {
            return []
        }
        return stssBox.syncSamples
    }
    
    var videoCodecID: PCMP4VideoStreamCodecID = .unknown  // 视频流编码器ID类型
    
    private var parser: PCMP4Parser
    private var _picWidth: Int = 0
    private var _picHeight: Int = 0
    private var _fps: Int = 0
    private var _duration: Double = 0
    private var _videoSamples: [MP4Sample]?
    
    init(filePath: String) {
        parser = PCMP4Parser(filePath: filePath)
        parser.delegate = self
    }
    
    /// 解析 MP4 文件
    func parse() {
        parser.parse()
        rootBox = parser.rootBox
        
        // 解析视频解码配置信息
        parseVideoDecoderConfigRecord()
    }
    
    /// 读取指定样本的数据包
    func readPacketOfSample(_ sampleIndex: Int) -> Data? {
        let samples = videoSamples
        if sampleIndex >= samples.count {
            PCVAPError(kPCVAPModuleCommon, "readPacketOfSample beyond bounds!:\(sampleIndex) > \(samples.count - 1)")
            return nil
        }
        
        let videoSample = samples[sampleIndex]
        let currentSampleSize = Int(videoSample.sampleSize)
        
        guard let fileHandle = parser.fileHandle else { return nil }
        fileHandle.seek(toFileOffset: UInt64(videoSample.streamOffset))
        
        // 当视频文件有问题时，sampleIndex还没有到最后，sampleIndex < self.videoSamples.count(总帧数)时，readDataOfLength长度可能为0Bytes
        return try? fileHandle.read(upToCount: currentSampleSize)
    }
    
    /// 读取 Box 数据
    func readDataOfBox(_ box: PCMP4Box?, length: Int, offset: Int) -> Data? {
        guard let box = box, length > 0, offset + length <= Int(box.length) else {
            return nil
        }
        
        guard let fileHandle = parser.fileHandle else { return nil }
        fileHandle.seek(toFileOffset: box.startIndexInBytes + UInt64(offset))
        return try? fileHandle.read(upToCount: length)
    }
    
    // MARK: - PCMP4ParserDelegate
    
    func didParsePCMP4Box(_ box: PCMP4Box, parser: PCMP4Parser) {
        // 记录所有重要的 box，便于调试
        if box.type == .hdlr || box.type == .avc1 || box.type == .hvc1 || box.type == .trak {
            PCVAPInfo(kPCVAPModuleCommon, "didParsePCMP4Box: boxType=\(box.type), boxLength=\(box.length)")
        }
        
        switch box.type {
        case .hdlr:
            PCVAPInfo(kPCVAPModuleCommon, "didParsePCMP4Box: processing hdlr box, box type=\(type(of: box)), is MP4HdlrBox=\(box is MP4HdlrBox)")
            if let hdlrBox = box as? MP4HdlrBox {
                PCVAPInfo(kPCVAPModuleCommon, "didParsePCMP4Box: hdlrBox.trackType=\(String(describing: hdlrBox.trackType))")
                
                // 添加调试信息：检查父级关系
                var currentBox: PCMP4Box? = box.superBox
                var level = 0
                while let parent = currentBox, level < 5 {
                    PCVAPInfo(kPCVAPModuleCommon, "didParsePCMP4Box: hdlr box parent level \(level): type=\(parent.type), boxLength=\(parent.length)")
                    currentBox = parent.superBox
                    level += 1
                }
                
                if let trackType = hdlrBox.trackType {
                    if let trackBox = box.superBoxOfType(.trak) as? MP4TrackBox {
                        PCVAPInfo(kPCVAPModuleCommon, "didParsePCMP4Box: found trackBox for type \(trackType)")
                        switch trackType {
                        case .video:
                            videoTrackBox = trackBox
                            PCVAPInfo(kPCVAPModuleCommon, "didParsePCMP4Box: found video track")
                        case .audio:
                            audioTrackBox = trackBox
                            PCVAPInfo(kPCVAPModuleCommon, "didParsePCMP4Box: found audio track")
                        case .hint:
                            break
                        }
                    } else {
                        PCVAPError(kPCVAPModuleCommon, "didParsePCMP4Box: hdlr box found but cannot get trackBox from superBoxOfType(.trak)")
                        // 备用方案：尝试从 rootBox 查找所有 trak box，然后检查哪个包含当前的 hdlr
                        if let rootBox = parser.rootBox {
                            // 查找所有 trak box
                            func findAllTrakBoxes(in box: PCMP4Box) -> [PCMP4Box] {
                                var trakBoxes: [PCMP4Box] = []
                                if box.type == .trak {
                                    trakBoxes.append(box)
                                }
                                for subBox in box.subBoxes {
                                    trakBoxes.append(contentsOf: findAllTrakBoxes(in: subBox))
                                }
                                return trakBoxes
                            }
                            
                            let allTrakBoxes = findAllTrakBoxes(in: rootBox)
                            PCVAPInfo(kPCVAPModuleCommon, "didParsePCMP4Box: found \(allTrakBoxes.count) trak boxes from rootBox")
                            
                            // 检查哪个 trak box 包含当前的 hdlr box
                            for trakBox in allTrakBoxes {
                                if let hdlrInTrak = trakBox.subBoxOfType(.hdlr) as? MP4HdlrBox,
                                   hdlrInTrak.trackType == trackType,
                                   hdlrInTrak.startIndexInBytes == box.startIndexInBytes {
                                    PCVAPInfo(kPCVAPModuleCommon, "didParsePCMP4Box: found matching trak box for hdlr with trackType \(trackType)")
                                    if let trackBox = trakBox as? MP4TrackBox {
                                        switch trackType {
                                        case .video:
                                            videoTrackBox = trackBox
                                            PCVAPInfo(kPCVAPModuleCommon, "didParsePCMP4Box: set videoTrackBox from rootBox search")
                                        case .audio:
                                            audioTrackBox = trackBox
                                            PCVAPInfo(kPCVAPModuleCommon, "didParsePCMP4Box: set audioTrackBox from rootBox search")
                                        case .hint:
                                            break
                                        }
                                    }
                                    break
                                }
                            }
                        }
                    }
                } else {
                    PCVAPError(kPCVAPModuleCommon, "didParsePCMP4Box: hdlr box found but trackType is nil")
                }
            } else {
                PCVAPError(kPCVAPModuleCommon, "didParsePCMP4Box: hdlr box cannot be cast to MP4HdlrBox")
            }
        case .avc1:
            videoCodecID = .h264
            PCVAPInfo(kPCVAPModuleCommon, "didParsePCMP4Box: found avc1 box, set videoCodecID to h264")
        case .hvc1:
            videoCodecID = .h265
            PCVAPInfo(kPCVAPModuleCommon, "didParsePCMP4Box: found hvc1 box, set videoCodecID to h265")
        default:
            break
        }
    }
    
    func MP4FileDidFinishParse(_ parser: PCMP4Parser) {
        PCVAPInfo(kPCVAPModuleCommon, "MP4FileDidFinishParse: videoTrackBox=\(videoTrackBox != nil ? "exists" : "nil"), videoCodecID=\(videoCodecID), audioTrackBox=\(audioTrackBox != nil ? "exists" : "nil")")
        
        // 如果 videoTrackBox 仍然为 nil，尝试从 rootBox 查找
        if videoTrackBox == nil, let rootBox = parser.rootBox {
            PCVAPInfo(kPCVAPModuleCommon, "MP4FileDidFinishParse: videoTrackBox is nil, trying to find from rootBox")
            
            // 查找所有 trak box
            func findAllTrakBoxes(in box: PCMP4Box) -> [PCMP4Box] {
                var trakBoxes: [PCMP4Box] = []
                if box.type == .trak {
                    trakBoxes.append(box)
                }
                for subBox in box.subBoxes {
                    trakBoxes.append(contentsOf: findAllTrakBoxes(in: subBox))
                }
                return trakBoxes
            }
            
            let allTrakBoxes = findAllTrakBoxes(in: rootBox)
            PCVAPInfo(kPCVAPModuleCommon, "MP4FileDidFinishParse: found \(allTrakBoxes.count) trak boxes from rootBox")
            
            // 遍历所有 trak box，查找包含 video hdlr 的
            for trakBox in allTrakBoxes {
                PCVAPInfo(kPCVAPModuleCommon, "MP4FileDidFinishParse: checking trak box, type=\(type(of: trakBox)), is MP4TrackBox=\(trakBox is MP4TrackBox)")
                if let hdlrBox = trakBox.subBoxOfType(.hdlr) as? MP4HdlrBox {
                    PCVAPInfo(kPCVAPModuleCommon, "MP4FileDidFinishParse: trak box has hdlr with trackType=\(String(describing: hdlrBox.trackType))")
                    if hdlrBox.trackType == .video {
                        // 如果 trakBox 已经是 MP4TrackBox，直接使用；否则创建一个包装
                        if let trackBox = trakBox as? MP4TrackBox {
                            videoTrackBox = trackBox
                            PCVAPInfo(kPCVAPModuleCommon, "MP4FileDidFinishParse: set videoTrackBox from post-parse search (direct cast)")
                        } else {
                            // 如果类型转换失败，创建一个新的 MP4TrackBox 并复制属性
                            let trackBox = MP4TrackBox(type: trakBox.type, startIndexInBytes: trakBox.startIndexInBytes, length: trakBox.length)
                            trackBox.superBox = trakBox.superBox
                            trackBox.subBoxes = trakBox.subBoxes
                            videoTrackBox = trackBox
                            PCVAPInfo(kPCVAPModuleCommon, "MP4FileDidFinishParse: set videoTrackBox from post-parse search (created new)")
                        }
                        break
                    } else if hdlrBox.trackType == .audio {
                        if let trackBox = trakBox as? MP4TrackBox {
                            audioTrackBox = trackBox
                            PCVAPInfo(kPCVAPModuleCommon, "MP4FileDidFinishParse: set audioTrackBox from post-parse search (direct cast)")
                        } else {
                            // 如果类型转换失败，创建一个新的 MP4TrackBox 并复制属性
                            let trackBox = MP4TrackBox(type: trakBox.type, startIndexInBytes: trakBox.startIndexInBytes, length: trakBox.length)
                            trackBox.superBox = trakBox.superBox
                            trackBox.subBoxes = trakBox.subBoxes
                            audioTrackBox = trackBox
                            PCVAPInfo(kPCVAPModuleCommon, "MP4FileDidFinishParse: set audioTrackBox from post-parse search (created new)")
                        }
                    }
                }
            }
            
            PCVAPInfo(kPCVAPModuleCommon, "MP4FileDidFinishParse: after search, videoTrackBox=\(videoTrackBox != nil ? "exists" : "nil"), audioTrackBox=\(audioTrackBox != nil ? "exists" : "nil")")
        }
    }
    
//    func MP4FileDidFinishParse(_ parser: PCMP4Parser) {
//        // 解析完成
//    }
    
    // MARK: - Private Methods
    
    /// 解析视频解码配置记录
    private func parseVideoDecoderConfigRecord() {
        PCVAPInfo(kPCVAPModuleCommon, "parseVideoDecoderConfigRecord: videoCodecID=\(videoCodecID), videoTrackBox=\(videoTrackBox != nil ? "exists" : "nil")")
        
        if videoCodecID == .h264 {
            parseAvccDecoderConfigRecord()
            PCVAPInfo(kPCVAPModuleCommon, "parseAvccDecoderConfigRecord completed: spsData=\(spsData != nil ? "exists(\(spsData!.count) bytes)" : "nil"), ppsData=\(ppsData != nil ? "exists(\(ppsData!.count) bytes)" : "nil")")
        } else if videoCodecID == .h265 {
            parseHvccDecoderConfigRecord()
            PCVAPInfo(kPCVAPModuleCommon, "parseHvccDecoderConfigRecord completed: spsData=\(spsData != nil ? "exists(\(spsData!.count) bytes)" : "nil"), ppsData=\(ppsData != nil ? "exists(\(ppsData!.count) bytes)" : "nil"), vpsData=\(vpsData != nil ? "exists(\(vpsData!.count) bytes)" : "nil")")
        } else {
            PCVAPError(kPCVAPModuleCommon, "parseVideoDecoderConfigRecord: unknown videoCodecID=\(videoCodecID)")
        }
    }
    
    /// 解析 AVC 解码配置记录
    private func parseAvccDecoderConfigRecord() {
        spsData = parseAvccSPSData()
        ppsData = parseAvccPPSData()
    }
    
    /// 解析 HEVC 解码配置记录
    private func parseHvccDecoderConfigRecord() {
        guard let videoTrackBox = videoTrackBox,
              let hvccBox = videoTrackBox.subBoxOfType(.hvcC) as? MP4HvccBox,
              let extraData = parser.readDataForBox(hvccBox),
              extraData.count > 8 else {
            return
        }
        
        let bytes = extraData.withUnsafeBytes { $0.baseAddress!.assumingMemoryBound(to: UInt8.self) }
        var index = 30  // 21 + 4 + 4
        
        // int lengthSize = ((bytes[index++] & 0xff) & 0x03) + 1;
        let arrayNum = Int(bytes[index])
        index += 1
        
        // sps pps vps 种类数量
        for _ in 0..<arrayNum {
            let value = Int(bytes[index])
            index += 1
            let naluType = value & 0x3F
            
            // sps pps vps 各自的数量
            let naluNum = (Int(bytes[index]) << 8) + Int(bytes[index + 1])
            index += 2
            
            for _ in 0..<naluNum {
                let naluLength = (Int(bytes[index]) << 8) + Int(bytes[index + 1])
                index += 2
                
                guard index + naluLength <= extraData.count else { break }
                let paramData = extraData.subdata(in: index..<(index + naluLength))
                
                if naluType == 32 {
                    // vps
                    vpsData = paramData
                } else if naluType == 33 {
                    // sps
                    spsData = paramData
                } else if naluType == 34 {
                    // pps
                    ppsData = paramData
                }
                
                index += naluLength
            }
        }
    }
    
    /// 解析 AVC SPS 数据
    private func parseAvccSPSData() -> Data? {
        guard let videoTrackBox = videoTrackBox,
              let avccBox = videoTrackBox.subBoxOfType(.avcC) as? MP4AvccBox,
              let extraData = parser.readDataForBox(avccBox),
              extraData.count > 8 else {
            return nil
        }
        
        let bytes = extraData.withUnsafeBytes { $0.baseAddress!.assumingMemoryBound(to: UInt8.self) }
        // sps数量 默认一个暂无使用
        // let spsCount = Int(bytes[13] & 0x1f)
        let spsLength = (Int(bytes[14] & 0xff) << 8) + Int(bytes[15] & 0xff)
        let naluType = Int(bytes[16] & 0x1F)
        
        if spsLength + 16 > extraData.count || naluType != 7 {
            return nil
        }
        
        return extraData.subdata(in: 16..<(16 + spsLength))
    }
    
    /// 解析 AVC PPS 数据
    private func parseAvccPPSData() -> Data? {
        guard let videoTrackBox = videoTrackBox,
              let avccBox = videoTrackBox.subBoxOfType(.avcC) as? MP4AvccBox,
              let extraData = parser.readDataForBox(avccBox),
              extraData.count > 8 else {
            return nil
        }
        
        let bytes = extraData.withUnsafeBytes { $0.baseAddress!.assumingMemoryBound(to: UInt8.self) }
        var spsCount = Int(bytes[13] & 0x1f)
        var spsLength = (Int(bytes[14] & 0xff) << 8) + Int(bytes[15] & 0xff)
        var prefixLength = 16 + spsLength
        
        while spsCount > 1 {
            if prefixLength + 2 >= extraData.count {
                return nil
            }
            let nextSpsLength = (Int(bytes[prefixLength] & 0xff) << 8) + Int(bytes[prefixLength + 1] & 0xff)
            prefixLength += nextSpsLength
            spsCount -= 1
        }
        
        // 默认1个
        // let ppsCount = Int(bytes[prefixLength] & 0xff)
        if prefixLength + 3 >= extraData.count {
            return nil
        }
        
        let ppsLength = (Int(bytes[prefixLength + 1] & 0xff) << 8) + Int(bytes[prefixLength + 2] & 0xff)
        let naluType = Int(bytes[prefixLength + 3] & 0x1F)
        
        if naluType != 8 || (ppsLength + prefixLength + 3) > extraData.count {
            return nil
        }
        
        return extraData.subdata(in: (prefixLength + 3)..<(prefixLength + 3 + ppsLength))
    }
    
    /// 读取视频宽度
    private func readPicWidth() -> Int {
        if videoCodecID == .unknown {
            return 0
        }
        
        let boxType: PCMP4BoxType = videoCodecID == .h264 ? .avc1 : .hvc1
        let sizeIndex = 32
        let readLength = 2
        
        guard let videoTrackBox = videoTrackBox,
              let avc1 = videoTrackBox.subBoxOfType(boxType),
              let fileHandle = parser.fileHandle else {
            return 0
        }
        
        fileHandle.seek(toFileOffset: avc1.startIndexInBytes + UInt64(sizeIndex))
        guard let widthData = try? fileHandle.read(upToCount: readLength),
              widthData.count >= readLength else {
            return 0
        }
        
        let bytes = widthData.withUnsafeBytes { $0.baseAddress!.assumingMemoryBound(to: UInt8.self) }
        let width = (Int(bytes[0] & 0xff) << 8) + Int(bytes[1] & 0xff)
        return width
    }
    
    /// 读取视频高度
    private func readPicHeight() -> Int {
        if videoCodecID == .unknown {
            return 0
        }
        
        let boxType: PCMP4BoxType = videoCodecID == .h264 ? .avc1 : .hvc1
        let sizeIndex = 34
        let readLength = 2
        
        guard let videoTrackBox = videoTrackBox,
              let avc1 = videoTrackBox.subBoxOfType(boxType),
              let fileHandle = parser.fileHandle else {
            return 0
        }
        
        fileHandle.seek(toFileOffset: avc1.startIndexInBytes + UInt64(sizeIndex))
        guard let heightData = try? fileHandle.read(upToCount: readLength),
              heightData.count >= readLength else {
            return 0
        }
        
        let bytes = heightData.withUnsafeBytes { $0.baseAddress!.assumingMemoryBound(to: UInt8.self) }
        let height = (Int(bytes[0] & 0xff) << 8) + Int(bytes[1] & 0xff)
        return height
    }
    
    /// 从 stts box 计算 fps（备用方法，当 duration 无效时使用）
    private func calculateFpsFromStts() -> Int? {
        guard let videoTrackBox = videoTrackBox,
              let sttsBox = videoTrackBox.subBoxOfType(.stts) as? MP4SttsBox,
              !sttsBox.entries.isEmpty else {
            return nil
        }
        
        // 获取视频轨道的 timescale（从 mdhd box）
        guard let mdhdBox = videoTrackBox.subBoxOfType(.mdhd),
              let mdhdData = parser.readDataForBox(mdhdBox) else {
            return nil
        }
        
        let bytes = mdhdData.withUnsafeBytes { $0.baseAddress!.assumingMemoryBound(to: UInt8.self) }
        guard mdhdData.count >= 24 else {
            return nil
        }
        
        let version = READ32BIT(bytes.advanced(by: 8))
        
        var timescaleIndex = 20
        if version == 1 {
            timescaleIndex = 28
        }
        
        guard mdhdData.count >= timescaleIndex + 4 else {
            return nil
        }
        
        let timescale = parser.readValue(bytes.advanced(by: timescaleIndex), length: 4)
        
        if timescale == 0 {
            return nil
        }
        
        // 使用第一个 stts entry 的 sampleDelta 计算 fps
        // fps = timescale / sampleDelta
        let sampleDelta = sttsBox.entries[0].sampleDelta
        if sampleDelta == 0 {
            return nil
        }
        
        let calculatedFps = Int(round(Double(timescale) / Double(sampleDelta)))
        return calculatedFps > 0 ? calculatedFps : nil
    }
    
    /// 读取视频时长
    private func readDuration() -> Double {
        guard let rootBox = rootBox else {
            PCVAPError(kPCVAPModuleCommon, "readDuration: rootBox is nil")
            return 0
        }
        
        // 修复：mvhd box 现在应该正确映射为 MP4MvhdBox
        guard let mvhdBox = rootBox.subBoxOfType(.mvhd) as? MP4MvhdBox else {
            PCVAPError(kPCVAPModuleCommon, "readDuration: mvhd box not found or wrong type")
            // 调试：打印所有子 box 类型
            PCVAPInfo(kPCVAPModuleCommon, "readDuration: rootBox type=\(rootBox.typeString), subBoxes count=\(rootBox.subBoxes.count)")
            for (index, subBox) in rootBox.subBoxes.enumerated() {
                PCVAPInfo(kPCVAPModuleCommon, "readDuration: subBox[\(index)] type=\(subBox.typeString)")
                if subBox.type == .moov {
                    PCVAPInfo(kPCVAPModuleCommon, "readDuration: moov subBoxes count=\(subBox.subBoxes.count)")
                    for (moovIndex, moovSubBox) in subBox.subBoxes.enumerated() {
                        PCVAPInfo(kPCVAPModuleCommon, "readDuration: moov.subBox[\(moovIndex)] type=\(moovSubBox.typeString)")
                    }
                }
            }
            return 0
        }
        
        guard let mvhdData = parser.readDataForBox(mvhdBox) else {
            PCVAPError(kPCVAPModuleCommon, "readDuration: failed to read mvhd data")
            return 0
        }
        
        guard mvhdData.count >= 32 else {
            PCVAPError(kPCVAPModuleCommon, "readDuration: mvhd data too short, count=\(mvhdData.count)")
            return 0
        }
        
        let bytes = mvhdData.withUnsafeBytes { $0.baseAddress!.assumingMemoryBound(to: UInt8.self) }
        let version = READ32BIT(bytes.advanced(by: 8))
        
        PCVAPInfo(kPCVAPModuleCommon, "readDuration: mvhd version=\(version), dataSize=\(mvhdData.count)")
        
        var timescaleIndex = 20
        var timescaleLength = 4
        var durationIndex = 24
        var durationLength = 4
        
        if version == 1 {
            timescaleIndex = 28
            durationIndex = 32
            durationLength = 8
            guard mvhdData.count >= 40 else {
                PCVAPError(kPCVAPModuleCommon, "readDuration: mvhd version 1 data too short, count=\(mvhdData.count)")
                return 0
            }
        }
        
        let scale = parser.readValue(bytes.advanced(by: timescaleIndex), length: timescaleLength)
        let duration = parser.readValue(bytes.advanced(by: durationIndex), length: durationLength)
        
        PCVAPInfo(kPCVAPModuleCommon, "readDuration: scale=\(scale), duration=\(duration)")
        
        if scale == 0 {
            PCVAPError(kPCVAPModuleCommon, "readDuration: scale is 0, cannot calculate duration")
            return 0
        }
        
        let result = Double(duration) / Double(scale)
        PCVAPInfo(kPCVAPModuleCommon, "readDuration: calculated duration=\(result) seconds")
        return result
    }
    
    /// 计算视频样本
    private func calculateVideoSamples() -> [MP4Sample] {
        guard let videoTrackBox = videoTrackBox else {
            return []
        }
        
        guard let sttsBox = videoTrackBox.subBoxOfType(.stts) as? MP4SttsBox,
              let stszBox = videoTrackBox.subBoxOfType(.stsz) as? MP4StszBox,
              let stscBox = videoTrackBox.subBoxOfType(.stsc) as? MP4StscBox,
              let stcoBox = videoTrackBox.subBoxOfType(.stco) as? MP4StcoBox else {
            return []
        }
        
        let cttsBox = videoTrackBox.subBoxOfType(.ctts) as? MP4CttsBox
        
        var videoSamples: [MP4Sample] = []
        var tmp: UInt64 = 0
        
        var stscEntryIndex = 0
        var stscEntrySampleIndex = 0
        var stscEntrySampleOffset: UInt32 = 0
        var sttsEntryIndex = 0
        var sttsEntrySampleIndex = 0
        var stcoChunkLogicIndex = 0
        
        for i in 0..<stszBox.sampleCount {
            if stscEntryIndex >= stscBox.entries.count ||
               sttsEntryIndex >= sttsBox.entries.count ||
               stcoChunkLogicIndex >= stcoBox.chunkOffsets.count {
                break
            }
            
            let stscEntry = stscBox.entries[stscEntryIndex]
            let sttsEntry = sttsBox.entries[sttsEntryIndex]
            let sampleOffset = stcoBox.chunkOffsets[stcoChunkLogicIndex] + stscEntrySampleOffset
            
            var ctts: UInt32 = 0
            if let cttsBox = cttsBox, i < cttsBox.compositionOffsets.count {
                ctts = cttsBox.compositionOffsets[Int(i)]
            }
            
            let sample = MP4Sample()
            sample.codecType = .video
            sample.sampleIndex = UInt32(i)
            sample.chunkIndex = UInt32(stcoChunkLogicIndex)
            sample.sampleDelta = sttsEntry.sampleDelta
            sample.sampleSize = stszBox.sampleSizes[Int(i)]
            sample.pts = tmp + UInt64(ctts)
            sample.streamOffset = sampleOffset
            videoSamples.append(sample)
            
            stscEntrySampleOffset += sample.sampleSize
            tmp += UInt64(sample.sampleDelta)
            
            stscEntrySampleIndex += 1
            if stscEntrySampleIndex >= stscEntry.samplesPerChunk {
                if stcoChunkLogicIndex + 1 < stcoBox.chunkOffsets.count {
                    stcoChunkLogicIndex += 1
                }
                stscEntrySampleIndex = 0
                stscEntrySampleOffset = 0
            }
            
            sttsEntrySampleIndex += 1
            if sttsEntrySampleIndex >= sttsEntry.sampleCount {
                sttsEntrySampleIndex = 0
                if sttsEntryIndex + 1 < sttsBox.entries.count {
                    sttsEntryIndex += 1
                }
            }
            
            if stscEntryIndex + 1 < stscBox.entries.count {
                if stcoChunkLogicIndex >= Int(stscBox.entries[stscEntryIndex + 1].firstChunk) - 1 {
                    stscEntryIndex += 1
                }
            }
        }
        
        _videoSamples = videoSamples
        return videoSamples
    }
}

