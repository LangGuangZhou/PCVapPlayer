//
//  PCShaderSourceDefine.swift
//  PCVapPlayer
//
//  Created by converting from Objective-C
//  Copyright © 2024. All rights reserved.
//

import Foundation

/*
 !!!!!!!!!important!!!!!!!!!
 ！！所有.metal文件更新，都需要同步到这个文件中！！
 ！！本文件内着色器代码作为兜底逻辑，当无法找到预编译着色器时使用本文件定义的着色器字符串进行编译！
 !!!!!!!!!!!!!!!!!!!!!!!!!!
 */

// The source may only import the Metal standard library. There is no search path to find other functions.

/// 头文件引入
let kPCHWDMetalShaderSourceImports = """
#include <metal_stdlib>
#import <simd/simd.h>

"""

/// 类型定义
let kPCHWDMetalShaderTypeDefines = """
typedef struct {
    packed_float4 position;
    packed_float2 textureColorCoordinate;
    packed_float2 textureAlphaCoordinate;
} PCHWDVertex;

typedef struct {
    packed_float4 position;
    packed_float2 textureColorCoordinate;
    packed_float2 textureAlphaCoordinate;
    packed_float2 textureMaskCoordinate;
} PCVAPVertex;

struct PCColorParameters {
    matrix_float3x3 matrix;
    packed_float2 offset;
};

struct PCMaskParameters {
    matrix_float3x3 weightMatrix;
    int coreSize;
    float texelOffset;
};

typedef struct {
    packed_float4 position;
    packed_float2 sourceTextureCoordinate;
    packed_float2 maskTextureCoordinate;
} PCHWDAttachmentVertex;

struct PCVapAttachmentFragmentParameter {
    int needOriginRGB;
    packed_float4 fillColor;
};

"""

