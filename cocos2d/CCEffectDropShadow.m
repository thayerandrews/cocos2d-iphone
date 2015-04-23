//
//  CCEffectDropShadow.m
//  cocos2d-ios
//
//  Created by Oleg Osin on 5/12/14.
//
//
//  This effect makes use of algorithms and GLSL shaders from GPUImage whose
//  license is included here.
//
//  <Begin GPUImage license>
//
//  Copyright (c) 2012, Brad Larson, Ben Cochran, Hugues Lismonde, Keitaroh
//  Kobayashi, Alaric Cole, Matthew Clark, Jacob Gundersen, Chris Williams.
//  All rights reserved.
//
//  Redistribution and use in source and binary forms, with or without
//  modification, are permitted provided that the following conditions are met:
//
//  Redistributions of source code must retain the above copyright notice, this
//  list of conditions and the following disclaimer.
//  Redistributions in binary form must reproduce the above copyright notice,
//  this list of conditions and the following disclaimer in the documentation
//  and/or other materials provided with the distribution.
//  Neither the name of the GPUImage framework nor the names of its contributors
//  may be used to endorse or promote products derived from this software
//  without specific prior written permission.
//  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
//  AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
//  IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
//  ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
//  LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
//  CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
//  SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
//  INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
//  CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
//  ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
//  POSSIBILITY OF SUCH DAMAGE.
//
//  <End GPUImage license>

#import "CCEffectDropShadow.h"
#import "CCColor.h"
#import "CCEffectBlur_Private.h"
#import "CCEffectShader.h"
#import "CCEffectShaderBuilderGL.h"
#import "CCEffectShaderBuilderMetal.h"
#import "CCEffectUtils.h"
#import "CCEffect_Private.h"
#import "CCRenderer.h"
#import "CCSetup.h"
#import "CCTexture.h"



#pragma mark - CCEffectDropShadowImplGL

@interface CCEffectDropShadowImplGL : CCEffectImpl

@property (nonatomic, weak) CCEffectDropShadow *interface;

@end


@implementation CCEffectDropShadowImplGL

-(id)initWithInterface:(CCEffectDropShadow *)interface
{
    CCEffectBlurParams blurParams = CCEffectUtilsComputeBlurParams(interface.blurRadius, CCEffectBlurOptLinearFiltering);
    
    NSArray *fragFunctions = [CCEffectDropShadowImplGL buildFragmentFunctionsWithBlurParams:blurParams];
    NSArray *fragTemporaries = @[[CCEffectFunctionTemporary temporaryWithType:@"vec4" name:@"tmp" initializer:CCEffectInitFragColor]];
    NSArray *fragCalls = @[[[CCEffectFunctionCall alloc] initWithFunction:fragFunctions[0] outputName:@"dropShadow" inputs:@{@"inputValue" : @"tmp"}]];
    NSArray *fragUniforms = @[
                              [CCEffectUniform uniform:@"sampler2D" name:CCShaderUniformPreviousPassTexture value:(NSValue *)[CCTexture none]],
                              [CCEffectUniform uniform:@"vec2" name:CCShaderUniformTexCoord1Center value:[NSValue valueWithGLKVector2:GLKVector2Make(0.0f, 0.0f)]],
                              [CCEffectUniform uniform:@"vec2" name:CCShaderUniformTexCoord1Extents value:[NSValue valueWithGLKVector2:GLKVector2Make(0.0f, 0.0f)]],
                              [CCEffectUniform uniform:@"vec2" name:@"u_shadowOffset" value:[NSValue valueWithCGPoint:interface.shadowOffset]],
                              [CCEffectUniform uniform:@"vec4" name:@"u_shadowColor" value:[NSValue valueWithGLKVector4:interface.shadowColor.glkVector4]]
                              ];

    CCEffectShaderBuilder *fragShaderBuilder = [[CCEffectShaderBuilderGL alloc] initWithType:CCEffectShaderBuilderFragment
                                                                                   functions:fragFunctions
                                                                                       calls:fragCalls
                                                                                 temporaries:fragTemporaries
                                                                                    uniforms:fragUniforms
                                                                                    varyings:@[]];
    
    NSArray *renderPasses = [CCEffectDropShadowImplGL buildRenderPassesWithInterface:interface];
    NSArray *shaders =  @[
                          [[CCEffectShader alloc] initWithVertexShaderBuilder:[CCEffectShaderBuilderGL defaultVertexShaderBuilder] fragmentShaderBuilder:fragShaderBuilder]
                          ];
    
    if((self = [super initWithRenderPassDescriptors:renderPasses shaders:[[CCEffectBlurImplGL buildShadersWithBlurParams:blurParams] arrayByAddingObjectsFromArray:shaders]]))
    {
        self.interface = interface;
        self.debugName = @"CCEffectDropShadowImplGL";
        self.stitchFlags = 0;
        return self;
    }
    
    return self;
}

