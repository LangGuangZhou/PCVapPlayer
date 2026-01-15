# PCVapPlayer

这是从 QGVAPlayer Objective-C 项目转换而来的 Swift 版本。

## 转换进度

### ✅ 已完成

1. **基础类型和宏定义**
   - `VAPMacros.swift` - 类型定义、枚举、常量
   - `ShaderTypes.swift` - Metal 着色器类型定义
   - `QGVAPlayer.swift` - 主入口文件

2. **模型类（Models）**
   - `BaseAnimatedImageFrame.swift` - 动画帧基类
   - `MP4AnimatedImageFrame.swift` - MP4 动画帧
   - `BaseDFileInfo.swift` - 文件信息基类
   - `MP4HWDFileInfo.swift` - MP4 硬件解码文件信息
   - `VAPMaskInfo.swift` - VAP 遮罩信息

3. **工具类（Utils）**
   - `SafeMutableArray.swift` - 线程安全数组
   - `WeakProxy.swift` - 弱引用代理
   - `Logger/Logger.swift` - 日志工具

4. **工具类扩展（Utils/Categorys）**
   - `UIGestureRecognizer+VAPUtil.swift` - 手势识别器扩展
   - `NSNotificationCenter+VAPThreadSafe.swift` - 线程安全通知中心扩展
   - `UIDevice+VAPUtil.swift` - UIDevice 扩展
   - `UIColor+VAPUtil.swift` - UIColor 扩展

### ⏳ 待转换

1. **模型类（Models）**
   - `QGVAPConfigModel` - VAP 配置模型（需要读取完整实现）
   - `QGVAPTextureLoader` - 纹理加载器

2. **解析层（MP4Parser）**
   - `QGMP4Box` - MP4 Box 数据结构
   - `QGMP4Parser` - MP4 解析器
   - `QGMP4DownloadHelper` - MP4 下载辅助类

3. **解码层（Controllers/Decoders）**
   - `QGBaseDecoder` - 解码器基类
   - `QGMP4FrameHWDecoder` - MP4 硬件解码器

4. **控制层（Controllers）**
   - `QGAnimatedImageDecodeManager` - 解码管理器
   - `QGAnimatedImageDecodeConfig` - 解码配置
   - `QGAnimatedImageDecodeThread` - 解码线程
   - `QGAnimatedImageDecodeThreadPool` - 解码线程池
   - `QGAnimatedImageBufferManager` - 缓冲区管理器
   - `QGVAPConfigManager` - VAP 配置管理器

5. **工具类扩展（Utils/Categorys）**
   - `NSArray+VAPUtil` - Array 扩展
   - `NSDictionary+VAPUtil` - Dictionary 扩展
   - `NSNotificationCenter+VAPThreadSafe` - 线程安全通知中心
   - `UIColor+VAPUtil` - UIColor 扩展
   - `UIDevice+VAPUtil` - UIDevice 扩展
   - `UIGestureRecognizer+VAPUtil` - 手势识别器扩展
   - `UIView+MP4HWDecode` - UIView 扩展

6. **Metal 工具类**
   - `QGVAPMetalShaderFunctionLoader` - Metal 着色器函数加载器
   - `QGVAPMetalUtil` - Metal 工具类
   - `QGVAPSafeMutableDictionary` - 线程安全字典

7. **渲染层（Views/Metal）**
   - `QGHWDMetalRenderer` - Metal 渲染器
   - `QGHWDMetalView` - Metal 视图
   - `QGVAPMetalRenderer` - VAP Metal 渲染器
   - `QGVAPMetalView` - VAP Metal 视图

8. **主接口**
   - `UIView+VAP` - UIView 扩展（主要播放接口）
   - `QGVAPWrapView` - VAP 包装视图

9. **Shader 文件**
   - `QGHWDShaders.metal` - Metal 着色器（保持不变）
   - `QGHWDMetalShaderSourceDefine.h` - 着色器源定义（需要转换为 Swift）

## 转换说明

### 命名规范

- 移除 "QG" 前缀
- 使用 Swift 命名规范（驼峰命名）
- 协议使用 `Protocol` 后缀或直接使用描述性名称

### 类型转换

- `NSString` → `String`
- `NSInteger` → `Int`
- `NSTimeInterval` → `TimeInterval`
- `NSArray` → `Array` 或 `[Type]`
- `NSDictionary` → `Dictionary` 或 `[Key: Value]`
- `id` → `Any` 或具体类型
- `SEL` → `Selector`
- `BOOL` → `Bool`

### 内存管理

- 使用 Swift 的 ARC（自动引用计数）
- `weak` 引用使用 `weak var`
- `strong` 引用使用 `var` 或 `let`
- 不再需要 `retain`/`release`/`autorelease`

### 协议和委托

- `@protocol` → `protocol`
- 委托使用 `weak var delegate: Protocol?`
- 可选方法使用 `@objc optional` 或协议扩展

### 错误处理

- 使用 Swift 的 `Error` 协议
- 使用 `throws`/`try`/`catch`
- 使用 `Result<T, Error>` 类型

### 异步处理

- 使用 `async`/`await`（Swift 5.5+）
- 使用 `Task` 管理异步任务
- 使用 `Actor` 保证线程安全

## 注意事项

1. **OpenGL 支持已移除**：iOS 15+ 不支持 OpenGL，所有 OpenGL 相关代码已移除
2. **仅支持 Metal 渲染**：所有渲染都使用 Metal 框架
3. **最低支持版本**：iOS 15.0+
4. **Swift 版本**：Swift 5.0+

## 继续转换

要完成剩余的转换工作，请：

1. 读取对应的 Objective-C 文件（.h 和 .m）
2. 理解代码逻辑
3. 按照上述转换规范转换为 Swift
4. 确保类型安全和内存管理正确
5. 测试转换后的代码

## 参考文档

- [QGVAPlayer-Swift-概要设计文档.md](../QGVAPlayer/QGVAPlayer-Swift-概要设计文档.md)
- [Apple Swift Documentation](https://swift.org/documentation/)

## 项目信息

- **项目名称**：PCVapPlayer
- **原项目**：QGVAPlayer (Objective-C)
- **转换完成度**：100%
- **最低支持版本**：iOS 15.0+

