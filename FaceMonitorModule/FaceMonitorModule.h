#import <Foundation/Foundation.h>
#import "DCUniModule.h"
#import <AVFoundation/AVFoundation.h>
#import <Vision/Vision.h>

NS_ASSUME_NONNULL_BEGIN

@interface FaceMonitorModule : DCUniModule <AVCaptureVideoDataOutputSampleBufferDelegate>

// 暴露给UniApp JS端调用的方法
// 只声明方法，不使用UNI_EXPORT_METHOD宏
- (void)startMonitoring:(NSDictionary *)options callback:(UniModuleKeepAliveCallback)callback;
- (void)stopMonitoring;

@end

NS_ASSUME_NONNULL_END
