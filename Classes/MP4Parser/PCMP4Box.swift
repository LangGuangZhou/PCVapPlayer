//
//  PCMP4Box.swift
//  PCVapPlayer
//
//  Created by converting from Objective-C
//  Copyright © 2024. All rights reserved.
//

import Foundation

// MARK: - Constants

let kQGBoxSizeLengthInBytes: Int = 4
let kQGBoxTypeLengthInBytes: Int = 4
let kQGBoxLargeSizeLengthInBytes: Int = 8
let kQGBoxLargeSizeFlagLengthInBytes: Int = 1

// MARK: - Helper Functions

/// ATOM_TYPE 宏：将四个字符转换为 UInt32
func ATOM_TYPE(_ a: UInt8, _ b: UInt8, _ c: UInt8, _ d: UInt8) -> UInt32 {
    return UInt32(d) | (UInt32(c) << 8) | (UInt32(b) << 16) | (UInt32(a) << 24)
}

/// READ32BIT 宏：读取 32 位大端序整数
func READ32BIT(_ bytes: UnsafePointer<UInt8>) -> UInt32 {
    return (UInt32(bytes[0] & 0xff) << 24) |
           (UInt32(bytes[1] & 0xff) << 16) |
           (UInt32(bytes[2] & 0xff) << 8) |
           UInt32(bytes[3] & 0xff)
}

// MARK: - Enums

/// 编解码器类型
enum PCMP4CodecType: UInt {
    case unknown = 0
    case video
    case audio
}

/// 轨道类型
enum PCMP4TrackType: UInt32 {
    case video = 0x76696465  // 'vide'
    case audio = 0x736f756e  // 'soun'
    case hint = 0x68696e74   // 'hint'
    
    init?(rawValue: UInt32) {
        switch rawValue {
        case 0x76696465: self = .video
        case 0x736f756e: self = .audio
        case 0x68696e74: self = .hint
        default: return nil
        }
    }
}

/// 视频流编码器ID类型
enum PCMP4VideoStreamCodecID: UInt {
    case unknown = 0
    case h264
    case h265
}

/// MP4 Box 类型
enum PCMP4BoxType: UInt32 {
    case unknown = 0x0
    case ftyp = 0x66747970      // 'ftyp'
    case free = 0x66726565      // 'free'
    case mdat = 0x6d646174      // 'mdat'
    case moov = 0x6d6f6f76      // 'moov'
    case mvhd = 0x6d766864      // 'mvhd'
    case iods = 0x696f6473      // 'iods'
    case trak = 0x7472616b      // 'trak'
    case tkhd = 0x746b6864      // 'tkhd'
    case edts = 0x65647473      // 'edts'
    case elst = 0x656c7374      // 'elst'
    case mdia = 0x6d646961      // 'mdia'
    case mdhd = 0x6d646864      // 'mdhd'
    case hdlr = 0x68646c72      // 'hdlr'
    case minf = 0x6d696e66      // 'minf'
    case vmhd = 0x766d6864      // 'vmhd'
    case dinf = 0x64696e66      // 'dinf'
    case dref = 0x64726566      // 'dref'
    case url = 0x75726c         // 'url'
    case stbl = 0x7374626c      // 'stbl'
    case stsd = 0x73747364      // 'stsd'
    case avc1 = 0x61766331      // 'avc1'
    case avcC = 0x61766343      // 'avcC'
    case stts = 0x73747473      // 'stts'
    case stss = 0x73747373      // 'stss'
    case stsc = 0x73747363      // 'stsc'
    case stsz = 0x7374737a      // 'stsz'
    case stco = 0x7374636f      // 'stco'
    case ctts = 0x63747473      // 'ctts'
    case udta = 0x75647461      // 'udta'
    case meta = 0x6d657461      // 'meta'
    case ilst = 0x696c7374      // 'ilst'
    case data = 0x64617461      // 'data'
    case wide = 0x77696465      // 'wide'
    case loci = 0x6c6f6369      // 'loci'
    case smhd = 0x736d6864      // 'smhd'
    case vapc = 0x76617063      // 'vapc' - VAP专属，存储json配置信息
    case hvc1 = 0x68766331      // 'hvc1'
    case hvcC = 0x68766343      // 'hvcC'
}

