//
//  ADDataPresentationManager.h
//  AppData
//
//  Created by Fouad Raheb on 6/29/20.
//

#import <Foundation/Foundation.h>

typedef CGRect(^ADDataPresentationFrameHandler)(UIView *containerView);

@interface ADDataPresentationConfiguration : NSObject

@property (nonatomic, assign) CGFloat animationDuration; // default 0.25

@property (nonatomic, assign) CGFloat screenPercentage; // detault value is 66.66

@property (nonatomic, assign) BOOL fadeAnimation; // default NO

@property (nonatomic, strong) ADDataPresentationFrameHandler customFrameHandler;

@end

@interface ADDataPresentationManager : NSObject <UIViewControllerTransitioningDelegate>

@property (nonatomic, strong) ADDataPresentationConfiguration *configuration;

- (instancetype)initWithConfiguration:(ADDataPresentationConfiguration *)configuration;

@end