+ (NSArray *)buildFragmentFunctionsWithBlurParams:(CCEffectBlurParams)blurParams
{
    CCEffectFunctionInput *input = [[CCEffectFunctionInput alloc] initWithType:@"vec4" name:@"inputValue"];
    
    NSString *effectBody = CC_GLSL(
                                   highp float shadowOffsetAlpha = texture2D(cc_PreviousPassTexture, cc_FragTexCoord1 - u_shadowOffset).a;
                                   vec4 shadowColor = u_shadowColor * shadowOffsetAlpha;
                                   vec4 outputColor = inputValue * texture2D(cc_MainTexture, cc_FragTexCoord1);
                                   outputColor = outputColor + (1.0 - outputColor.a) * shadowColor;
                                   return outputColor;
                                   );
    
    return @[[[CCEffectFunction alloc] initWithName:@"dropShadowEffect" body:effectBody inputs:@[input] returnType:@"vec4"]];
}

+ (NSArray *)buildRenderPassesWithInterface:(CCEffectDropShadow *)interface
{
    // optmized approach based on linear sampling - http://rastergrid.com/blog/2010/09/efficient-gaussian-blur-with-linear-sampling/ and GPUImage - https://github.com/BradLarson/GPUImage
    // pass 0: blurs (horizontal) texture[0] and outputs blurmap to texture[1]
    // pass 1: blurs (vertical) texture[1] and outputs to texture[2]
    
    __weak CCEffectDropShadow *weakInterface = interface;

    CCEffectRenderPassDescriptor *pass0 = [CCEffectRenderPassDescriptor descriptor];
    pass0.debugLabel = @"CCEffectDropShadow pass 0";
    pass0.shaderIndex = 0;
    pass0.blendMode = [CCBlendMode premultipliedAlphaMode];
    pass0.beginBlocks = @[[[CCEffectBeginBlockContext alloc] initWithBlock:^(CCEffectRenderPass *pass, CCEffectRenderPassInputs *passInputs){

        passInputs.shaderUniforms[CCShaderUniformMainTexture] = passInputs.previousPassTexture;
        passInputs.shaderUniforms[CCShaderUniformPreviousPassTexture] = passInputs.previousPassTexture;

        passInputs.shaderUniforms[CCShaderUniformTexCoord1Center] = [NSValue valueWithGLKVector2:passInputs.texCoord1Center];
        passInputs.shaderUniforms[CCShaderUniformTexCoord1Extents] = [NSValue valueWithGLKVector2:passInputs.texCoord1Extents];
        
        GLKVector2 dur = GLKVector2Make(1.0 / (passInputs.previousPassTexture.sizeInPixels.width / passInputs.previousPassTexture.contentScale), 0.0);
        passInputs.shaderUniforms[passInputs.uniformTranslationTable[@"u_blurDirection"]] = [NSValue valueWithGLKVector2:dur];
        
    }]];

    
    CCEffectRenderPassDescriptor *pass1 = [CCEffectRenderPassDescriptor descriptor];
    pass1.debugLabel = @"CCEffectDropShadow pass 1";
    pass1.shaderIndex = 0;
    pass1.blendMode = [CCBlendMode premultipliedAlphaMode];
    pass1.beginBlocks = @[[[CCEffectBeginBlockContext alloc] initWithBlock:^(CCEffectRenderPass *pass, CCEffectRenderPassInputs *passInputs){

        passInputs.shaderUniforms[CCShaderUniformPreviousPassTexture] = passInputs.previousPassTexture;
        
        passInputs.shaderUniforms[CCShaderUniformTexCoord1Center] = [NSValue valueWithGLKVector2:passInputs.texCoord1Center];
        passInputs.shaderUniforms[CCShaderUniformTexCoord1Extents] = [NSValue valueWithGLKVector2:passInputs.texCoord1Extents];
        
        GLKVector2 dur = GLKVector2Make(0.0, 1.0 / (passInputs.previousPassTexture.sizeInPixels.height / passInputs.previousPassTexture.contentScale));
        passInputs.shaderUniforms[passInputs.uniformTranslationTable[@"u_blurDirection"]] = [NSValue valueWithGLKVector2:dur];
        
    }]];
    
    CCEffectRenderPassDescriptor *pass3 = [CCEffectRenderPassDescriptor descriptor];
    pass3.debugLabel = @"CCEffectDropShadow pass 3";
    pass3.shaderIndex = 1;
    pass3.blendMode = [CCBlendMode premultipliedAlphaMode];
    pass3.beginBlocks = @[[[CCEffectBeginBlockContext alloc] initWithBlock:^(CCEffectRenderPass *pass, CCEffectRenderPassInputs *passInputs){
        
        CGPoint offset = weakInterface.shadowOffset;
        offset.x /= passInputs.previousPassTexture.contentSize.width;
        offset.y /= passInputs.previousPassTexture.contentSize.height;
        
        passInputs.shaderUniforms[passInputs.uniformTranslationTable[@"u_shadowOffset"]] = [NSValue valueWithCGPoint:offset];
        passInputs.shaderUniforms[passInputs.uniformTranslationTable[@"u_shadowColor"]] = [NSValue valueWithGLKVector4:weakInterface.shadowColor.glkVector4];
        
    }]];
    
    return @[pass0, pass1, pass3];
}