/// 着色器代码
let kPCHWDMetalShaderSourceString = """
//PCHWDShaders.metal
using namespace metal;
typedef struct {
    float4 clipSpacePostion [[ position ]];
    float2 textureColorCoordinate;
    float2 textureAlphaCoordinate;
} PCHWDRasterizerData;

typedef struct {
    float4 clipSpacePostion [[ position ]];
    float2 textureColorCoordinate;
    float2 textureAlphaCoordinate;
    float2 textureMaskCoordinate;
} PCVAPRasterizerData;

typedef struct {
    float4 position [[ position ]];
    float2 sourceTextureCoordinate;
    float2 maskTextureCoordinate;
} PCVAPAttachmentRasterizerData;

float3 RGBColorFromYuvTextures(sampler textureSampler, float2 coordinate, texture2d<float> texture_luma, texture2d<float> texture_chroma, matrix_float3x3 rotationMatrix, float2 offset) {
    float3 color;
    color.x = texture_luma.sample(textureSampler, coordinate).r;
    color.yz = texture_chroma.sample(textureSampler, coordinate).rg - offset;
    return float3(rotationMatrix * color);
}

float4 RGBAColor(sampler textureSampler, float2 colorCoordinate, float2 alphaCoordinate, texture2d<float> lumaTexture, texture2d<float> chromaTexture, constant PCColorParameters *colorParameters) {
    matrix_float3x3 rotationMatrix = colorParameters[0].matrix;
    float2 offset = colorParameters[0].offset;
    float3 color = RGBColorFromYuvTextures(textureSampler, colorCoordinate, lumaTexture, chromaTexture, rotationMatrix, offset);
    float3 alpha = RGBColorFromYuvTextures(textureSampler, alphaCoordinate, lumaTexture, chromaTexture, rotationMatrix, offset);
    return float4(color, alpha.r);
}

vertex PCHWDRasterizerData hwd_vertexShader(uint vertexID [[ vertex_id ]], constant PCHWDVertex *vertexArray [[ buffer(0) ]]) {
    PCHWDRasterizerData out;
    out.clipSpacePostion = vertexArray[vertexID].position;
    out.textureColorCoordinate = vertexArray[vertexID].textureColorCoordinate;
    out.textureAlphaCoordinate = vertexArray[vertexID].textureAlphaCoordinate;
    return out;
}

fragment float4 hwd_yuvFragmentShader(PCHWDRasterizerData input [[ stage_in ]],
                                      texture2d<float>  lumaTexture [[ texture(0) ]],
                                      texture2d<float>  chromaTexture [[ texture(1) ]],
                                      constant PCColorParameters *colorParameters [[ buffer(0) ]]) {
    //signifies that an expression may be computed at compile-time rather than runtime
    constexpr sampler textureSampler (mag_filter::linear, min_filter::linear);
    return RGBAColor(textureSampler, input.textureColorCoordinate, input.textureAlphaCoordinate, lumaTexture, chromaTexture, colorParameters);
}

vertex PCVAPRasterizerData vap_vertexShader(uint vertexID [[ vertex_id ]], constant PCVAPVertex *vertexArray [[ buffer(0) ]]) {
    PCVAPRasterizerData out;
    out.clipSpacePostion = vertexArray[vertexID].position;
    out.textureColorCoordinate = vertexArray[vertexID].textureColorCoordinate;
    out.textureAlphaCoordinate = vertexArray[vertexID].textureAlphaCoordinate;
    out.textureMaskCoordinate = vertexArray[vertexID].textureMaskCoordinate;
    return out;
}

fragment float4 vap_yuvFragmentShader(PCVAPRasterizerData input [[ stage_in ]],
                                      texture2d<float>  lumaTexture [[ texture(0) ]],
                                      texture2d<float>  chromaTexture [[ texture(1) ]],
                                      constant PCColorParameters *colorParameters [[ buffer(0) ]]) {
    //signifies that an expression may be computed at compile-time rather than runtime
    constexpr sampler textureSampler (mag_filter::linear, min_filter::linear);
    return RGBAColor(textureSampler, input.textureColorCoordinate, input.textureAlphaCoordinate, lumaTexture, chromaTexture, colorParameters);
}

fragment float4 vap_maskFragmentShader(PCVAPRasterizerData input [[ stage_in ]],
                                      texture2d<float>  lumaTexture [[ texture(0) ]],
                                      texture2d<float>  chromaTexture [[ texture(1) ]],
                                      texture2d<float>  maskTexture [[ texture(2) ]],
                                      constant PCColorParameters *colorParameters [[ buffer(0) ]]) {
    //signifies that an expression may be computed at compile-time rather than runtime
    constexpr sampler textureSampler (mag_filter::linear, min_filter::linear);
    float4 originColor = RGBAColor(textureSampler, input.textureColorCoordinate, input.textureAlphaCoordinate, lumaTexture, chromaTexture, colorParameters);
    float4 maskColor = maskTexture.sample(textureSampler, input.textureMaskCoordinate);
    float needMask = maskColor.r * 255;
    return float4(originColor.rgb, (1 - needMask) * originColor.a);
}

fragment float4 vap_maskBlurFragmentShader(PCVAPRasterizerData input [[ stage_in ]],
                                           texture2d<float>  lumaTexture [[ texture(0) ]],
                                           texture2d<float>  chromaTexture [[ texture(1) ]],
                                           texture2d<float>  maskTexture [[ texture(2) ]],
                                           constant PCColorParameters *colorParameters [[ buffer(0) ]],
                                           constant PCMaskParameters *maskParameters [[ buffer(1) ]]) {
    //signifies that an expression may be computed at compile-time rather than runtime
    constexpr sampler textureSampler (mag_filter::linear, min_filter::linear);
    float4 originColor = RGBAColor(textureSampler, input.textureColorCoordinate, input.textureAlphaCoordinate, lumaTexture, chromaTexture, colorParameters);
    
    int uniform = 255;
    float3x3 weightMatrix = maskParameters[0].weightMatrix;
    int coreSize = maskParameters[0].coreSize;
    float texelOffset = maskParameters[0].texelOffset;
    float alphaResult = 0;
    
    // 循环9次可以写成for循环
    for (int y = 0; y < coreSize; y++) {
        for (int x = 0; x < coreSize; x++) {
            float2 nearMaskColor = float2(input.textureMaskCoordinate.x +  (-1.0 + float(x)) * texelOffset, input.textureMaskCoordinate.y + (-1.0 + float(y)) * texelOffset);
            alphaResult += maskTexture.sample(textureSampler, nearMaskColor).r * uniform * weightMatrix[x][y];
        }
    }
    
    int needOrigin = step(alphaResult, 0.01) + step(originColor.a, 0.01);
    return float4(originColor.rgb, needOrigin * originColor.a + (1 - needOrigin) * (1 - alphaResult));
}

vertex PCVAPAttachmentRasterizerData vapAttachment_vertexShader(uint vertexID [[ vertex_id ]], constant PCHWDAttachmentVertex *vertexArray [[ buffer(0) ]]) {
    PCVAPAttachmentRasterizerData out;
    out.position = vertexArray[vertexID].position;
    out.sourceTextureCoordinate = vertexArray[vertexID].sourceTextureCoordinate;
    out.maskTextureCoordinate =  vertexArray[vertexID].maskTextureCoordinate;
    return out;
}

fragment float4 vapAttachment_FragmentShader(PCVAPAttachmentRasterizerData input [[ stage_in ]],
                                             texture2d<float>  lumaTexture [[ texture(0) ]],
                                             texture2d<float>  chromaTexture [[ texture(1) ]],
                                             texture2d<float>  sourceTexture [[ texture(2) ]],
                                             constant PCColorParameters *colorParameters [[ buffer(0) ]],
                                             constant PCVapAttachmentFragmentParameter *fillParams [[ buffer(1) ]]) {
    
    constexpr sampler textureSampler (mag_filter::linear, min_filter::linear);
    matrix_float3x3 rotationMatrix = colorParameters[0].matrix;
    float2 offset = colorParameters[0].offset;
    float3 mask = RGBColorFromYuvTextures(textureSampler, input.maskTextureCoordinate, lumaTexture, chromaTexture, rotationMatrix, offset);
    float4 source = sourceTexture.sample(textureSampler, input.sourceTextureCoordinate);
    return float4(source.rgb, source.a * mask.r);
}

"""

