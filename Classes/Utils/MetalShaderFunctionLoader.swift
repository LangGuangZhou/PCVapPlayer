//
//  MetalShaderFunctionLoader.swift
//  QGVAPlayer
//
//  Created by converting from Objective-C
//  Copyright © 2024. All rights reserved.
//

import Foundation
import Metal
import MetalKit

/// Metal 着色器函数加载器
class MetalShaderFunctionLoader {
    private var alreadyLoadDefaultLibrary = false
    private var alreadyLoadHWDLibrary = false
    
    private let device: MTLDevice
    private var defaultLibrary: MTLLibrary?
    private var hwdLibrary: MTLLibrary?
    
    init(device: MTLDevice) {
        self.device = device
    }
    
    /// 加载函数
    /// - Parameter funcName: 函数名称
    /// - Returns: Metal 函数
    func loadFunction(withName funcName: String) -> MTLFunction? {
        loadDefaultLibraryIfNeed()
        
        var program = defaultLibrary?.makeFunction(name: funcName)
        
        // 没有找到 defaultLibrary 文件 || defaultLibrary 中不包含对应的 function
        if program == nil {
            loadHWDLibraryIfNeed()
            program = hwdLibrary?.makeFunction(name: funcName)
        }
        
        return program
    }
    
    /// 加载默认库（如果需要）
    private func loadDefaultLibraryIfNeed() {
        if defaultLibrary != nil || alreadyLoadDefaultLibrary {
            return
        }
        
        let bundle = Bundle(for: type(of: self))
        guard let metalLibPath = bundle.path(forResource: "default", ofType: "metallib"),
              !metalLibPath.isEmpty else {
            return
        }
        
        do {
            let libraryURL = URL(fileURLWithPath: metalLibPath)
            let library = try device.makeLibrary(URL: libraryURL)
            defaultLibrary = library
            alreadyLoadDefaultLibrary = true
        } catch {
            PCVAPError(kPCVAPModuleCommon, "loadDefaultLibrary error!:\(error)")
        }
    }
    
    /// 加载 HWD 库（如果需要）
    private func loadHWDLibraryIfNeed() {
        if hwdLibrary != nil || alreadyLoadHWDLibrary {
            return
        }
        
        // 组合 shader 源字符串（imports + type defines + source string）
        let sourceString = kPCHWDMetalShaderSourceImports + kPCHWDMetalShaderTypeDefines + kPCHWDMetalShaderSourceString
        
        do {
            let library = try device.makeLibrary(source: sourceString, options: nil)
            hwdLibrary = library
            alreadyLoadHWDLibrary = true
        } catch {
            PCVAPError(kPCVAPModuleCommon, "loadHWDLibrary error!:\(error)")
        }
    }
}

