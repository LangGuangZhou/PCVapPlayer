//
//  PCMP4Parser.swift
//  PCVapPlayer
//
//  Created by converting from Objective-C
//  Copyright © 2024. All rights reserved.
//

import Foundation

// MARK: - Parser Delegate Protocol

protocol PCMP4ParserDelegate: AnyObject {
    func didParsePCMP4Box(_ box: PCMP4Box, parser: PCMP4Parser)
    func MP4FileDidFinishParse(_ parser: PCMP4Parser)
}

// MARK: - MP4 Parser

/// MP4 文件解析器
class PCMP4Parser {
    var rootBox: PCMP4Box?
    var fileHandle: FileHandle?
    weak var delegate: PCMP4ParserDelegate?
    
    private var filePath: String
    private var boxDataFetcher: PCMP4BoxDataFetcher?
    
    init(filePath: String) {
        self.filePath = filePath
        self.fileHandle = FileHandle(forReadingAtPath: filePath)
        
        // 创建 box data fetcher
        weak var weakSelf = self
        self.boxDataFetcher = { box in
            return weakSelf?.readDataForBox(box)
        }
    }
    
    deinit {
        fileHandle?.closeFile()
    }
    
    /// 解析 MP4 文件
    func parse() {
        guard let fileHandle = fileHandle else { 
            PCVAPError(kPCVAPModuleCommon, "parse error: fileHandle is nil")
            return 
        }
        
        // 获取文件大小
        fileHandle.seekToEndOfFile()
        let fileSize = fileHandle.offsetInFile
        fileHandle.seek(toFileOffset: 0)
        
        PCVAPInfo(kPCVAPModuleCommon, "开始解析 MP4 文件，文件大小: \(fileSize) bytes")
        
        // 创建根 Box
        rootBox = PCMP4BoxFactory.createBoxForType(.unknown, startIndexInBytes: 0, length: UInt64(fileSize))
        
        // 广度优先遍历队列
        var bfsQueue: [PCMP4Box] = [rootBox!]
        var boxCount = 0
        
        // 长度包含类型码长度+本身长度
        while let calBox = bfsQueue.first {
            bfsQueue.removeFirst()
            boxCount += 1
            
            // 每解析 100 个 box 打印一次进度
            if boxCount % 100 == 0 {
                PCVAPInfo(kPCVAPModuleCommon, "MP4 解析进度: 已解析 \(boxCount) 个 box，队列中还有 \(bfsQueue.count) 个")
            }
            
            // 长度限制检查
            if calBox.length <= UInt64(2 * (kQGBoxSizeLengthInBytes + kQGBoxTypeLengthInBytes)) {
                continue
            }
            
            var offset: UInt64 = 0
            var length: UInt64 = 0
            var type: PCMP4BoxType = .unknown
            
            // 第一个子box
            offset = calBox.superBox != nil ? (calBox.startIndexInBytes + UInt64(kQGBoxSizeLengthInBytes + kQGBoxTypeLengthInBytes)) : 0
            
            // 特殊处理
            if shouldResetOffset(calBox.type) {
                calibrateOffset(&offset, boxType: calBox.type)
            }
            
            // 解析子box
            while true {
                // 判断是否会越界
                if (offset + UInt64(kQGBoxSizeLengthInBytes + kQGBoxTypeLengthInBytes)) > (calBox.startIndexInBytes + calBox.length) {
                    break
                }
                
                guard readBoxTypeAndLength(offset, type: &type, length: &length) else {
                    break
                }
                
                if (offset + length) > (calBox.startIndexInBytes + calBox.length) {
                    // 到达父 box 末尾或不是 box
                    break
                }
                
                if !PCMP4BoxFactory.isTypeValueValid(type) && (offset == (calBox.startIndexInBytes + UInt64(kQGBoxSizeLengthInBytes + kQGBoxTypeLengthInBytes))) {
                    // 目前的策略是：如果第一个子box类型无效，则停止解析
                    break
                }
                
                let subBox = PCMP4BoxFactory.createBoxForType(type, startIndexInBytes: offset, length: length)
                subBox.superBox = calBox
                if calBox.subBoxes.isEmpty {
                    calBox.subBoxes = []
                }
                calBox.subBoxes.append(subBox)
                
                // 进入广度优先遍历队列
                bfsQueue.append(subBox)
                didParseBox(subBox)
                
                // 继续兄弟box
                offset += length
            }
        }
        
        PCVAPInfo(kPCVAPModuleCommon, "MP4 文件解析完成，共解析 \(boxCount) 个 box")
        didFinisheParseFile()
    }
    
