//
//  CCEffectBlur_Private.h
//  cocos2d
//
//  Created by Thayer J Andrews on 4/16/15.
//
//

#import "CCEffect_Private.h"
#import "CCEffectUtils.h"

@class CCEffectBlur;

@interface CCEffectBlurImplGL : CCEffectImpl

@property (nonatomic, weak) CCEffectBlur *interface;

+ (NSArray *)buildShadersWithBlurParams:(CCEffectBlurParams)blurParams;

@end


@interface CCEffectBlurImplMetal : CCEffectImpl

@property (nonatomic, weak) CCEffectBlur *interface;

+ (NSArray *)buildShadersWithBlurParams:(CCEffectBlurParams)blurParams;

@end
