//
//  ADActionsBarView.m
//  AppData
//
//  Created by Fouad Raheb on 12/3/20.
//  Copyright © 2020 Fouad Raheb. All rights reserved.
//

#import "ADActionsBarView.h"

@interface ADActionsBarView ()
@property (nonatomic, strong) UIStackView *stackView;
@end

@interface ADActionButton : UIButton
@property (nonatomic, strong) ADActionBarBlock actionBlock;
@property (nonatomic, strong) ADActionBarBlock longPressActionBlock;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *detailLabel;
@property (nonatomic, strong) UIImageView *actionImageView;
@property (nonatomic, strong) UIActivityIndicatorView *activityIndicatorView;
@end

@implementation ADActionsBarView

- (instancetype)init {
    if (self = [super init]) {
        self.axis = UILayoutConstraintAxisHorizontal;
        self.alignment = UIStackViewAlignmentFill;
        self.distribution = UIStackViewDistributionFillEqually;
        self.spacing = 1;
        self.backgroundColor = [UIColor clearColor];
    }
    return self;
}

- (void)addItemWithTitle:(NSString *)title detail:(NSString *)detail image:(UIImage *)image handler:(ADActionBarBlock)handler {
    [self addItemWithTitle:title detail:detail image:image handler:handler longPressHandler:nil];
}

