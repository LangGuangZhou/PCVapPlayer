//
//  PCMP4HWDFileInfo.swift
//  PCVapPlayer
//
//  Created by converting from Objective-C
//  Copyright © 2024. All rights reserved.
//

import Foundation

/// MP4 硬件解码文件信息
class PCMP4HWDFileInfo: PCBaseDFileInfoImpl {
    var mp4Parser: PCMP4ParserProxy?
    
    init(filePath: String) {
        super.init()
        self.filePath = filePath
        self.mp4Parser = PCMP4ParserProxy(filePath: filePath)
    }
}

