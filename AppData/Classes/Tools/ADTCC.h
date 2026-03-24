//
//  ADTCC.h
//  AppData
//

#ifndef ADTCC_h
#define ADTCC_h

#import <Foundation/Foundation.h>

// 增加 AD_ 前缀，彻底避免和底层 SDK 或其他文件产生同名冲突
FOUNDATION_EXTERN int AD_TCCAccessResetForBundleIdentifier(NSString *service, NSString *bundleIdentifier);
FOUNDATION_EXTERN NSArray<NSDictionary *> *AD_TCCAccessCopyInformationForBundleIdentifier(NSString *bundleIdentifier);

#endif /* ADTCC_h */