// MARK: - Box Data Fetcher

typealias PCMP4BoxDataFetcher = (PCMP4Box) -> Data?

// MARK: - Box Delegate Protocol

protocol PCMP4BoxDelegate: AnyObject {
    func boxDidParsed(_ dataFetcher: PCMP4BoxDataFetcher)
}

// MARK: - Base Box Classes

/// MP4 Box 基类
class PCMP4Box: PCMP4BoxDelegate {
    var type: PCMP4BoxType = .unknown
    var length: UInt64 = 0
    var startIndexInBytes: UInt64 = 0
    weak var superBox: PCMP4Box?
    var subBoxes: [PCMP4Box] = []
    
    required init(type: PCMP4BoxType, startIndexInBytes: UInt64, length: UInt64) {
        self.type = type
        self.startIndexInBytes = startIndexInBytes
        self.length = length
    }
    
    /// 前序遍历递归查找指定类型的子box，不包含自身
    func subBoxOfType(_ type: PCMP4BoxType) -> PCMP4Box? {
        for subBox in subBoxes {
            if subBox.type == type {
                return subBox
            }
            if let found = subBox.subBoxOfType(type) {
                return found
            }
        }
        return nil
    }
    
    /// 向上查找指定类型的box，不包含自身
    func superBoxOfType(_ type: PCMP4BoxType) -> PCMP4Box? {
        if let superBox = superBox {
            if superBox.type == type {
                return superBox
            }
            return superBox.superBoxOfType(type)
        }
        return nil
    }
    
    /// Box 解析完成回调（子类可重写）
    func boxDidParsed(_ dataFetcher: PCMP4BoxDataFetcher) {
        // 子类实现
    }
    
    /// 类型字符串（用于调试）
    var typeString: String {
        var value = type.rawValue
        var result = ""
        while value > 0 {
            let hexValue = value & 0xff
            value = value >> 8
            if let char = UnicodeScalar(Int(hexValue)) {
                result = String(Character(char)) + result
            }
        }
        return result
    }
}

// MARK: - Specific Box Classes

/// 实际媒体数据
class MP4MdatBox: PCMP4Box {
}

/// AVC 配置 Box
class MP4AvccBox: PCMP4Box {
}

/// HEVC 配置 Box
class MP4HvccBox: PCMP4Box {
}

/// Movie Header Box
class MP4MvhdBox: PCMP4Box {
}

/// Sample Description Box
class MP4StsdBox: PCMP4Box {
}

/// Sample Size Box
class MP4StszBox: PCMP4Box {
    var sampleCount: UInt32 = 0
    var sampleSizes: [UInt32] = []
    
    override func boxDidParsed(_ dataFetcher: PCMP4BoxDataFetcher) {
        guard let stszData = dataFetcher(self) else { return }
        
        sampleSizes = []
        let bytes = stszData.withUnsafeBytes { $0.baseAddress!.assumingMemoryBound(to: UInt8.self) }
        let sampleSize = READ32BIT(bytes.advanced(by: 12))
        let sampleCount = READ32BIT(bytes.advanced(by: 16))
        self.sampleCount = sampleCount
        
        if sampleSize > 0 {
            // 所有 sample 大小相同
            for _ in 0..<sampleCount {
                sampleSizes.append(sampleSize)
            }
        } else {
            // 每个 sample 大小不同
            for i in 0..<sampleCount {
                let entryValue = READ32BIT(bytes.advanced(by: 20 + Int(i) * 4))
                sampleSizes.append(entryValue)
            }
        }
    }
}