@end


#pragma mark - CCEffectDropShadowImplMetal

typedef struct CCEffectDropShadowParameters
{
    GLKVector2 shadowOffset;
    GLKVector4 shadowColor;
} CCEffectDropShadowParameters;


@interface CCEffectDropShadowImplMetal : CCEffectImpl

@property (nonatomic, weak) CCEffectDropShadow *interface;

@end


@implementation CCEffectDropShadowImplMetal

-(id)initWithInterface:(CCEffectDropShadow *)interface
{
    CCEffectBlurParams blurParams = CCEffectUtilsComputeBlurParams(interface.blurRadius, CCEffectBlurOptNone);
    
    NSArray *renderPasses = [CCEffectDropShadowImplMetal buildRenderPassesWithInterface:interface];
    NSArray *shaders = [CCEffectDropShadowImplMetal buildShaders];
    
    if((self = [super initWithRenderPassDescriptors:renderPasses shaders:[[CCEffectBlurImplMetal buildShadersWithBlurParams:blurParams] arrayByAddingObjectsFromArray:shaders]]))
    {
        self.interface = interface;
        self.debugName = @"CCEffectDropShadowImplMetal";
        self.stitchFlags = 0
        ;
    }
    
    return self;
}

+ (NSArray *)buildShaders
{
    return @[[[CCEffectShader alloc] initWithVertexShaderBuilder:[CCEffectShaderBuilderMetal defaultVertexShaderBuilder] fragmentShaderBuilder:[CCEffectDropShadowImplMetal fragShaderBuilder]]];
}

