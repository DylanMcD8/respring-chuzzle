#include "render_scale.h"
#include <SDL.h>
#include <SDL_main.h>
#include <stdlib.h>
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>

#import <OpenGLES/EAGL.h>
#import <objc/runtime.h>
#import <OpenAL/al.h>
#import <OpenAL/alc.h>
// SDL owns one drawable view per context. Its window can be created before
// UIKit connects the scene; attach it once a foreground scene is available.
@interface EAGLContext (ChuzzleSDLDrawable)
@property(nonatomic, readonly) UIView *sdlView;
@end
void ChuzzleEnsureDrawableScene(void) {
    EAGLContext *context=EAGLContext.currentContext;
    if (![context respondsToSelector:@selector(sdlView)]) return;
    static UIWindow *drawableWindow;
    UIView *view=context.sdlView;
    UIWindow *window=view.window;
    if (window) drawableWindow=window;
    else if (drawableWindow && view) {
        // SDL keeps multiple contexts associated with one window, but creating
        // a guest context replaces the compositor view without clearing the
        // old view's SDL association. Restore the view that is presenting.
        drawableWindow.rootViewController.view=view;
        window=drawableWindow;
    }
    if (!window || window.windowScene) return;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class] ||
            scene.activationState == UISceneActivationStateBackground ||
            scene.activationState == UISceneActivationStateUnattached) continue;
        UIWindowScene *windowScene=(UIWindowScene *)scene;
        window.windowScene=windowScene;
        id<UIWindowSceneDelegate> delegate=(id)scene.delegate;
        if ([delegate respondsToSelector:@selector(window)] && delegate.window != window)
            delegate.window.hidden=YES;
        if ([delegate respondsToSelector:@selector(setWindow:)]) delegate.window=window;
        [window makeKeyAndVisible];
        if (@available(iOS 27.1,*)) {
            // Duo inner displays resize independently of physical orientation.
            [window.rootViewController setNeedsUpdateOfSupportedInterfaceOrientations];
        } else if (@available(iOS 16.0,*)) {
            [window.rootViewController setNeedsUpdateOfSupportedInterfaceOrientations];
            UIWindowSceneGeometryPreferencesIOS *geometry=[[UIWindowSceneGeometryPreferencesIOS alloc]
                initWithInterfaceOrientations:UIInterfaceOrientationMaskPortrait];
            [windowScene requestGeometryUpdateWithPreferences:geometry errorHandler:^(NSError *error) {
                NSLog(@"Chuzzle portrait orientation: %@",error);
            }];
        }
        break;
    }
}

// UIKit converts touch locations through this transform, so SDL's existing
// normalized-input mapping remains aligned with the enlarged game canvas.
static BOOL chuzzleFillScreenCropped;
static void ChuzzleApplyCroppedPresentation(EAGLContext *context) {
    if (![context respondsToSelector:@selector(sdlView)]) return;
    UIView *view = context.sdlView;
    if (!view || !view.window) return;
    UIWindow *window = view.window;
    if (@available(iOS 27.1,*)) {
        // SDL's original window was sized for one screen/orientation. Refresh
        // from the active scene after rotation or a Duo display transition.
        CGRect sceneBounds = window.windowScene.coordinateSpace.bounds;
        if (sceneBounds.size.width > 0 && sceneBounds.size.height > 0 &&
            !CGRectEqualToRect(window.frame, sceneBounds)) window.frame = sceneBounds;
    }
    CGSize windowSize = window.bounds.size;
    if (windowSize.width > 0 && windowSize.height > 0 &&
        !CGSizeEqualToSize(view.bounds.size, windowSize)) {
        // Never assign frame while the previous crop transform is active.
        view.transform = CGAffineTransformIdentity;
        view.bounds = (CGRect){CGPointZero, windowSize};
        view.center = CGPointMake(CGRectGetMidX(window.bounds), CGRectGetMidY(window.bounds));
        [view setNeedsLayout];
        NSLog(@"Chuzzle drawable resized: %.0fx%.0f", windowSize.width, windowSize.height);
    }
    CGSize size = view.bounds.size;
    if (size.width <= 0 || size.height <= 0) return;
    CGFloat zoom = ChuzzlePresentationZoom(size.width, size.height, chuzzleFillScreenCropped);
    CGAffineTransform transform = CGAffineTransformMakeScale(zoom, zoom);
    if (!CGAffineTransformEqualToTransform(view.transform, transform)) {
        view.transform = transform;
        view.window.clipsToBounds = YES;
        NSLog(@"Chuzzle presentation: cropped=%d zoom=%.4f view=%.0fx%.0f window=%.0fx%.0f",
              chuzzleFillScreenCropped, zoom, size.width, size.height,
              view.window.bounds.size.width, view.window.bounds.size.height);
    }
}

