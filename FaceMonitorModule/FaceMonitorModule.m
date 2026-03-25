#import "FaceMonitorModule.h"

@interface FaceMonitorModule ()

@property (nonatomic, strong) AVCaptureSession *captureSession;
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *previewLayer;
@property (nonatomic, strong) dispatch_queue_t sessionQueue;
@property (nonatomic, strong) VNSequenceRequestHandler *visionSequenceHandler;
@property (nonatomic, strong) CAShapeLayer *faceLayer;
@property (nonatomic, assign) BOOL isFaceInView;
@property (nonatomic, strong) NSTimer *randomCaptureTimer;
@property (nonatomic, strong) AVCapturePhotoOutput *photoOutput;
@property (nonatomic, copy) UniModuleKeepAliveCallback statusCallback;


// 添加缺失的属性
@property (nonatomic, strong) AVCaptureVideoDataOutput *videoDataOutput; // 添加这一行


@end

@implementation FaceMonitorModule

#pragma mark - Lifecycle
- (void)dealloc {
    [self stopMonitoring];
}

#pragma mark - Exported Methods
- (void)startMonitoring:(NSDictionary *)options callback:(UniModuleKeepAliveCallback)callback {
    self.statusCallback = callback;
    NSLog(@"[FaceMonitor] Starting monitoring...");
    
    // 初始化会话队列
    self.sessionQueue = dispatch_queue_create("com.facemonitor.sessionqueue", DISPATCH_QUEUE_SERIAL);
    self.visionSequenceHandler = [[VNSequenceRequestHandler alloc] init]; // 正确
    
    dispatch_async(self.sessionQueue, ^{
        [self setupCaptureSession];
    });
}

- (void)stopMonitoring {
    NSLog(@"[FaceMonitor] Stopping monitoring...");
    
    dispatch_async(self.sessionQueue, ^{
        if (self.captureSession && self.captureSession.isRunning) {
            [self.captureSession stopRunning];
        }
        [self.randomCaptureTimer invalidate];
        self.randomCaptureTimer = nil;
        
        // 清理界面
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.faceLayer removeFromSuperlayer];
            [self.previewLayer removeFromSuperlayer];
        });
        
        self.captureSession = nil;
        NSLog(@"[FaceMonitor] Monitoring stopped.");
    });
}

#pragma mark - Capture Session Setup
- (void)setupCaptureSession {
    self.captureSession = [[AVCaptureSession alloc] init];
    self.captureSession.sessionPreset = AVCaptureSessionPreset1280x720; // 平衡画质与性能
    
    // 1. 设置输入
    AVCaptureDevice *videoDevice = [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera mediaType:AVMediaTypeVideo position:AVCaptureDevicePositionFront];
    
    if (!videoDevice) {
        [self sendCallback:@{@"error": @"Front camera not available."}];
        return;
    }
    
    NSError *error;
    AVCaptureDeviceInput *videoInput = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:&error];
    if (error || !videoInput) {
        [self sendCallback:@{@"error": [NSString stringWithFormat:@"Failed to create video input: %@", error.localizedDescription]}];
        return;
    }
    
    if ([self.captureSession canAddInput:videoInput]) {
        [self.captureSession addInput:videoInput];
    }
    
    // 2. 设置视频输出（用于实时人脸检测）
    // 2. 设置视频输出（用于实时人脸检测）
    self.videoDataOutput = [[AVCaptureVideoDataOutput alloc] init]; // 使用 self.videoDataOutput
    self.videoDataOutput.alwaysDiscardsLateVideoFrames = YES;
    [self.videoDataOutput setSampleBufferDelegate:self queue:dispatch_queue_create("com.facemonitor.videooutput", DISPATCH_QUEUE_SERIAL)];

    if ([self.captureSession canAddOutput:self.videoDataOutput]) {
        [self.captureSession addOutput:self.videoDataOutput];
    }
//    AVCaptureVideoDataOutput *videoOutput = [[AVCaptureVideoDataOutput alloc] init];
//    videoOutput.alwaysDiscardsLateVideoFrames = YES;
//    [videoOutput setSampleBufferDelegate:self queue:dispatch_queue_create("com.facemonitor.videooutput", DISPATCH_QUEUE_SERIAL)];
//
//    if ([self.captureSession canAddOutput:videoOutput]) {
//        [self.captureSession addOutput:videoOutput];
//    }
    
    // 3. 设置照片输出（用于随机拍照）
    self.photoOutput = [[AVCapturePhotoOutput alloc] init];
    if ([self.captureSession canAddOutput:self.photoOutput]) {
        [self.captureSession addOutput:self.photoOutput];
    }
    
    // 4. 设置预览层（可选，如需在原生层显示）
    dispatch_async(dispatch_get_main_queue(), ^{
        self.previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:self.captureSession];
        self.previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
        // 设置previewLayer的frame，例如覆盖整个屏幕
        // self.previewLayer.frame = ...;
        // [self.view.layer addSublayer:self.previewLayer];
        
        // 初始化人脸框图层
        self.faceLayer = [CAShapeLayer layer];
        self.faceLayer.strokeColor = [UIColor greenColor].CGColor;
        self.faceLayer.lineWidth = 2.0;
        self.faceLayer.fillColor = [UIColor clearColor].CGColor;
        // [self.previewLayer addSublayer:self.faceLayer];
    });
    
    [self.captureSession startRunning];
    [self startRandomCaptureTimer]; // 启动随机拍照定时器
}

