/*
 * This file is part of the SDSRemoteFile package.
 * (c) Sergio De Simone, Freescapes Labs
 * Parts of this file (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import <Foundation/Foundation.h>

#import <TargetConditionals.h>

#ifdef __OBJC_GC__
#error SDSRemoteFile does not support Objective-C Garbage Collection
#endif

#if __IPHONE_OS_VERSION_MIN_REQUIRED < __IPHONE_5_0
#error SDSRemoteFile doesn't support Deployement Target version < 5.0
#endif

#if OS_OBJECT_USE_OBJC
#undef SDDispatchQueueRelease
#undef SDDispatchQueueSetterSementics
#define SDDispatchQueueRelease(q)
#define SDDispatchQueueSetterSementics strong
#else
#undef SDDispatchQueueRelease
#undef SDDispatchQueueSetterSementics
#define SDDispatchQueueRelease(q) (dispatch_release(q))
#define SDDispatchQueueSetterSementics assign
#endif

@protocol SDSRemoteFileOperation <NSObject>

- (void)cancel;

@end
