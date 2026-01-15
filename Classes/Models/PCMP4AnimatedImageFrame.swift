//
//  PCMP4AnimatedImageFrame.swift
//  PCVapPlayer
//
//  Created by converting from Objective-C
//  Copyright © 2024. All rights reserved.
//

import Foundation
import CoreVideo

/// MP4 动画帧
public class PCMP4AnimatedImageFrame: PCBaseAnimatedImageFrameImpl {
    public var pixelBuffer: CVPixelBuffer?
    public var defaultFps: Int = 0
    
    deinit {
        // Core Video 对象现在由 ARC 自动管理，不需要手动释放
    }
}

