//
//  TCC.h
//  AppData
//
//  Created by udevs on 21/11/2020.
//

#ifndef ADTCC_h
#define ADTCC_h

#import <Foundation/Foundation.h>

FOUNDATION_EXTERN NSString *const kTCCServiceAll;

// 修改为直接传入 Bundle Identifier，摒弃旧的 CFBundleRef
FOUNDATION_EXTERN int TCCAccessResetForBundleIdentifier(NSString *service, NSString *bundleIdentifier);
FOUNDATION_EXTERN NSArray<NSDictionary *> *TCCAccessCopyInformationForBundleIdentifier(NSString *bundleIdentifier);

#endif /* ADTCC_h */