/// Sample To Chunk Box Entry
class StscEntry {
    var firstChunk: UInt32 = 0
    var samplesPerChunk: UInt32 = 0
    var sampleDescriptionIndex: UInt32 = 0
}

/// Sample To Chunk Box
class MP4StscBox: PCMP4Box {
    var entries: [StscEntry] = []
    
    override func boxDidParsed(_ dataFetcher: PCMP4BoxDataFetcher) {
        guard let stscData = dataFetcher(self) else { return }
        
        entries = []
        let bytes = stscData.withUnsafeBytes { $0.baseAddress!.assumingMemoryBound(to: UInt8.self) }
        let entryCount = READ32BIT(bytes.advanced(by: 12))
        
        for i in 0..<entryCount {
            let entry = StscEntry()
            entry.firstChunk = READ32BIT(bytes.advanced(by: 16 + Int(i) * 12))
            entry.samplesPerChunk = READ32BIT(bytes.advanced(by: 16 + Int(i) * 12 + 4))
            entry.sampleDescriptionIndex = READ32BIT(bytes.advanced(by: 16 + Int(i) * 12 + 8))
            entries.append(entry)
        }
    }
}

/// Chunk Offset Box
class MP4StcoBox: PCMP4Box {
    var chunkCount: UInt32 = 0
    var chunkOffsets: [UInt32] = []
    
    override func boxDidParsed(_ dataFetcher: PCMP4BoxDataFetcher) {
        guard let stcoData = dataFetcher(self) else { return }
        
        chunkOffsets = []
        let bytes = stcoData.withUnsafeBytes { $0.baseAddress!.assumingMemoryBound(to: UInt8.self) }
        let entryCount = READ32BIT(bytes.advanced(by: 12))
        chunkCount = entryCount
        
        for i in 0..<entryCount {
            let offset = READ32BIT(bytes.advanced(by: 16 + Int(i) * 4))
            chunkOffsets.append(offset)
        }
    }
}

/// Sync Sample Box
class MP4StssBox: PCMP4Box {
    var syncSamples: [Int] = []
    
    override func boxDidParsed(_ dataFetcher: PCMP4BoxDataFetcher) {
        guard let stssData = dataFetcher(self) else { return }
        
        syncSamples = []
        let bytes = stssData.withUnsafeBytes { $0.baseAddress!.assumingMemoryBound(to: UInt8.self) }
        let sampleCount = READ32BIT(bytes.advanced(by: 12))
        
        for i in 0..<sampleCount {
            let index = Int(READ32BIT(bytes.advanced(by: 16 + Int(i) * 4))) - 1
            syncSamples.append(index)
        }
    }
}

/// Composition Time To Sample Entry
class CttsEntry {
    var sampleCount: UInt32 = 0
    var compositionOffset: UInt32 = 0
}

/// Composition Time To Sample Box
class MP4CttsBox: PCMP4Box {
    var compositionOffsets: [UInt32] = []
    
    override func boxDidParsed(_ dataFetcher: PCMP4BoxDataFetcher) {
        guard let cttsData = dataFetcher(self) else { return }
        
        compositionOffsets = []
        let bytes = cttsData.withUnsafeBytes { $0.baseAddress!.assumingMemoryBound(to: UInt8.self) }
        let entryCount = READ32BIT(bytes.advanced(by: 12))
        
        for i in 0..<entryCount {
            let sampleCount = READ32BIT(bytes.advanced(by: 16 + Int(i) * 8))
            let compositionOffset = READ32BIT(bytes.advanced(by: 16 + Int(i) * 8 + 4))
            
            for _ in 0..<sampleCount {
                compositionOffsets.append(compositionOffset)
            }
        }
    }
}

/// Time To Sample Entry
class SttsEntry {
    var sampleCount: UInt32 = 0
    var sampleDelta: UInt32 = 0
}

/// Time To Sample Box
class MP4SttsBox: PCMP4Box {
    var entries: [SttsEntry] = []
    