#pragma mark - Real-time Face Detection (AVCaptureVideoDataOutputSampleBufferDelegate)
- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    if (output != self.videoDataOutput) return;
    
    CVImageBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (!pixelBuffer) return;
    
    VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCVPixelBuffer:pixelBuffer orientation:kCGImagePropertyOrientationUp options:@{}];
    VNDetectFaceRectanglesRequest *faceRequest = [[VNDetectFaceRectanglesRequest alloc] initWithCompletionHandler:^(VNRequest * _Nonnull request, NSError * _Nullable error) {
        
        if (error) {
            return;
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            BOOL previousState = self.isFaceInView;
            NSArray<VNFaceObservation *> *results = request.results;
            self.isFaceInView = (results.count > 0);
            
            // 更新人脸框
            [self updateFaceRectLayerWithObservations:results];
            
            // 状态变化时发送事件
            if (previousState != self.isFaceInView) {
                NSDictionary *eventData = @{
                    @"isFaceInView": @(self.isFaceInView),
                    @"faceCount": @(results.count),
                    @"message": self.isFaceInView ? @"Face detected" : @"Face not in view"
                };
                [self sendCallback:eventData];
                
                if (!self.isFaceInView) {
                    // 可以触发提醒
                    [self sendCallback:@{@"alert": @"Please move your face into the frame."}];
                }
            }
        });
    }];
    
    NSError *performError;
    [handler performRequests:@[faceRequest] error:&performError];
}

#pragma mark - Face Rect Drawing
- (void)updateFaceRectLayerWithObservations:(NSArray<VNFaceObservation *> *)observations {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self updateFaceRectLayerWithObservations:observations];
        });
        return;
    }
    
    [self.faceLayer removeFromSuperlayer];
    
    if (observations.count == 0) {
        return;
    }
    
    // 简化处理：只绘制第一个人脸框
    VNFaceObservation *faceObs = observations.firstObject;
    CGRect boundingBox = faceObs.boundingBox;
    
    // 需要将Vision返回的归一化坐标转换为预览层的坐标
    // 注意：这是一个简化示例，实际转换需根据预览层大小和方向调整
    CGRect displayRect = [self convertNormalizedRect:boundingBox toViewRect:self.previewLayer.bounds];
    
    UIBezierPath *path = [UIBezierPath bezierPathWithRect:displayRect];
    self.faceLayer.path = path.CGPath;
    
    [self.previewLayer addSublayer:self.faceLayer];
}

- (CGRect)convertNormalizedRect:(CGRect)normalizedRect toViewRect:(CGRect)viewRect {
    return CGRectMake(normalizedRect.origin.x * viewRect.size.width,
                      normalizedRect.origin.y * viewRect.size.height,
                      normalizedRect.size.width * viewRect.size.width,
                      normalizedRect.size.height * viewRect.size.height);
}

#pragma mark - Random Capture
- (void)startRandomCaptureTimer {
    [self.randomCaptureTimer invalidate];
    
    // 设置随机间隔，例如5-15秒
    __weak typeof(self) weakSelf = self;
    self.randomCaptureTimer = [NSTimer scheduledTimerWithTimeInterval:10.0 repeats:YES block:^(NSTimer * _Nonnull timer) {
        [weakSelf tryCapturePhoto];
    }];
}

- (void)tryCapturePhoto {
    if (!self.isFaceInView) {
        NSLog(@"[FaceMonitor] No face detected, skipping capture.");
        return;
    }
    
    NSLog(@"[FaceMonitor] Attempting to capture photo...");
    dispatch_async(self.sessionQueue, ^{
        AVCapturePhotoSettings *settings = [AVCapturePhotoSettings photoSettings];
        [self.photoOutput capturePhotoWithSettings:settings delegate:self];
    });
}

#pragma mark - AVCapturePhotoCaptureDelegate
- (void)captureOutput:(AVCapturePhotoOutput *)output didFinishProcessingPhoto:(AVCapturePhoto *)photo error:(NSError *)error {
    if (error) {
        NSLog(@"[FaceMonitor] Capture failed: %@", error);
        [self sendCallback:@{@"error": [NSString stringWithFormat:@"Capture failed: %@", error.localizedDescription]}];
        return;
    }
    
    NSData *imageData = [photo fileDataRepresentation];
    if (!imageData) {
        NSLog(@"[FaceMonitor] Failed to get image data.");
        return;
    }
    
    NSLog(@"[FaceMonitor] Photo captured, size: %lu KB", (unsigned long)imageData.length / 1024);
    [self sendCallback:@{@"photoCaptured": @(imageData.length)}];
    
    // 上传到腾讯云COS
    [self uploadImageToCOS:imageData];
}

#pragma mark - Tencent Cloud COS Upload (示例框架)
- (void)uploadImageToCOS:(NSData *)imageData {
    NSLog(@"[FaceMonitor] Starting upload to COS...");
    
    // 重要：临时密钥应从您的业务服务器动态获取，切勿硬编码在客户端[9,10](@ref)。
    // 这里是一个示例流程，具体实现需根据您使用的腾讯云COS SDK版本进行调整。
    
    // 1. 从您的服务器获取临时上传凭证（安全做法）
    // 2. 使用COS SDK初始化上传请求
    // 3. 执行上传
    
    // 模拟上传成功
    [self sendCallback:@{@"uploadSuccess": @"https://your-bucket.cos.ap-shanghai.myqcloud.com/face_monitor/1234567890.jpg"}];
}

#pragma mark - Callback Helper
- (void)sendCallback:(NSDictionary *)data {
    if (self.statusCallback) {
        self.statusCallback(data, YES); // YES表示保持回调活跃，可以多次调用
    }
}

@end
