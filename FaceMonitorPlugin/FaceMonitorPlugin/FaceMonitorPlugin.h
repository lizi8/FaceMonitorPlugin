//
//  FaceMonitorPlugin.h
//  FaceMonitorPlugin
//
//  Created by lfl on 2025/7/25.
//

//#import <Foundation/Foundation.h>
//
////! Project version number for FaceMonitorPlugin.
//FOUNDATION_EXPORT double FaceMonitorPluginVersionNumber;
//
////! Project version string for FaceMonitorPlugin.
//FOUNDATION_EXPORT const unsigned char FaceMonitorPluginVersionString[];

// In this header, you should import all the public headers of your framework using statements like #import <FaceMonitorPlugin/PublicHeader.h>


// FaceMonitorPlugin.m
#import <AVFoundation/AVFoundation.h>
#import <KiwiFaceSDK/KiwiFaceDetector.h>

@implementation FaceMonitorPlugin {
    AVCaptureSession *_session;
    KiwiFaceDetector *_detector;
}

// 启动摄像头
UNI_EXPORT_METHOD(@selector(startMonitoring:))
- (void)startMonitoring:(UniModuleKeepAliveCallback)callback {
    _session = [[AVCaptureSession alloc] init];
    AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    // 配置输入输出流（代码详见[11](@ref)）
    _detector = [[KiwiFaceDetector alloc] init];
    [_detector startDetectionWithSession:_session completion:^(NSArray<Face *> *faces) {
        if (faces.count > 0) {
            // 检测到人脸时触发随机拍照
            [self takeSnapshot];
        }
    }];
}

- (void)takeSnapshot {
    // 随机数生成（如每5-15秒拍一次）
    int delay = arc4random_uniform(10) + 5;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, delay * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        AVCaptureConnection *connection = [_videoOutput connectionWithMediaType:AVMediaTypeVideo];
        [_photoOutput capturePhotoWithSettings:[AVCapturePhotoSettings photoSettings] delegate:self];
    });
}

// 保存图片至临时目录
- (void)captureOutput:(AVCapturePhotoOutput *)output didFinishProcessingPhoto:(AVCapturePhoto *)photo error:(nullable NSError *)error {
    NSData *imageData = [photo fileDataRepresentation];
    NSString *tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"snapshot.jpg"];
    [imageData writeToFile:tempPath atomically:YES];
    // 通知UniApp层上传图片
    [self notifyUniApp:@{@"imagePath": tempPath}];
}@end
