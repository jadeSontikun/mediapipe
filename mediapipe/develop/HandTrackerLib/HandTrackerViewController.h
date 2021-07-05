#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CoreVideo/CoreVideo.h>

@class Landmark;
@class HandTrackerViewController;

@protocol TrackerDelegate <NSObject>
- (void)handTracker: (HandTrackerViewController*)HandTrackerViewController didOutputLandmarks: (NSArray<Landmark *> *)landmarks;
- (void)handTracker: (HandTrackerViewController*)HandTrackerViewController didOutputPixelBuffer: (CVPixelBufferRef)pixelBuffer;
@end

@interface HandTrackerViewController : UIViewController
- (void)startGraph;
- (void)processVideoFrame:(CVPixelBufferRef)imageBuffer;
@property (weak, nonatomic) id <TrackerDelegate> delegate;
@end

@interface Landmark: NSObject
@property(nonatomic, readonly) float x;
@property(nonatomic, readonly) float y;
@property(nonatomic, readonly) float z;
@end
