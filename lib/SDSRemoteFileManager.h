/*
 * This file is part of the SDSRemoteFile package.
 * (c) Sergio De Simone, Freescapes Labs
 * Parts of this file (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import "SDSRemoteFileOperation.h"
#import "SDSFileDownloader.h"
#import "SDSFileCache.h"

typedef enum
{
    /**
     * By default, when a URL fail to be downloaded, the URL is blacklisted so the library won't keep trying.
     * This flag disable this blacklisting.
     */
    SDSRemoteFileRetryFailed = 1 << 0,
    /**
     * By default, image downloads are started during UI interactions, this flags disable this feature,
     * leading to delayed download on UIScrollView deceleration for instance.
     */
    SDSRemoteFileLowPriority = 1 << 1,
    /**
     * This flag disables on-disk caching
     */
    SDSRemoteFileCacheMemoryOnly = 1 << 2,
    /**
     * This flag enables progressive download, the image is displayed progressively during download as a browser would do.
     * By default, the image is only displayed once completely downloaded.
     */
    SDSRemoteFileProgressiveDownload = 1 << 3,
    /**
     * Even if the image is cached, respect the HTTP response cache control, and refresh the image from remote location if needed.
     * The disk caching will be handled by NSURLCache instead of SDSRemoteFile leading to slight performance degradation.
     * This option helps deal with images changing behind the same request URL, e.g. Facebook graph api profile pics.
     * If a cached image is refreshed, the completion block is called once with the cached image and again with the final image.
     *
     * Use this flag only if you can't make your URLs static with embeded cache busting parameter.
     */
    SDSRemoteFileRefreshCached = 1 << 4
} SDSRemoteFileOptions;

//typedef void(^SDSRemoteFileCompletedBlock)(UIImage *image, NSError *error, SDSFileCacheType cacheType);
typedef void(^SDSRemoteFileCompletedWithFinishedBlock)(NSData *fileData, NSError *error, SDSFileCacheType cacheType, BOOL finished);


@class SDSRemoteFileManager;

@protocol SDSRemoteFileManagerDelegate <NSObject>

@optional

/**
 * Controls which image should be downloaded when the image is not found in the cache.
 *
 * @param imageManager The current `SDSRemoteFileManager`
 * @param imageURL The url of the image to be downloaded
 *
 * @return Return NO to prevent the downloading of the image on cache misses. If not implemented, YES is implied.
 */
- (BOOL)remoteFileManager:(SDSRemoteFileManager *)manager shouldDownloadDataForURL:(NSURL *)URL;

/**
 * Allows to transform the image immediately after it has been downloaded and just before to cache it on disk and memory.
 * NOTE: This method is called from a global queue in order to not to block the main thread.
 *
 * @param imageManager The current `SDSRemoteFileManager`
 * @param image The image to transform
 * @param imageURL The url of the image to transform
 *
 * @return The transformed image object.
 */
- (UIImage *)remoteFileManager:(SDSRemoteFileManager *)manager processDownloadedData:(NSData*)fileData withURL:(NSURL *)URL;

@end

/**
 * The SDSRemoteFileManager is the class behind the UIImageView+WebCache category and likes.
 * It ties the asynchronous downloader (SDSFileDownloader) with the image cache store (SDSFileCache).
 * You can use this class directly to benefit from web image downloading with caching in another context than
 * a UIView.
 *
 * Here is a simple example of how to use SDSRemoteFileManager:
 *
 * @code

SDSRemoteFileManager *manager = [SDSRemoteFileManager sharedManager];
[manager downloadWithURL:imageURL
                 options:0
                progress:nil
               completed:^(UIImage *image, NSError *error, SDSFileCacheType cacheType, BOOL finished)
               {
                   if (image)
                   {
                       // do something with image
                   }
               }];

 * @endcode
 */
@interface SDSRemoteFileManager : NSObject

@property (weak, nonatomic) id<SDSRemoteFileManagerDelegate> delegate;

@property (strong, nonatomic, readonly) SDSFileCache *imageCache;
@property (strong, nonatomic, readonly) SDSFileDownloader *imageDownloader;

/**
 * The cache filter is a block used each time SDSRemoteFileManager need to convert an URL into a cache key. This can
 * be used to remove dynamic part of an image URL.
 *
 * The following example sets a filter in the application delegate that will remove any query-string from the
 * URL before to use it as a cache key:
 *
 * @code

[[SDSRemoteFileManager sharedManager] setCacheKeyFilter:^(NSURL *url)
{
    url = [[NSURL alloc] initWithScheme:url.scheme host:url.host path:url.path];
    return [url absoluteString];
}];

 * @endcode
 */
@property (strong) NSString *(^cacheKeyFilter)(NSURL *url);

/**
 * Returns global SDSRemoteFileManager instance.
 *
 * @return SDSRemoteFileManager shared instance
 */
+ (SDSRemoteFileManager *)sharedManager;

/**
 * Downloads the image at the given URL if not present in cache or return the cached version otherwise.
 *
 * @param url The URL to the image
 * @param options A mask to specify options to use for this request
 * @param progressBlock A block called while image is downloading
 * @param completedBlock A block called when operation has been completed.
 *
 *   This block as no return value and takes the requested UIImage as first parameter.
 *   In case of error the image parameter is nil and the second parameter may contain an NSError.
 *
 *   The third parameter is an `SDSFileCacheType` enum indicating if the image was retrived from the local cache
 *   or from the memory cache or from the network.
 *
 *   The last parameter is set to NO when the SDSRemoteFileProgressiveDownload option is used and the image is 
 *   downloading. This block is thus called repetidly with a partial image. When image is fully downloaded, the
 *   block is called a last time with the full image and the last parameter set to YES.
 *
 * @return Returns a cancellable NSOperation
 */
- (id<SDSRemoteFileOperation>)downloadWithURL:(NSURL *)url
                                   options:(SDSRemoteFileOptions)options
                                  progress:(SDSFileDownloaderProgressBlock)progressBlock
                                 completed:(SDSRemoteFileCompletedWithFinishedBlock)completedBlock;

/**
 * Cancel all current opreations
 */
- (void)cancelAll;

/**
 * Check one or more operations running
 */
- (BOOL)isRunning;

@end