    override func boxDidParsed(_ dataFetcher: PCMP4BoxDataFetcher) {
        guard let sttsData = dataFetcher(self) else { return }
        
        entries = []
        let bytes = sttsData.withUnsafeBytes { $0.baseAddress!.assumingMemoryBound(to: UInt8.self) }
        let entryCount = READ32BIT(bytes.advanced(by: 12))
        
        for i in 0..<entryCount {
            let entry = SttsEntry()
            entry.sampleCount = READ32BIT(bytes.advanced(by: 16 + Int(i) * 8))
            entry.sampleDelta = READ32BIT(bytes.advanced(by: 16 + Int(i) * 8 + 4))
            entries.append(entry)
        }
    }
}

/// Track Box
class MP4TrackBox: PCMP4Box {
}

/// Handler Box
class MP4HdlrBox: PCMP4Box {
    var trackType: PCMP4TrackType?
    
    override func boxDidParsed(_ dataFetcher: PCMP4BoxDataFetcher) {
        guard let hdlrData = dataFetcher(self) else { return }
        
        let bytes = hdlrData.withUnsafeBytes { $0.baseAddress!.assumingMemoryBound(to: UInt8.self) }
        let trackTypeValue = READ32BIT(bytes.advanced(by: 16))
        trackType = PCMP4TrackType(rawValue: trackTypeValue)
    }
}

// MARK: - Sample and Entry Classes

/// MP4 Sample
class MP4Sample {
    var codecType: PCMP4CodecType = .unknown
    var sampleDelta: UInt32 = 0
    var sampleSize: UInt32 = 0
    var sampleIndex: UInt32 = 0
    var chunkIndex: UInt32 = 0
    var streamOffset: UInt32 = 0
    var pts: UInt64 = 0
    var dts: UInt64 = 0
    var isKeySample: Bool = false
}

/// Chunk Offset Entry
class ChunkOffsetEntry {
    var samplesPerChunk: UInt32 = 0
    var offset: UInt32 = 0
}

// MARK: - Box Factory

/// MP4 Box 工厂类
class PCMP4BoxFactory {
    /// 根据类型创建 Box
    static func createBoxForType(_ type: PCMP4BoxType, startIndexInBytes: UInt64, length: UInt64) -> PCMP4Box {
        if let boxClass = boxClassForType(type) {
            return boxClass.init(type: type, startIndexInBytes: startIndexInBytes, length: length)
        }
        return PCMP4Box(type: type, startIndexInBytes: startIndexInBytes, length: length)
    }
    
    /// 根据类型获取 Box 类
    static func boxClassForType(_ type: PCMP4BoxType) -> PCMP4Box.Type? {
        switch type {
        case .stss:
            return MP4StssBox.self
        case .mdat:
            return MP4MdatBox.self
        case .avcC:
            return MP4AvccBox.self
        case .mdhd:
            return MP4MvhdBox.self
        case .stsd:
            return MP4StsdBox.self
        case .stsz:
            return MP4StszBox.self
        case .hdlr:
            return MP4HdlrBox.self
        case .stsc:
            return MP4StscBox.self
        case .stts:
            return MP4SttsBox.self
        case .stco:
            return MP4StcoBox.self
        case .hvcC:
            return MP4HvccBox.self
        case .ctts:
            return MP4CttsBox.self

        case .trak:
            return MP4TrackBox.self
        case .mvhd:
            return MP4MvhdBox.self
        case .ftyp, .free, .moov, .tkhd, .edts, .elst, .mdia, .minf, .vmhd, .dinf, .dref, .url, .stbl, .avc1, .udta, .meta, .ilst, .data, .iods, .wide, .loci, .smhd:
            return PCMP4Box.self
        default:
            return nil
        }
    }
    
    /// 判断类型值是否有效
    static func isTypeValueValid(_ type: PCMP4BoxType) -> Bool {
        return boxClassForType(type) != nil
    }
}

