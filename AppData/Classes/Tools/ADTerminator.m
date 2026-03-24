//
//  TCC.m
//  AppData
//
//  Created by udevs on 21/11/2020.
//

#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import "ADTCC.h"

NSString *const kTCCServiceAll = @"kTCCServiceAll";

// 1. iOS 15+ TCC Identity API
typedef void* tcc_identity_t;
static tcc_identity_t (*tcc_identity_create_Ptr)(CFStringRef, int); // type 0 代表 bundle
static CFArrayRef (*TCCAccessCopyInformation_Ptr)(tcc_identity_t);
static int (*TCCAccessReset_Ptr)(CFStringRef, tcc_identity_t);

// 2. iOS 14 / Early iOS 15 字符串 API
static int (*TCCAccessResetForBundleId_Ptr)(CFStringRef, CFStringRef);
static CFArrayRef (*TCCAccessCopyInformationForBundleId_Ptr)(CFStringRef);

// 3. iOS 11 - 13 旧版 CFBundleRef API
static int (*TCCAccessResetForBundle_Ptr)(NSString *, CFBundleRef);
static CFArrayRef (*TCCAccessCopyInformationForBundle_Ptr)(CFBundleRef);

int TCCAccessResetForBundleIdentifier(NSString *service, NSString *bundleIdentifier) {
    if (!bundleIdentifier) return 0;

    // 优先：iOS 15+ 使用 tcc_identity_t
    if (tcc_identity_create_Ptr && TCCAccessReset_Ptr) {
        tcc_identity_t identity = tcc_identity_create_Ptr((__bridge CFStringRef)bundleIdentifier, 0);
        if (identity) {
            return TCCAccessReset_Ptr((__bridge CFStringRef)service, identity);
        }
    }
    
    // 备用：尝试直接传入 BundleID
    if (TCCAccessResetForBundleId_Ptr) {
        return TCCAccessResetForBundleId_Ptr((__bridge CFStringRef)service, (__bridge CFStringRef)bundleIdentifier);
    }

    // 兜底：降级为旧版 CFBundleRef 方式
    if (TCCAccessResetForBundle_Ptr) {
        Class lsAppProxyClass = NSClassFromString(@"LSApplicationProxy");
        if (lsAppProxyClass) {
            id proxy = [lsAppProxyClass performSelector:@selector(applicationProxyForIdentifier:) withObject:bundleIdentifier];
            if (proxy) {
                NSURL *bundleURL = [proxy performSelector:@selector(bundleURL)];
                if (bundleURL) {
                    CFBundleRef bundle = CFBundleCreate(kCFAllocatorDefault, (CFURLRef)bundleURL);
                    if (bundle) {
                        int result = TCCAccessResetForBundle_Ptr(service, bundle);
                        CFRelease(bundle);
                        return result;
                    }
                }
            }
        }
    }
    
    return 0;
}

NSArray<NSDictionary *> *TCCAccessCopyInformationForBundleIdentifier(NSString *bundleIdentifier) {
    if (!bundleIdentifier) return nil;
    
    CFArrayRef array = NULL;

    // 优先：iOS 15+ 使用 tcc_identity_t
    if (tcc_identity_create_Ptr && TCCAccessCopyInformation_Ptr) {
        tcc_identity_t identity = tcc_identity_create_Ptr((__bridge CFStringRef)bundleIdentifier, 0);
        if (identity) {
            array = TCCAccessCopyInformation_Ptr(identity);
        }
    } 
    // 备用：尝试直接传入 BundleID
    else if (TCCAccessCopyInformationForBundleId_Ptr) {
        array = TCCAccessCopyInformationForBundleId_Ptr((__bridge CFStringRef)bundleIdentifier);
    } 
    // 兜底：降级为旧版 CFBundleRef 方式
    else if (TCCAccessCopyInformationForBundle_Ptr) {
        Class lsAppProxyClass = NSClassFromString(@"LSApplicationProxy");
        if (lsAppProxyClass) {
            id proxy = [lsAppProxyClass performSelector:@selector(applicationProxyForIdentifier:) withObject:bundleIdentifier];
            if (proxy) {
                NSURL *bundleURL = [proxy performSelector:@selector(bundleURL)];
                if (bundleURL) {
                    CFBundleRef bundle = CFBundleCreate(kCFAllocatorDefault, (CFURLRef)bundleURL);
                    if (bundle) {
                        array = TCCAccessCopyInformationForBundle_Ptr(bundle);
                        CFRelease(bundle);
                    }
                }
            }
        }
    }

    if (array) {
        NSArray *objcArray = (__bridge_transfer NSArray *)array;
        return [objcArray copy];
    }
    return nil;
}

__attribute__((constructor))
static void initializeFunctions() {
    void *handle = dlopen("/System/Library/PrivateFrameworks/TCC.framework/TCC", RTLD_LAZY);
    if (handle) {
        // 绑定 iOS 15+ API
        tcc_identity_create_Ptr = dlsym(handle, "tcc_identity_create");
        TCCAccessCopyInformation_Ptr = dlsym(handle, "TCCAccessCopyInformation");
        TCCAccessReset_Ptr = dlsym(handle, "TCCAccessReset");
        
        // 绑定 iOS 14 API
        TCCAccessResetForBundleId_Ptr = dlsym(handle, "TCCAccessResetForBundleId");
        TCCAccessCopyInformationForBundleId_Ptr = dlsym(handle, "TCCAccessCopyInformationForBundleId");
        
        // 绑定 iOS 11-13 API
        TCCAccessResetForBundle_Ptr = dlsym(handle, "TCCAccessResetForBundle");
        TCCAccessCopyInformationForBundle_Ptr = dlsym(handle, "TCCAccessCopyInformationForBundle");
        
        dlclose(handle);
    }
}
