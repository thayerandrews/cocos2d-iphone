//
//  CCEffectStitcher.m
//  cocos2d
//
//  Created by Thayer J Andrews on 3/9/15.
//
//

#import "CCEffectStitcher.h"
#import "CCEffectStitcherGL.h"
#import "CCEffectStitcherMetal.h"
#import "CCSetup.h"

@implementation CCEffectStitcher

- (id)init
{
    return [super init];
}

+ (instancetype)stitcherWithEffects:(NSArray *)effects manglePrefix:(NSString *)prefix stitchListIndex:(NSUInteger)stitchListIndex shaderStartIndex:(NSUInteger)shaderStartIndex
{
    if([CCSetup sharedSetup].graphicsAPI == CCGraphicsAPIMetal)
    {
        return [[CCEffectStitcherMetal alloc] initWithEffects:effects manglePrefix:prefix stitchListIndex:stitchListIndex shaderStartIndex:shaderStartIndex];
    }
    else
    {
        return [[CCEffectStitcherGL alloc] initWithEffects:effects manglePrefix:prefix stitchListIndex:stitchListIndex shaderStartIndex:shaderStartIndex];
    }
}


- (NSArray *)renderPassDescriptors
{
    NSAssert(0, @"Subclasses must override this.");
    return nil;
}

- (NSArray *)shaders
{
    NSAssert(0, @"Subclasses must override this.");
    return nil;
}

@end


