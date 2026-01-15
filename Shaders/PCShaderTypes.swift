//
//  PCShaderTypes.swift
//  PCVapPlayer
//
//  Created by converting from Objective-C
//  Copyright © 2024. All rights reserved.
//

import simd
import Metal

// MARK: - Vertex Structures

struct PCHWDVertex {
    var position: SIMD4<Float>
    var textureColorCoordinate: SIMD2<Float>
    var textureAlphaCoordinate: SIMD2<Float>
}

struct PCVAPVertex {
    var position: SIMD4<Float>
    var textureColorCoordinate: SIMD2<Float>
    var textureAlphaCoordinate: SIMD2<Float>
    var textureMaskCoordinate: SIMD2<Float>
}

struct PCHWDAttachmentVertex {
    var position: SIMD4<Float>
    var sourceTextureCoordinate: SIMD2<Float>
    var maskTextureCoordinate: SIMD2<Float>
}

// MARK: - Parameter Structures

struct PCColorParameters {
    var matrix: matrix_float3x3
    var offset: SIMD2<Float>
}

struct PCMaskParameters {
    var weightMatrix: matrix_float3x3
    var coreSize: Int32
    var texelOffset: Float
}

struct PCVapAttachmentFragmentParameter {
    var needOriginRGB: Int32
    var fillColor: SIMD4<Float>
}

// MARK: - Texture Index

enum PCYUVFragmentTextureIndex: Int {
    case luma = 0
    case chroma = 1
    case attachmentStart = 2
}

