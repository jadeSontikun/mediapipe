#import "HandTracker.h"
#include "mediapipe/framework/formats/landmark.pb.h"
#import "mediapipe/objc/MPPCameraInputSource.h"
#import "mediapipe/objc/MPPGraph.h"
#import "mediapipe/objc/MPPPlayerInputSource.h"
#import "mediapipe/objc/MPPTimestampConverter.h"

static const char* kNumHandsInputSidePacket = "num_hands";

static const int kNumHands = 1;

static NSString* const kGraphName = @"hand_tracking_mobile_gpu";
static const char* kInputStream = "input_video";
static const char* kOutputStream = "output_video";
// static const char* kSobelOutputStream = "sobel_video";
static const char* kLandmarksOutputStream = "hand_landmarks";
static const char* kVideoQueueLabel = "com.odds.mediapipe.videoQueue";

@interface HandTracker () <MPPGraphDelegate, MPPInputSourceDelegate>
@property (nonatomic) MPPGraph* mediapipeGraph;

// Handles camera access via AVCaptureSession library.
@property (nonatomic) MPPCameraInputSource* cameraSource;

// Provides data from a video.
// @property (nonatomic) MPPPlayerInputSource* videoSource;

// Helps to convert timestamp.
@property (nonatomic) MPPTimestampConverter* timestampConverter;

// The data source for the demo.
// @property (nonatomic) MediaPipeDemoSourceMode sourceMode;

// Inform the user when camera is unavailable.
//@property(nonatomic) IBOutlet UILabel* noCameraLabel;

// Display the camera preview frames.
//@property(strong, nonatomic) IBOutlet UIView* liveView;

// Render frames in a layer.
// @property (nonatomic) MPPLayerRenderer* renderer;

// Process camera frames on this queue.
@property (nonatomic) dispatch_queue_t videoQueue;
@end

@interface Landmark ()
- (instancetype)initWithX:(float)x y:(float)y z:(float)z;
@end

@implementation HandTracker {
}

#pragma mark - Cleanup methods

- (void)dealloc
{
  self.mediapipeGraph.delegate = nil;
  [self.mediapipeGraph cancel];
  // Ignore errors since we're cleaning up.
  [self.mediapipeGraph closeAllInputStreamsWithError:nil];
  [self.mediapipeGraph waitUntilDoneWithError:nil];
}

#pragma mark - MediaPipe graph methods

- (MPPGraph*)loadGraphFromResource:(NSString*)resource
{
  // Load the graph config resource.
  NSError* configLoadError = nil;
  NSBundle* bundle = [NSBundle bundleForClass:[self class]];
  if (!resource || resource.length == 0) {
    return nil;
  }
  NSURL* graphURL = [bundle URLForResource:resource withExtension:@"binarypb"];
  NSData* data = [NSData dataWithContentsOfURL:graphURL options:0 error:&configLoadError];
  if (!data) {
    NSLog(@"Failed to load MediaPipe graph config: %@", configLoadError);
    return nil;
  }

  // Parse the graph config resource into mediapipe::CalculatorGraphConfig proto object.
  mediapipe::CalculatorGraphConfig config;
  config.ParseFromArray(data.bytes, data.length);

  // Create MediaPipe graph with mediapipe::CalculatorGraphConfig proto object.
  MPPGraph* newGraph = [[MPPGraph alloc] initWithGraphConfig:config];
  return newGraph;
}

- (void)startGraph
{
  //    self.renderer = [[MPPLayerRenderer alloc] init];
  //    self.renderer.layer.frame = self.liveView.layer.bounds;
  //    [self.liveView.layer addSublayer:self.renderer.layer];
  //    self.renderer.frameScaleMode = MPPFrameScaleModeFillAndCrop;

  self.timestampConverter = [[MPPTimestampConverter alloc] init];

  dispatch_queue_attr_t qosAttribute = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INTERACTIVE, /*relative_priority=*/0);
  self.videoQueue = dispatch_queue_create(kVideoQueueLabel, qosAttribute);

  self.mediapipeGraph = [self loadGraphFromResource:kGraphName];
  [self.mediapipeGraph addFrameOutputStream:kOutputStream outputPacketType:MPPPacketTypePixelBuffer];
  // [self.mediapipeGraph addFrameOutputStream:kSobelOutputStream outputPacketType:MPPPacketTypePixelBuffer];

  self.mediapipeGraph.delegate = self;

  [self.mediapipeGraph setSidePacket:(mediapipe::MakePacket<int>(kNumHands)) named:kNumHandsInputSidePacket];
  [self.mediapipeGraph addFrameOutputStream:kLandmarksOutputStream outputPacketType:MPPPacketTypeRaw];
  NSLog(@"Start Graph");
}