    /// 读取 Box 类型和长度
    private func readBoxTypeAndLength(_ offset: UInt64, type: inout PCMP4BoxType, length: inout UInt64) -> Bool {
        guard let fileHandle = fileHandle else { return false }
        
        fileHandle.seek(toFileOffset: offset)
        guard let data = try? fileHandle.read(upToCount: kQGBoxSizeLengthInBytes + kQGBoxTypeLengthInBytes),
              data.count >= kQGBoxSizeLengthInBytes + kQGBoxTypeLengthInBytes else {
            PCVAPError(kPCVAPModuleCommon, "read box length and type error")
            return false
        }
        
        // 修复：withUnsafeBytes 闭包内的指针只在闭包内有效，需要在闭包内完成所有操作
        var lengthValue: UInt64 = 0
        var typeValue: UInt64 = 0
        data.withUnsafeBytes { bytes in
            let ptr = bytes.baseAddress!.assumingMemoryBound(to: UInt8.self)
            lengthValue = UInt64(readValue(ptr, length: kQGBoxSizeLengthInBytes))
            typeValue = readValue(ptr.advanced(by: kQGBoxSizeLengthInBytes), length: kQGBoxTypeLengthInBytes)
        }
        length = lengthValue
        type = PCMP4BoxType(rawValue: UInt32(typeValue)) ?? .unknown
        
        // 处理大尺寸标志
        if length == UInt64(kQGBoxLargeSizeFlagLengthInBytes) {
            let newOffset = offset + UInt64(kQGBoxSizeLengthInBytes + kQGBoxTypeLengthInBytes)
            fileHandle.seek(toFileOffset: newOffset)
            guard let largeSizeData = try? fileHandle.read(upToCount: kQGBoxLargeSizeLengthInBytes),
                  largeSizeData.count >= kQGBoxLargeSizeLengthInBytes else {
                PCVAPError(kPCVAPModuleCommon, "read box length and type error")
                return false
            }
            // 修复：在闭包内完成读取操作
            var largeLengthValue: UInt64 = 0
            largeSizeData.withUnsafeBytes { bytes in
                let ptr = bytes.baseAddress!.assumingMemoryBound(to: UInt8.self)
                largeLengthValue = UInt64(readValue(ptr, length: kQGBoxLargeSizeLengthInBytes))
            }
            length = largeLengthValue
            if length == 0 {
                PCVAPError(kPCVAPModuleCommon, "read box length is 0")
                return false
            }
        }
        
        return true
    }
    
    /// 判断是否需要重置偏移量
    private func shouldResetOffset(_ type: PCMP4BoxType) -> Bool {
        return type == .stsd || type == .avc1 || type == .hvc1
    }
    
    /// 校准偏移量
    private func calibrateOffset(_ offset: inout UInt64, boxType: PCMP4BoxType) {
        switch boxType {
        case .stsd:
            offset += 8
        case .avc1, .hvc1:
            let offsetValue = 24 + 2 + 2 + 14 + 32 + 4
            offset += UInt64(offsetValue)
        default:
            break
        }
    }
    
    /// 读取 Box 数据
    func readDataForBox(_ box: PCMP4Box?) -> Data? {
        guard let box = box, let fileHandle = fileHandle else { return nil }
        
        fileHandle.seek(toFileOffset: box.startIndexInBytes)
        return try? fileHandle.read(upToCount: Int(box.length))
    }
    
    /// 读取值（大端序）
    func readValue(_ bytes: UnsafePointer<UInt8>, length: Int) -> UInt64 {
        var value: UInt64 = 0
        for i in 0..<length {
            value += UInt64(bytes[i] & 0xff) << ((length - i - 1) * 8)
        }
//  打印日志也额米有问题的，但是值为什么都是0 =呢？
        VAPDebug(kPCVAPModuleCommon, "readValue length:\(length) value:\(value)")
        return value
    }
    
    // MARK: - Private Methods
    
    /// Box 解析完成
    private func didParseBox(_ box: PCMP4Box) {
        // 调用 box 的解析回调
        if let boxDataFetcher = boxDataFetcher {
            box.boxDidParsed(boxDataFetcher)
        }
        
        // 通知 delegate
        delegate?.didParsePCMP4Box(box, parser: self)
    }
    
    /// 文件解析完成
    private func didFinisheParseFile() {
        delegate?.MP4FileDidFinishParse(self)
    }
}