+ (CCEffectShaderBuilder *)fragShaderBuilder
{
    NSArray *functions = [CCEffectDropShadowImplMetal buildFragmentFunctions];
    NSArray *temporaries = @[[CCEffectFunctionTemporary temporaryWithType:@"half4" name:@"tmp" initializer:CCEffectInitFragColor]];
    NSArray *calls = @[[[CCEffectFunctionCall alloc] initWithFunction:functions[0] outputName:@"shadowed" inputs:@{@"cc_FragIn" : @"cc_FragIn",
                                                                                                                   @"cc_PreviousPassTexture" : @"cc_PreviousPassTexture",
                                                                                                                   @"cc_PreviousPassTextureSampler" : @"cc_PreviousPassTextureSampler",
                                                                                                                   @"cc_MainTexture" : @"cc_MainTexture",
                                                                                                                   @"cc_MainTextureSampler" : @"cc_MainTextureSampler",
                                                                                                                   @"cc_FragTexCoordDimensions" : @"cc_FragTexCoordDimensions",
                                                                                                                   @"shadowParams" : @"shadowParams",
                                                                                                                   @"inputValue" : @"tmp"
                                                                                                                   }]];
    NSArray *arguments = @[
                           [[CCEffectShaderArgument alloc] initWithType:@"const device CCEffectDropShadowParameters*" name:@"shadowParams" qualifier:CCEffectShaderArgumentBuffer]
                           ];
    
    NSString* structDropShadowParams =
    @"float2 shadowOffset;\n"
    @"float4 shadowColor;\n";
    
    NSArray *structs = @[
                         [[CCEffectShaderStructDeclaration alloc] initWithName:@"CCEffectDropShadowParameters" body:structDropShadowParams]
                         ];
    
    return [[CCEffectShaderBuilderMetal alloc] initWithType:CCEffectShaderBuilderFragment
                                                  functions:[[CCEffectShaderBuilderMetal defaultFragmentFunctions] arrayByAddingObjectsFromArray:functions]
                                                      calls:calls
                                                temporaries:temporaries
                                                  arguments:[[CCEffectShaderBuilderMetal defaultFragmentArguments] arrayByAddingObjectsFromArray:arguments]
                                                    structs:[[CCEffectShaderBuilderMetal defaultStructDeclarations] arrayByAddingObjectsFromArray:structs]];
}

+ (NSArray *)buildFragmentFunctions
{
    NSArray *effectInputs = @[
                              [[CCEffectFunctionInput alloc] initWithType:@"const CCFragData" name:CCShaderArgumentFragIn],
                              [[CCEffectFunctionInput alloc] initWithType:@"texture2d<half>" name:CCShaderUniformPreviousPassTexture],
                              [[CCEffectFunctionInput alloc] initWithType:@"sampler" name:CCShaderUniformPreviousPassTextureSampler],
                              [[CCEffectFunctionInput alloc] initWithType:@"texture2d<half>" name:CCShaderUniformMainTexture],
                              [[CCEffectFunctionInput alloc] initWithType:@"sampler" name:CCShaderUniformMainTextureSampler],
                              [[CCEffectFunctionInput alloc] initWithType:@"const device CCEffectTexCoordDimensions*" name:CCShaderArgumentTexCoordDimensions],
                              [[CCEffectFunctionInput alloc] initWithType:@"const device CCEffectDropShadowParameters*" name:@"shadowParams"],
                              [[CCEffectFunctionInput alloc] initWithType:@"half4" name:@"inputValue"]
                              ];
    
    NSString *effectBody = CC_GLSL(
                                   float shadowAlpha = CCEffectSampleWithBounds(cc_FragIn.texCoord1 - shadowParams->shadowOffset,
                                                                                cc_FragTexCoordDimensions->texCoord1Center,
                                                                                cc_FragTexCoordDimensions->texCoord1Extents,
                                                                                cc_PreviousPassTexture,
                                                                                cc_PreviousPassTextureSampler).a;
                                   half4 shadowColor = (half4)(shadowParams->shadowColor * shadowAlpha);
                                   half4 outputColor = inputValue * cc_MainTexture.sample(cc_MainTextureSampler, cc_FragIn.texCoord1);
                                   outputColor = outputColor + (1.0 - outputColor.a) * shadowColor;
                                   return outputColor;

                                   );
    return @[[[CCEffectFunction alloc] initWithName:@"dropShadow" body:effectBody inputs:effectInputs returnType:@"half4"]];
}

