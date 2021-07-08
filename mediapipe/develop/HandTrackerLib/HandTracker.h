#include <objc/objc.h>
#import <Foundation/Foundation.h>
#import <CoreVideo/CoreVideo.h>
#import <AVFoundation/AVFoundation.h>

@class Landmark;
@class HandTracker;

@protocol TrackerDelegate <NSObject>
- (void)handTracker: (HandTracker*)handTracker didOutputLandmarks: (NSArray<Landmark *> *)landmarks;
- (void)handTracker: (HandTracker*)handTracker didOutputPixelBuffer: (CVPixelBufferRef)pixelBuffer;
- (void)handTracker: (HandTracker*)handTracker didProcessVideoFrame: (CVPixelBufferRef)imageBuffer;
@end

@interface HandTracker : NSObject
- (instancetype)init;
- (void)startGraph;
- (void)presentView;
- (void)setCameraPosition:(AVCaptureDevicePosition)cameraPosition;
- (void)setVideoMirrored:(BOOL)videoMirrored;
@property (weak, nonatomic) id <TrackerDelegate> delegate;
@end

@interface Landmark: NSObject
@property(nonatomic, readonly) float x;
@property(nonatomic, readonly) float y;
@property(nonatomic, readonly) float z;
@end
