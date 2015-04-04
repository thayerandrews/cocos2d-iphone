//
//  CCEffect.m
//  cocos2d-ios
//
//  Created by Oleg Osin on 3/29/14.
//
//


#import "CCEffect_Private.h"
#import "CCEffectShader.h"
#import "CCEffectShaderBuilder.h"
#import "CCTexture.h"
#import "CCColor.h"
#import "CCRenderer.h"


NSString * const CCShaderUniformPreviousPassTexture        = @"cc_PreviousPassTexture";
NSString * const CCShaderUniformPreviousPassTextureSampler = @"cc_PreviousPassTextureSampler";
NSString * const CCShaderUniformTexCoord1Center            = @"cc_FragTexCoord1Center";
NSString * const CCShaderUniformTexCoord1Extents           = @"cc_FragTexCoord1Extents";
NSString * const CCShaderUniformTexCoord2Center            = @"cc_FragTexCoord2Center";
NSString * const CCShaderUniformTexCoord2Extents           = @"cc_FragTexCoord2Extents";

NSString * const CCShaderArgumentVertexId                  = @"cc_VertexId";
NSString * const CCShaderArgumentVertexAtttributes         = @"cc_VertexAttributes";
NSString * const CCShaderArgumentTexCoordDimensions        = @"cc_FragTexCoordDimensions";
NSString * const CCShaderArgumentFragIn                    = @"cc_FragIn";

const CCEffectPrepareResult CCEffectPrepareNoop     = { CCEffectPrepareSuccess, CCEffectPrepareNothingChanged };

#pragma mark CCEffectImpl

@implementation CCEffectImpl

-(id)initWithRenderPasses:(NSArray *)renderPasses shaders:(NSArray *)shaders
{
    if((self = [super init]))
    {
        _stitchFlags = CCEffectFunctionStitchBoth;
        _firstInStack = YES;
        
        // Copy these arrays so the caller can't mutate them
        // behind our backs later (they could be NSMutableArray
        // after all).
        _renderPasses = [renderPasses copy];
        _shaders = [shaders copy];
        
        _shaderParameters = [[NSMutableDictionary alloc] init];
        NSMutableArray *allUTTs = [[NSMutableArray alloc] init];
        for (CCEffectShader *shader in _shaders)
        {
            NSAssert([shader isKindOfClass:[CCEffectShader class]], @"Expected a CCEffectShader but received something else.");
            [_shaderParameters addEntriesFromDictionary:shader.parameters];
            
            [allUTTs addObject:[CCEffectImpl buildDefaultTranslationTableFromParameterDictionary:shader.parameters]];
        }
        
        // Setup the pass shaders based on the pass shader indices and
        // supplied shaders.
        for (CCEffectRenderPass *pass in _renderPasses)
        {
            NSAssert([pass isKindOfClass:[CCEffectRenderPass class]], @"Expected a CCEffectRenderPass but received something else.");
            NSAssert(pass.shaderIndex < _shaders.count, @"Supplied shader index out of range.");
            
            pass.effectShader = _shaders[pass.shaderIndex];
            
            // If a uniform translation table is not set already, set it to the default.
            for (CCEffectRenderPassBeginBlockContext *blockContext in pass.beginBlocks)
            {
                if (!blockContext.uniformTranslationTable)
                {
                    blockContext.uniformTranslationTable = allUTTs[pass.shaderIndex];
                }
            }
        }
    }
    return self;
}

+ (NSMutableDictionary *)buildDefaultTranslationTableFromParameterDictionary:(NSDictionary *)parameters
{
    NSMutableDictionary *translationTable = [[NSMutableDictionary alloc] init];
    for(NSString *key in parameters)
    {
        translationTable[key] = key;
    }
    return translationTable;
    
}

-(NSUInteger)renderPassCount
{
    return _renderPasses.count;
}

- (BOOL)supportsDirectRendering
{
    return YES;
}

- (CCEffectPrepareResult)prepareForRenderingWithSprite:(CCSprite *)sprite
{
    return CCEffectPrepareNoop;
}

-(CCEffectRenderPass *)renderPassAtIndex:(NSUInteger)passIndex
{
    NSAssert((passIndex < _renderPasses.count), @"Pass index out of range.");
    return _renderPasses[passIndex];
}

-(BOOL)stitchSupported:(CCEffectFunctionStitchFlags)stitch
{
    NSAssert(stitch && ((stitch & CCEffectFunctionStitchBoth) == stitch), @"Invalid stitch flag specified");
    return ((stitch & _stitchFlags) == stitch);
}


@end

#pragma mark CCEffect

@implementation CCEffect

- (id)init
{
    return [super init];
}

- (BOOL)supportsDirectRendering
{
    NSAssert(_effectImpl, @"The effect has a nil implementation. Something is terribly wrong.");
    return _effectImpl.supportsDirectRendering;
}

- (NSUInteger)renderPassCount
{
    NSAssert(_effectImpl, @"The effect has a nil implementation. Something is terribly wrong.");
    return _effectImpl.renderPasses.count;
}

- (CCEffectPrepareResult)prepareForRenderingWithSprite:(CCSprite *)sprite;
{
    NSAssert(_effectImpl, @"The effect has a nil implementation. Something is terribly wrong.");
    return [_effectImpl prepareForRenderingWithSprite:sprite];
}

- (CCEffectRenderPass *)renderPassAtIndex:(NSUInteger)passIndex
{
    NSAssert(_effectImpl, @"The effect has a nil implementation. Something is terribly wrong.");
    return [_effectImpl renderPassAtIndex:passIndex];
}

@end