+ (NSArray *)buildRenderPassesWithInterface:(CCEffectDropShadow *)interface
{
    // optmized approach based on linear sampling - http://rastergrid.com/blog/2010/09/efficient-gaussian-blur-with-linear-sampling/ and GPUImage - https://github.com/BradLarson/GPUImage
    // pass 0: blurs (horizontal) texture[0] and outputs blurmap to texture[1]
    // pass 1: blurs (vertical) texture[1] and outputs to texture[2]
    
    __weak CCEffectDropShadow *weakInterface = interface;

    CCEffectRenderPassDescriptor *pass0 = [CCEffectRenderPassDescriptor descriptor];
    pass0.debugLabel = @"CCEffectDropShadow pass 0";
    pass0.shaderIndex = 0;
    pass0.blendMode = [CCBlendMode premultipliedAlphaMode];
    pass0.beginBlocks = @[[[CCEffectBeginBlockContext alloc] initWithBlock:^(CCEffectRenderPass *pass, CCEffectRenderPassInputs *passInputs){

        passInputs.shaderUniforms[CCShaderUniformMainTexture] = passInputs.previousPassTexture;
        passInputs.shaderUniforms[CCShaderUniformPreviousPassTexture] = passInputs.previousPassTexture;
        
        CCEffectTexCoordDimensions tcDims;
        tcDims.texCoord1Center = passInputs.texCoord1Center;
        tcDims.texCoord1Extents = passInputs.texCoord1Extents;
        tcDims.texCoord2Center = passInputs.texCoord2Center;
        tcDims.texCoord2Extents = passInputs.texCoord2Extents;
        passInputs.shaderUniforms[CCShaderArgumentTexCoordDimensions] = [NSValue valueWithBytes:&tcDims objCType:@encode(CCEffectTexCoordDimensions)];
        
        GLKVector2 dur = GLKVector2Make(1.0 / (passInputs.previousPassTexture.sizeInPixels.width / passInputs.previousPassTexture.contentScale), 0.0);
        passInputs.shaderUniforms[passInputs.uniformTranslationTable[@"blurDirection"]] = [NSValue valueWithGLKVector2:dur];
    }]];
    
    
    CCEffectRenderPassDescriptor *pass1 = [CCEffectRenderPassDescriptor descriptor];
    pass1.debugLabel = @"CCEffectDropShadow pass 1";
    pass1.shaderIndex = 0;
    pass1.blendMode = [CCBlendMode premultipliedAlphaMode];
    pass1.beginBlocks = @[[[CCEffectBeginBlockContext alloc] initWithBlock:^(CCEffectRenderPass *pass, CCEffectRenderPassInputs *passInputs){

        passInputs.shaderUniforms[CCShaderUniformPreviousPassTexture] = passInputs.previousPassTexture;
        
        CCEffectTexCoordDimensions tcDims;
        tcDims.texCoord1Center = GLKVector2Make(0.5f, 0.5f);
        tcDims.texCoord1Extents = GLKVector2Make(1.0f, 1.0f);
        tcDims.texCoord2Center = passInputs.texCoord2Center;
        tcDims.texCoord2Extents = passInputs.texCoord2Extents;
        passInputs.shaderUniforms[CCShaderArgumentTexCoordDimensions] = [NSValue valueWithBytes:&tcDims objCType:@encode(CCEffectTexCoordDimensions)];
        
        GLKVector2 dur = GLKVector2Make(0.0, 1.0 / (passInputs.previousPassTexture.sizeInPixels.height / passInputs.previousPassTexture.contentScale));
        passInputs.shaderUniforms[passInputs.uniformTranslationTable[@"blurDirection"]] = [NSValue valueWithGLKVector2:dur];
        
    }]];
    
    CCEffectRenderPassDescriptor *pass3 = [CCEffectRenderPassDescriptor descriptor];
    pass3.debugLabel = @"CCEffectDropShadow pass 3";
    pass3.shaderIndex = 1;
    pass3.blendMode = [CCBlendMode premultipliedAlphaMode];
    pass3.beginBlocks = @[[[CCEffectBeginBlockContext alloc] initWithBlock:^(CCEffectRenderPass *pass, CCEffectRenderPassInputs *passInputs){
        
        passInputs.shaderUniforms[CCShaderUniformPreviousPassTexture] = passInputs.previousPassTexture;
        
        CCEffectTexCoordDimensions tcDims;
        tcDims.texCoord1Center = passInputs.texCoord1Center;
        tcDims.texCoord1Extents = passInputs.texCoord1Extents;
        tcDims.texCoord2Center = passInputs.texCoord2Center;
        tcDims.texCoord2Extents = passInputs.texCoord2Extents;
        passInputs.shaderUniforms[CCShaderArgumentTexCoordDimensions] = [NSValue valueWithBytes:&tcDims objCType:@encode(CCEffectTexCoordDimensions)];

        CCEffectDropShadowParameters parameters;
        parameters.shadowOffset = GLKVector2Make(weakInterface.shadowOffset.x / passInputs.previousPassTexture.contentSize.width,
                                                 weakInterface.shadowOffset.y / passInputs.previousPassTexture.contentSize.height);
        parameters.shadowColor = weakInterface.shadowColor.glkVector4;
        passInputs.shaderUniforms[passInputs.uniformTranslationTable[@"shadowParams"]] = [NSValue valueWithBytes:&parameters objCType:@encode(CCEffectDropShadowParameters)];
        
        
    }]];
    
    return @[pass0, pass1, pass3];
}