static BOOL (*chuzzleOriginalPresent)(id,SEL,NSUInteger);
static BOOL ChuzzlePresent(id context, SEL selector, NSUInteger target) {
    ChuzzleEnsureDrawableScene();
    ChuzzleApplyCroppedPresentation(context);
    if (getenv("CHUZZLE_MUTE") && alcGetCurrentContext()) alListenerf(AL_GAIN,0.0f);
    return chuzzleOriginalPresent(context,selector,target);
}

extern void ChuzzleFrameTimingSetActive(BOOL active);
static UIBackgroundTaskIdentifier backgroundSave;

void ChuzzleFinishBackgroundSave(void) {
    if (backgroundSave == UIBackgroundTaskInvalid) return;
    UIBackgroundTaskIdentifier task = backgroundSave;
    backgroundSave = UIBackgroundTaskInvalid;
    [UIApplication.sharedApplication endBackgroundTask:task];
}

void ChuzzleHostAudioActive(int active) {
    NSError *error = nil;
    [AVAudioSession.sharedInstance setActive:(active != 0)
        withOptions:active ? 0 : AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:&error];
    if (error) NSLog(@"Chuzzle audio lifecycle: %@", error);
}

@interface ChuzzleSceneDelegate : NSObject <UIWindowSceneDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation ChuzzleSceneDelegate
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    if (![scene isKindOfClass:UIWindowScene.class]) return;
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    self.window.rootViewController = [UIViewController new];
    self.window.rootViewController.view.backgroundColor = UIColor.blackColor;
    [self.window makeKeyAndVisible];
    NSLog(@"Chuzzle Compatibility scene connected");
}
- (void)sceneWillResignActive:(UIScene *)scene {
    UIApplication.sharedApplication.idleTimerDisabled = NO;
    ChuzzleFrameTimingSetActive(NO);
    id<UIApplicationDelegate> delegate = UIApplication.sharedApplication.delegate;
    if ([delegate respondsToSelector:@selector(applicationWillResignActive:)])
        [delegate applicationWillResignActive:UIApplication.sharedApplication];
}
- (void)sceneDidBecomeActive:(UIScene *)scene {
    UIApplication.sharedApplication.idleTimerDisabled = YES;
    ChuzzleFrameTimingSetActive(YES);
    id<UIApplicationDelegate> delegate = UIApplication.sharedApplication.delegate;
    if ([delegate respondsToSelector:@selector(applicationDidBecomeActive:)])
        [delegate applicationDidBecomeActive:UIApplication.sharedApplication];
}
- (void)sceneDidEnterBackground:(UIScene *)scene {
    if (backgroundSave == UIBackgroundTaskInvalid) {
        backgroundSave = [UIApplication.sharedApplication beginBackgroundTaskWithName:@"Save Chuzzle"
            expirationHandler:^{ ChuzzleFinishBackgroundSave(); }];
    }
    id<UIApplicationDelegate> delegate = UIApplication.sharedApplication.delegate;
    if ([delegate respondsToSelector:@selector(applicationDidEnterBackground:)])
        [delegate applicationDidEnterBackground:UIApplication.sharedApplication];
}
- (void)sceneWillEnterForeground:(UIScene *)scene {
    id<UIApplicationDelegate> delegate = UIApplication.sharedApplication.delegate;
    if ([delegate respondsToSelector:@selector(applicationWillEnterForeground:)])
        [delegate applicationWillEnterForeground:UIApplication.sharedApplication];
}
@end

