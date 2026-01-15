//
//  PCMP4DownloadHelper.swift
//  PCVapPlayer
//
//  Created by converting from Objective-C
//  Copyright © 2024. All rights reserved.
//

import Foundation
import CommonCrypto

/// MP4 下载完成回调
typealias PCMP4CompletionBlock = (String?) -> Void

/// MP4 下载失败回调
typealias PCMP4FailureBlock = (Error?) -> Void

/// MP4 下载辅助类
class PCMP4DownloadHelper {
    private static var parseQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 8
        return queue
    }()
    
    private static var completionMap: [String: [PCMP4CompletionBlock]] = [:]
    private static var failureMap: [String: [PCMP4FailureBlock]] = [:]
    private static let mapQueue = DispatchQueue(label: "com.qgame.vap.download.map", attributes: .concurrent)
    
    /// 下载 MP4 文件
    /// - Parameters:
    ///   - url: 文件 URL
    ///   - completionBlock: 完成回调
    ///   - failureBlock: 失败回调
    func download(with url: URL, completionBlock: @escaping PCMP4CompletionBlock, failureBlock: PCMP4FailureBlock?) {
        let urlRequest = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 20.0)
        let cacheKey = cacheKey(for: url)
        let filepath = cacheFilepath(for: url)
        
        // 检查文件是否已存在
        if FileManager.default.fileExists(atPath: filepath) {
            PCVAPInfo(kPCVAPModuleCommon, "mp4 load from file \(filepath)")
            OperationQueue.main.addOperation {
                completionBlock(filepath)
            }
            return
        }
        
        // 保存失败回调
        if let failureBlock = failureBlock {
            PCMP4DownloadHelper.mapQueue.async(flags: .barrier) {
                if PCMP4DownloadHelper.failureMap[cacheKey] != nil {
                    PCMP4DownloadHelper.failureMap[cacheKey]?.append(failureBlock)
                } else {
                    PCMP4DownloadHelper.failureMap[cacheKey] = [failureBlock]
                }
            }
        }
        
        // 保存成功回调
        var shouldDownload = false
        PCMP4DownloadHelper.mapQueue.async(flags: .barrier) {
            if PCMP4DownloadHelper.completionMap[cacheKey] != nil {
                PCMP4DownloadHelper.completionMap[cacheKey]?.append(completionBlock)
            } else {
                PCMP4DownloadHelper.completionMap[cacheKey] = [completionBlock]
                shouldDownload = true
            }
        }
        
        guard shouldDownload else { return }
        
        // 下载
        PCVAPInfo(kPCVAPModuleCommon, "mp4 load from net download begin \(urlRequest.url?.absoluteString ?? "")")
        let startTime = CACurrentMediaTime()
        
        URLSession.shared.downloadTask(with: urlRequest) { [weak self] location, response, error in
            guard let self = self else { return }
            
            if let error = error {
                PCVAPError(kPCVAPModuleCommon, "mp4 load from net ❌ \(urlRequest.url?.absoluteString ?? "") error：\(error.localizedDescription)")
                self.executeCacheFailure(cacheKey: cacheKey, error: error)
                return
            }
            
            guard let location = location else {
                let downloadError = NSError(domain: "PCMP4DownloadHelper", code: -1, userInfo: [NSLocalizedDescriptionKey: "Download location is nil"])
                self.executeCacheFailure(cacheKey: cacheKey, error: downloadError)
                return
            }
            
            let cacheDir = self.cacheDirectory(for: cacheKey)
            var fileError: NSError?
            
            // 创建缓存目录
            if !FileManager.default.fileExists(atPath: cacheDir) {
                try? FileManager.default.createDirectory(atPath: cacheDir, withIntermediateDirectories: true, attributes: nil)
            }
            
            // 移动文件（should move item from location before URLSession completionHandler return）
            do {
                try FileManager.default.moveItem(at: location, to: URL(fileURLWithPath: filepath))
            } catch {
                fileError = error as NSError
            }
            
            if let fileError = fileError {
                PCVAPError(kPCVAPModuleCommon, "mp4 load from net ❌ \(urlRequest.url?.absoluteString ?? "") error：\(fileError.localizedDescription)")
                self.clearCache(cacheKey: cacheKey)
                self.executeCacheFailure(cacheKey: cacheKey, error: fileError)
                return
            }
            
            let consumeTime = CACurrentMediaTime() - startTime
            PCVAPInfo(kPCVAPModuleCommon, "mp4 load from net \(urlRequest.url?.absoluteString ?? "") consume time：\(consumeTime)")
            self.executeCacheCompletion(cacheKey: cacheKey, filepath: filepath)
        }.resume()
    }
    
    // MARK: - Private Methods
    
    /// 执行缓存完成回调
    private func executeCacheCompletion(cacheKey: String, filepath: String) {
        PCMP4DownloadHelper.mapQueue.async(flags: .barrier) {
            guard let blocks = PCMP4DownloadHelper.completionMap[cacheKey] else { return }
            PCMP4DownloadHelper.completionMap.removeValue(forKey: cacheKey)
            
            OperationQueue.main.addOperation {
                blocks.forEach { $0(filepath) }
            }
        }
    }
    
    /// 执行缓存失败回调
    private func executeCacheFailure(cacheKey: String, error: Error) {
        PCMP4DownloadHelper.mapQueue.async(flags: .barrier) {
            guard let blocks = PCMP4DownloadHelper.failureMap[cacheKey] else { return }
            PCMP4DownloadHelper.failureMap.removeValue(forKey: cacheKey)
            
            OperationQueue.main.addOperation {
                blocks.forEach { $0(error) }
            }
        }
    }
    
    /// 获取缓存目录
    private func cacheDirectory(for cacheKey: String) -> String {
        let cacheDir = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true).first ?? ""
        return (cacheDir as NSString).appendingPathComponent("mp4/\(cacheKey)")
    }
    
    /// 获取缓存文件路径
    private func cacheFilepath(for url: URL) -> String {
        let suffix = "/\(url.lastPathComponent)"
        return cacheDirectory(for: cacheKey(for: url)) + suffix
    }
    
    /// 获取缓存键（URL 的 MD5）
    private func cacheKey(for url: URL) -> String {
        return MD5String(url.absoluteString)
    }
    
    /// 清除缓存
    private func clearCache(cacheKey: String) {
        let cacheDir = cacheDirectory(for: cacheKey)
        try? FileManager.default.removeItem(atPath: cacheDir)
        PCVAPInfo(kPCVAPModuleCommon, "mp4 load clear file \(cacheKey)")
    }
    
    /// MD5 字符串
    private func MD5String(_ str: String) -> String {
        guard !str.isEmpty else { return "" }
        
        guard let cstr = str.cString(using: .utf8) else { return "" }
        var result = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        CC_MD5(cstr, CC_LONG(strlen(cstr)), &result)
        
        return result.map { String(format: "%02X", $0) }.joined()
    }
}

