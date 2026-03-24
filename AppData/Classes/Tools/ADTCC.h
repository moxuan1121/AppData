//
//  TCC.h
//  AppData
//

#ifndef ADTCC_h
#define ADTCC_h

#import <Foundation/Foundation.h>

// 彻底去掉 kTCCServiceAll 的声明，避免重复符号冲突
FOUNDATION_EXTERN int TCCAccessResetForBundleIdentifier(NSString *service, NSString *bundleIdentifier);
FOUNDATION_EXTERN NSArray<NSDictionary *> *TCCAccessCopyInformationForBundleIdentifier(NSString *bundleIdentifier);

#endif /* ADTCC_h */