- (void)addItemWithTitle:(NSString *)title detail:(NSString *)detail image:(UIImage *)image handler:(ADActionBarBlock)handler longPressHandler:(ADActionBarBlock)longPressHandler {
    ADActionButton *view = [[ADActionButton alloc] initWithFrame:CGRectZero];
    [view setActionBlock:handler];
    [view setLongPressActionBlock:longPressHandler];
    [view addTarget:self action:@selector(buttonTouchDown:) forControlEvents:UIControlEventTouchDown];
    [view addTarget:self action:@selector(buttonTouchUpInside:) forControlEvents:UIControlEventTouchUpInside];
    [view addTarget:self action:@selector(touchUpOutside:) forControlEvents:UIControlEventTouchUpOutside];
    [view addTarget:self action:@selector(buttonDragOutside:) forControlEvents:UIControlEventTouchDragOutside];
    [view addTarget:self action:@selector(buttonDragInside:) forControlEvents:UIControlEventTouchDragInside];
    if (longPressHandler) {
        UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(buttonLongPressed:)];
        [view addGestureRecognizer:longPress];
    }

    view.actionImageView = [[UIImageView alloc] init];
    view.actionImageView.userInteractionEnabled = NO;
    [view.actionImageView setImage:[image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
    
    // 使用等比例缩放，不裁切变形
    view.actionImageView.contentMode = UIViewContentModeScaleAspectFit;
    view.actionImageView.translatesAutoresizingMaskIntoConstraints = NO;
    [view addSubview:view.actionImageView];

    // 锁定统一大小为 31x31
    [view.actionImageView.topAnchor constraintEqualToAnchor:view.topAnchor constant:8].active = YES;
    [view.actionImageView.centerXAnchor constraintEqualToAnchor:view.centerXAnchor].active = YES;
    [view.actionImageView.widthAnchor constraintEqualToConstant:33].active = YES;
    [view.actionImageView.heightAnchor constraintEqualToConstant:33].active = YES;

    // 加载动画
    view.activityIndicatorView = [ADAppearance.sharedInstance activityIndicatorView];
    view.activityIndicatorView.userInteractionEnabled = NO;
    view.activityIndicatorView.translatesAutoresizingMaskIntoConstraints = NO;
    [view.activityIndicatorView hidesWhenStopped];
    [view.activityIndicatorView stopAnimating];
    [view addSubview:view.activityIndicatorView];
    
    [view.activityIndicatorView.topAnchor constraintEqualToAnchor:view.topAnchor constant:8].active = YES;
    [view.activityIndicatorView.centerXAnchor constraintEqualToAnchor:view.centerXAnchor].active = YES;
    [view.activityIndicatorView.widthAnchor constraintEqualToConstant:31].active = YES;
    [view.activityIndicatorView.heightAnchor constraintEqualToConstant:31].active = YES;

    view.nameLabel = [[UILabel alloc] init];
    view.nameLabel.tag = 2;
    view.nameLabel.userInteractionEnabled = NO;
    view.nameLabel.textAlignment = NSTextAlignmentCenter;
    view.nameLabel.font = [UIFont systemFontOfSize:11];
    
    // 【修改点：强制单行显示，并且自动缩小字体防止越界】
    view.nameLabel.numberOfLines = 1;
    view.nameLabel.adjustsFontSizeToFitWidth = YES;
    view.nameLabel.minimumScaleFactor = 0.8;
    
    [view.nameLabel setText:title];
    view.nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [view addSubview:view.nameLabel];
    
    // 图标与文字增加 4pt 间距
    [view.nameLabel.topAnchor constraintEqualToAnchor:view.actionImageView.bottomAnchor constant:4].active = YES;
    [view.nameLabel.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:2].active = YES;
    [view.nameLabel.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-2].active = YES;

    if (detail && detail.length > 0) {
        [view.nameLabel.heightAnchor constraintEqualToAnchor:view.heightAnchor multiplier:0.35].active = YES;
        view.detailLabel = [[UILabel alloc] init];
        view.detailLabel.tag = 3;
        view.detailLabel.userInteractionEnabled = NO;
        view.detailLabel.textAlignment = NSTextAlignmentCenter;
        view.detailLabel.font = [UIFont systemFontOfSize:11];
        [view.detailLabel setText:detail];
        view.detailLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [view addSubview:view.detailLabel];
        [view.detailLabel.topAnchor constraintEqualToAnchor:view.nameLabel.bottomAnchor].active = YES;
        [view.detailLabel.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:2].active = YES;
        [view.detailLabel.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-2].active = YES;
        [view.detailLabel.bottomAnchor constraintEqualToAnchor:view.bottomAnchor constant:-5].active = YES;
    } else {
        [view.nameLabel.bottomAnchor constraintEqualToAnchor:view.bottomAnchor constant:-5].active = YES;
    }
    
    [self addArrangedSubview:view];
}

- (void)buttonLongPressed:(UILongPressGestureRecognizer *)recognizer {
    if (recognizer.state != UIGestureRecognizerStateBegan) return;
    ADActionButton *button = (ADActionButton *)recognizer.view;
    [self setSubviewsOfButton:button highlighted:NO];
    if (button.longPressActionBlock) {
        [[UIImpactFeedbackGenerator new] impactOccurred];
        button.longPressActionBlock();
    }
}

- (void)setItemEnabled:(BOOL)enabled atIndex:(NSInteger)index {
    ADActionButton *button = [self.arrangedSubviews objectAtIndex:index];
    [button setEnabled:enabled];
    button.actionImageView.alpha = enabled ? 1.0 : 0.5;
    button.nameLabel.alpha = enabled ? 1.0 : 0.5;
    button.detailLabel.alpha = enabled ? 1.0 : 0.5;
}

- (void)setTitle:(NSString *)title forItemAtIndex:(NSInteger)index {
    ADActionButton *button = [self.arrangedSubviews objectAtIndex:index];
    [button.nameLabel setText:title];
}

- (void)setDetail:(NSString *)detail forItemAtIndex:(NSInteger)index {
    ADActionButton *button = [self.arrangedSubviews objectAtIndex:index];
    [button.detailLabel setText:detail];
}

- (void)showLoadingIndicatorForItemAtIndex:(NSInteger)index {
    ADActionButton *button = [self.arrangedSubviews objectAtIndex:index];
    [button.actionImageView setHidden:YES];
    [button.activityIndicatorView startAnimating];
}

- (void)hideLoadingIndicatorForItemAtIndex:(NSInteger)index {
    ADActionButton *button = [self.arrangedSubviews objectAtIndex:index];
    [button.activityIndicatorView stopAnimating];
    [button.actionImageView setHidden:NO];
}

- (void)buttonTouchUpInside:(ADActionButton *)button {
    [self setSubviewsOfButton:button highlighted:NO];
    if (button.actionBlock) {
        [[UISelectionFeedbackGenerator new] selectionChanged];
        button.actionBlock();
    }
}

- (void)buttonTouchDown:(ADActionButton *)button {
    [self setSubviewsOfButton:button highlighted:YES];
}

- (void)touchUpOutside:(ADActionButton *)button {
    [self setSubviewsOfButton:button highlighted:NO];
}

- (void)buttonDragOutside:(id)button {
    [self setSubviewsOfButton:button highlighted:NO];
}

- (void)buttonDragInside:(id)button {
    [self setSubviewsOfButton:button highlighted:YES];
}

- (void)setSubviewsOfButton:(ADActionButton *)button highlighted:(BOOL)highlighted {
    button.actionImageView.alpha = highlighted ? 0.5 : 1.0;
    button.nameLabel.alpha = highlighted ? 0.5 : 1.0;
    button.detailLabel.alpha = highlighted ? 0.5 : 1.0;
}

@end


@implementation ADActionButton

- (void)layoutSubviews {
    [super layoutSubviews];
    self.nameLabel.textColor = [ADAppearance.sharedInstance primaryTextColor];
    self.detailLabel.textColor = [ADAppearance.sharedInstance secondaryTextColor];
    self.actionImageView.tintColor = [ADAppearance.sharedInstance actionsBarIconTintColor];
}

@end