@end


#pragma mark - CCEffectDropShadow

@implementation CCEffectDropShadow
{
    BOOL _shaderDirty;
}

-(id)init
{
    return [self initWithShadowOffset:ccp(5, -5) shadowColor:[CCColor blackColor] blurRadius:2];
}

-(id)initWithShadowOffset:(CGPoint)shadowOffset shadowColor:(CCColor*)shadowColor blurRadius:(NSUInteger)blurRadius
{
    if((self = [super init]))
    {
        _shadowColor = shadowColor;
        _shadowOffset = shadowOffset;
        self.blurRadius = blurRadius;
        
        if([CCSetup sharedSetup].graphicsAPI == CCGraphicsAPIMetal)
        {
            self.effectImpl = [[CCEffectDropShadowImplMetal alloc] initWithInterface:self];
        }
        else
        {
            self.effectImpl = [[CCEffectDropShadowImplGL alloc] initWithInterface:self];
        }
        self.debugName = @"CCEffectDropShadow";
    }
    return self;
}

+(instancetype)effectWithShadowOffset:(CGPoint)shadowOffset shadowColor:(CCColor*)shadowColor blurRadius:(NSUInteger)blurRadius
{
    return [[self alloc] initWithShadowOffset:shadowOffset shadowColor:shadowColor blurRadius:blurRadius];
}

-(void)setBlurRadius:(NSUInteger)blurRadius
{
    _blurRadius = blurRadius;
    
    // The shader is constructed dynamically based on the blur radius
    // so mark it dirty.
    _shaderDirty = YES;
}

- (CCEffectPrepareResult)prepareForRenderingWithSprite:(CCSprite *)sprite
{
    CCEffectPrepareResult result = CCEffectPrepareNoop;
    if (_shaderDirty)
    {
        if([CCSetup sharedSetup].graphicsAPI == CCGraphicsAPIMetal)
        {
            self.effectImpl = [[CCEffectDropShadowImplMetal alloc] initWithInterface:self];
        }
        else
        {
            self.effectImpl = [[CCEffectDropShadowImplGL alloc] initWithInterface:self];
        }
        _shaderDirty = NO;
        
        result.status = CCEffectPrepareSuccess;
        result.changes = CCEffectPrepareShaderChanged;
    }
    return result;
}

@end