extern void ChuzzleConfigureFrameTiming(NSString *documents);

extern int chuzzle_ios_run(const char *ipa, const char *resources, const char *documents);

int SDL_main(int argc, char *argv[]) {
    @autoreleasepool {
        // Detailed frame metrics are opt-in for diagnostic launches.
        setenv("CHUZZLE_RUNTIME_DIAGNOSTICS", "0", 0);
        NSError *error = nil;
        AVAudioSession *audio = [AVAudioSession sharedInstance];
        [audio setCategory:AVAudioSessionCategoryAmbient error:&error];
        [audio setActive:YES error:&error];
        if (error) NSLog(@"Audio session: %@", error);
        NSString *resources = NSBundle.mainBundle.resourcePath;
        NSString *ipa = [resources stringByAppendingPathComponent:@"Chuzzle-1.0.ipa"];
        NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        NSUserDefaults *settings = NSUserDefaults.standardUserDefaults;
        [settings registerDefaults:@{ @"AllowFullResolution": @YES, @"FillScreenCropped": @NO }];
        chuzzleFillScreenCropped = [settings boolForKey:@"FillScreenCropped"];
        BOOL allowFullResolution = [settings boolForKey:@"AllowFullResolution"];
        Method present = class_getInstanceMethod(EAGLContext.class, @selector(presentRenderbuffer:));
        chuzzleOriginalPresent = (void *)method_setImplementation(present, (IMP)ChuzzlePresent);
        ChuzzleConfigureFrameTiming(documents);
        CGSize pixels = UIScreen.mainScreen.nativeBounds.size;
        // The game stays portrait even if the device was launched sideways.
        double width = MIN(pixels.width, pixels.height);
        double height = MAX(pixels.width, pixels.height);
        if (!getenv("CHUZZLE_RENDER_SCALE")) {
            NSString *scale = [NSString stringWithFormat:@"%u", allowFullResolution ? ChuzzleRenderScale(
                chuzzleFillScreenCropped ? fmax(width, height * 2.0 / 3.0) : width,
                chuzzleFillScreenCropped ? fmax(height, width * 1.5) : height) : 1];
            setenv("CHUZZLE_RENDER_SCALE", scale.UTF8String, 1);
        }
        if (strcmp(getenv("CHUZZLE_RUNTIME_DIAGNOSTICS"), "1") == 0) {
            NSDictionary *renderInfo = @{ @"nativeWidth": @(width), @"nativeHeight": @(height),
                @"screenScale": @(UIScreen.mainScreen.scale),
                @"allowFullResolution": @(allowFullResolution), @"fillScreenCropped": @(chuzzleFillScreenCropped),
                @"renderScale": @(atoi(getenv("CHUZZLE_RENDER_SCALE"))) };
            [renderInfo writeToFile:[documents stringByAppendingPathComponent:@"rendering-info.plist"] atomically:YES];
        }
        return chuzzle_ios_run(ipa.fileSystemRepresentation, resources.fileSystemRepresentation, documents.fileSystemRepresentation);
    }
}

// Keep the host's UIKit entry point explicit instead of depending on an
// entry point pulled indirectly from the Rust static library's SDL objects.
#undef main
int main(int argc, char *argv[]) {
    backgroundSave = UIBackgroundTaskInvalid;
    // Let the Home gesture work normally, without SDL fullscreen deferral.
    SDL_SetHintWithPriority(SDL_HINT_IOS_HIDE_HOME_INDICATOR, "0", SDL_HINT_OVERRIDE);
    if (@available(iOS 27.1,*)) {
        // Rotate the native window while the game retains portrait coordinates.
        SDL_SetHintWithPriority(SDL_HINT_ORIENTATIONS,
            "Portrait PortraitUpsideDown LandscapeLeft LandscapeRight", SDL_HINT_OVERRIDE);
    }
    return SDL_UIKitRunApp(argc, argv, SDL_main);
}