- (void)presentView
{
  self.cameraSource = [[MPPCameraInputSource alloc] init];
  [self.cameraSource setDelegate:self queue:self.videoQueue];
  self.cameraSource.sessionPreset = AVCaptureSessionPresetHigh;

  // self.cameraSource.cameraPosition = AVCaptureDevicePositionBack;
  self.cameraSource.cameraPosition = AVCaptureDevicePositionFront;
  // When using the front camera, mirror the input for a more natural look.
  self.cameraSource.videoMirrored = YES;

  // The frame's native format is rotated with respect to the portrait orientation.
  self.cameraSource.orientation = AVCaptureVideoOrientationPortrait;

  NSLog(@"prevent View");

  [self.cameraSource requestCameraAccessWithCompletionHandler:^void(BOOL granted) {
      if (granted) {
        //        dispatch_async(dispatch_get_main_queue(), ^{
        //          self.noCameraLabel.hidden = YES;
        //        });

        NSLog(@"Granted camera access");
        [self startGraphAndCamera];
      } else {
        NSLog(@"No camera acceess");
      }
  }];
}

- (void)setCameraPosition:(AVCaptureDevicePosition)cameraPosition
{
  self.cameraSource.cameraPosition = cameraPosition;
  NSLog(@"set camera position");
}

- (void)setVideoMirrored:(BOOL)videoMirrored
{
  self.cameraSource.videoMirrored = videoMirrored;
  NSLog(@"set video mirrored");
}

- (void)startGraphAndCamera
{
  // Start running self.mediapipeGraph.
  NSError* error;
  if (![self.mediapipeGraph startWithError:&error]) {
    NSLog(@"Failed to start graph: %@", error);
  } else if (![self.mediapipeGraph waitUntilIdleWithError:&error]) {
    NSLog(@"Failed to complete graph initial run: %@", error);
  }

  // Start fetching frames from the camera.
  dispatch_async(self.videoQueue, ^{ [self.cameraSource start]; });
  NSLog(@"Start fetching frames from the camera.");
}

#pragma mark - MPPInputSourceDelegate methods

// Must be invoked on self.videoQueue.
- (void)processVideoFrame:(CVPixelBufferRef)imageBuffer timestamp:(CMTime)timestamp fromSource:(MPPInputSource*)source
{
  NSLog(@"processVideoFrame.sendPixelBuffer");

  if (source != self.cameraSource) {
    NSLog(@"Unknown source: %@", source);
    return;
  }

  [self.mediapipeGraph sendPixelBuffer:imageBuffer
                            intoStream:kInputStream
                            packetType:MPPPacketTypePixelBuffer
                             timestamp:[self.timestampConverter timestampForMediaTime:timestamp]];

  NSLog(@"processVideoFrame.didProcessVideoFrame");
  dispatch_async(dispatch_get_main_queue(), ^{ [_delegate handTracker:self didProcessVideoFrame:imageBuffer withTimestamp:timestamp]; });
}

#pragma mark - MPPGraphDelegate methods

// Receives CVPixelBufferRef from the MediaPipe graph. Invoked on a MediaPipe worker thread.
- (void)mediapipeGraph:(MPPGraph*)graph didOutputPixelBuffer:(CVPixelBufferRef)pixelBuffer fromStream:(const std::string&)streamName
{
  //    if (streamName == self.graphOutputStream) {
  //        // Display the captured image on the screen.
  //        CVPixelBufferRetain(pixelBuffer);
  //        dispatch_async(dispatch_get_main_queue(), ^{
  //            [self.renderer renderPixelBuffer:pixelBuffer];
  //            CVPixelBufferRelease(pixelBuffer);
  //        });
  //    }
  NSLog(@"mediapipeGraph.didOutputPixelBuffer", streamName.c_str());
  NSString* result = [NSString stringWithUTF8String:&streamName != nil ? streamName.c_str() : ""];

  NSLog(@"didOutputPixelBuffer fromStream= %s", streamName.c_str());
  [_delegate handTracker:self didOutputPixelBuffer:pixelBuffer];
}

// Receives a raw packet from the MediaPipe graph. Invoked on a MediaPipe worker thread.
- (void)mediapipeGraph:(MPPGraph*)graph didOutputPacket:(const ::mediapipe::Packet&)packet fromStream:(const std::string&)streamName
{
  NSLog(@"didOutputPacket fromStream= %s", streamName.c_str());
  if (streamName == kLandmarksOutputStream) {
    if (packet.IsEmpty()) {
      NSLog(@"didOutputPacket packet EMPTY");
      return;
    }
    const auto& multiHandLandmarks = packet.Get<std::vector<::mediapipe::NormalizedLandmarkList>>();
    const auto& landmarks = multiHandLandmarks[0];

    //        for (int i = 0; i < landmarks.landmark_size(); ++i) {
    //            NSLog(@"\tLandmark[%d]: (%f, %f, %f)", i, landmarks.landmark(i).x(),
    //                  landmarks.landmark(i).y(), landmarks.landmark(i).z());
    //        }
    NSMutableArray<Landmark*>* result = [NSMutableArray array];

    for (int i = 0; i < landmarks.landmark_size(); ++i) {
      Landmark* landmark = [[Landmark alloc] initWithX:landmarks.landmark(i).x() y:landmarks.landmark(i).y() z:landmarks.landmark(i).z()];
      [result addObject:landmark];
    }

    NSLog(@"didOutputPacket packet sending");
    [_delegate handTracker:self didOutputLandmarks:result];
  }
}

@end

@implementation Landmark

- (instancetype)initWithX:(float)x y:(float)y z:(float)z
{
  self = [super init];
  if (self) {
    _x = x;
    _y = y;
    _z = z;
  }
  return self;
}

@end
