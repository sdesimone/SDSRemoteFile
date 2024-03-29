//
//  SDSAppDelegate.m
//  SDSFileDownloader
//
//  Created by sergio on 6/10/13.
//  Copyright (c) 2013 Sergio De Simone, Freescapes Labs. All rights reserved.
//

#import "SDSAppDelegate.h"
#import "SDSFileDownloader.h"

@implementation SDSAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    // Override point for customization after application launch.
    self.window.backgroundColor = [UIColor whiteColor];
    [self.window makeKeyAndVisible];
    
    NSString* imageURL = @"http://files.parse.com/b6a8c6d1-ba52-4d82-bde7-d2f2c9bb6fe4/6279b03f-521a-4481-97ae-553a0396ff98-MBAdef";
    
    [SDSFileDownloader.sharedDownloader
     downloadFileWithURL:[NSURL URLWithString:imageURL]
     options:0
     progress:^(NSUInteger receivedSize, long long expectedSize)
     {
         NSLog(@"PROGRESS: %f", ((float)receivedSize)/expectedSize);
     }
     completed:^(NSData* data, NSError *error, BOOL finished)
     {
         if (data && finished)
         {
             // do something with image
         }
     }];

    
    return YES;
}

- (void)applicationWillResignActive:(UIApplication *)application
{
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later. 
    // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
    // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
}

- (void)applicationWillTerminate:(UIApplication *)application
{
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
}

@end
