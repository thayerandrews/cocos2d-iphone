//
//  CCEffectBloom.m
//  cocos2d-ios
//
//  Created by Oleg Osin on 4/14/14.
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


#import "CCEffectBloom.h"
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


@interface CCEffectBloom ()
@property (nonatomic, strong) NSNumber *conditionedIntensity;
@property (nonatomic, strong) NSNumber *conditionedThreshold;
@end


#pragma mark - CCEffectBloomImplGL

@interface CCEffectBloomImplGL : CCEffectImpl
@property (nonatomic, weak) CCEffectBloom *interface;
@end

@implementation CCEffectBloomImplGL

-(id)initWithInterface:(CCEffectBloom *)interface
{
    CCEffectBlurParams blurParams = CCEffectUtilsComputeBlurParams(interface.blurRadius, CCEffectBlurOptLinearFiltering);
    blurParams.luminanceThresholdEnabled = YES;
    
    NSArray *fragFunctions = [CCEffectBloomImplGL buildFragmentFunctionsWithBlurParams:blurParams];
    NSArray *fragTemporaries = @[[CCEffectFunctionTemporary temporaryWithType:@"vec4" name:@"tmp" initializer:CCEffectInitFragColor]];
    NSArray *fragCalls = @[[[CCEffectFunctionCall alloc] initWithFunction:fragFunctions[0] outputName:@"bloom" inputs:@{@"inputValue" : @"tmp"}]];
    NSArray *fragUniforms = @[
                              [CCEffectUniform uniform:@"sampler2D" name:CCShaderUniformPreviousPassTexture value:(NSValue *)[CCTexture none]],
                              [CCEffectUniform uniform:@"vec2" name:CCShaderUniformTexCoord1Center value:[NSValue valueWithGLKVector2:GLKVector2Make(0.0f, 0.0f)]],
                              [CCEffectUniform uniform:@"vec2" name:CCShaderUniformTexCoord1Extents value:[NSValue valueWithGLKVector2:GLKVector2Make(0.0f, 0.0f)]],
                              [CCEffectUniform uniform:@"vec2" name:CCShaderUniformTexCoord2Center value:[NSValue valueWithGLKVector2:GLKVector2Make(0.0f, 0.0f)]],
                              [CCEffectUniform uniform:@"vec2" name:CCShaderUniformTexCoord2Extents value:[NSValue valueWithGLKVector2:GLKVector2Make(0.0f, 0.0f)]],
                              [CCEffectUniform uniform:@"float" name:@"u_intensity" value:[NSNumber numberWithFloat:0.0f]]
                              ];
    
    CCEffectShaderBuilder *fragShaderBuilder = [[CCEffectShaderBuilderGL alloc] initWithType:CCEffectShaderBuilderFragment
                                                                                   functions:[[CCEffectShaderBuilderGL defaultFragmentFunctions] arrayByAddingObjectsFromArray:fragFunctions]
                                                                                       calls:fragCalls
                                                                                 temporaries:fragTemporaries
                                                                                    uniforms:fragUniforms
                                                                                    varyings:@[]];
    
    NSArray *renderPasses = [CCEffectBloomImplGL buildRenderPassesWithInterface:interface];
    NSArray *shaders =  @[[[CCEffectShader alloc] initWithVertexShaderBuilder:[CCEffectShaderBuilderGL defaultVertexShaderBuilder]  fragmentShaderBuilder:fragShaderBuilder]];

    if((self = [super initWithRenderPassDescriptors:renderPasses shaders:[[CCEffectBlurImplGL buildShadersWithBlurParams:blurParams] arrayByAddingObjectsFromArray:shaders]]))
    {
        self.interface = interface;
        self.debugName = @"CCEffectBloomImplGL";
        self.stitchFlags = 0;
        return self;
    }
    
    return self;
}

+ (NSArray *)buildFragmentFunctionsWithBlurParams:(CCEffectBlurParams)blurParams
{
    CCEffectFunctionInput *input = [[CCEffectFunctionInput alloc] initWithType:@"vec4" name:@"inputValue"];
    
    NSString *effectBody = CC_GLSL(
                                   vec4 dst = inputValue * CCEffectSampleWithBounds(cc_FragTexCoord2, cc_FragTexCoord2Center, cc_FragTexCoord2Extents, cc_MainTexture);
                                   vec4 src = texture2D(cc_PreviousPassTexture, cc_FragTexCoord1);
                                   return (src * u_intensity + dst) - ((src * dst) * u_intensity);
                                   );
    
    return @[[[CCEffectFunction alloc] initWithName:@"bloomEffect" body:effectBody inputs:@[input] returnType:@"vec4"]];
}

+ (NSArray *)buildRenderPassesWithInterface:(CCEffectBloom *)interface
{
    // optmized approach based on linear sampling - http://rastergrid.com/blog/2010/09/efficient-gaussian-blur-with-linear-sampling/ and GPUImage - https://github.com/BradLarson/GPUImage
    // pass 0: blurs (horizontal) texture[0] and outputs blurmap to texture[1]
    // pass 1: blurs (vertical) texture[1] and outputs to texture[2]
    // pass 2: blends texture[0] and texture[2] and outputs to texture[3]

    // Why not just use self (or "__weak self" really)? Because at the time these blocks are created,
    // self is not necesssarily valid.
    __weak CCEffectBloom *weakInterface = interface;

    CCEffectRenderPassDescriptor *pass0 = [CCEffectRenderPassDescriptor descriptor];
    pass0.debugLabel = @"CCEffectBloom pass 0";
    pass0.shaderIndex = 0;
    pass0.beginBlocks = @[[[CCEffectBeginBlockContext alloc] initWithBlock:^(CCEffectRenderPass *pass, CCEffectRenderPassInputs *passInputs){

        passInputs.shaderUniforms[CCShaderUniformMainTexture] = passInputs.previousPassTexture;
        passInputs.shaderUniforms[CCShaderUniformPreviousPassTexture] = passInputs.previousPassTexture;
        
        passInputs.shaderUniforms[CCShaderUniformTexCoord1Center] = [NSValue valueWithGLKVector2:passInputs.texCoord1Center];
        passInputs.shaderUniforms[CCShaderUniformTexCoord1Extents] = [NSValue valueWithGLKVector2:passInputs.texCoord1Extents];
        
        GLKVector2 dur = GLKVector2Make(1.0 / (passInputs.previousPassTexture.sizeInPixels.width / passInputs.previousPassTexture.contentScale), 0.0);
        passInputs.shaderUniforms[passInputs.uniformTranslationTable[@"u_blurDirection"]] = [NSValue valueWithGLKVector2:dur];
        
        passInputs.shaderUniforms[passInputs.uniformTranslationTable[@"u_luminanceThreshold"]] = weakInterface.conditionedThreshold;
        
    }]];
    
    
    CCEffectRenderPassDescriptor *pass1 = [CCEffectRenderPassDescriptor descriptor];
    pass1.debugLabel = @"CCEffectBloom pass 1";
    pass1.shaderIndex = 0;
    pass1.beginBlocks = @[[[CCEffectBeginBlockContext alloc] initWithBlock:^(CCEffectRenderPass *pass, CCEffectRenderPassInputs *passInputs){

        passInputs.shaderUniforms[CCShaderUniformPreviousPassTexture] = passInputs.previousPassTexture;
        passInputs.shaderUniforms[CCShaderUniformTexCoord1Center] = [NSValue valueWithGLKVector2:GLKVector2Make(0.5f, 0.5f)];
        passInputs.shaderUniforms[CCShaderUniformTexCoord1Extents] = [NSValue valueWithGLKVector2:GLKVector2Make(1.0f, 1.0f)];
        
        GLKVector2 dur = GLKVector2Make(0.0, 1.0 / (passInputs.previousPassTexture.sizeInPixels.height / passInputs.previousPassTexture.contentScale));
        passInputs.shaderUniforms[passInputs.uniformTranslationTable[@"u_blurDirection"]] = [NSValue valueWithGLKVector2:dur];
                
        passInputs.shaderUniforms[passInputs.uniformTranslationTable[@"u_luminanceThreshold"]] = @(0.0f);
        
    }]];

    
    CCEffectRenderPassDescriptor *pass2 = [CCEffectRenderPassDescriptor descriptor];
    pass2.debugLabel = @"CCEffectBloom pass 2";
    pass2.shaderIndex = 1;
    CCEffectTexCoordsMapping texCoordsMapping = { CCEffectTexCoordMapPreviousPassTex, CCEffectTexCoordMapMainTex };
    pass2.texCoordsMapping = texCoordsMapping;
    pass2.beginBlocks = @[[[CCEffectBeginBlockContext alloc] initWithBlock:^(CCEffectRenderPass *pass, CCEffectRenderPassInputs *passInputs){

        passInputs.shaderUniforms[CCShaderUniformPreviousPassTexture] = passInputs.previousPassTexture;
        passInputs.shaderUniforms[CCShaderUniformTexCoord1Center] = [NSValue valueWithGLKVector2:GLKVector2Make(0.5f, 0.5f)];
        passInputs.shaderUniforms[CCShaderUniformTexCoord1Extents] = [NSValue valueWithGLKVector2:GLKVector2Make(1.0f, 1.0f)];
        passInputs.shaderUniforms[CCShaderUniformTexCoord2Center] = [NSValue valueWithGLKVector2:passInputs.texCoord1Center];
        passInputs.shaderUniforms[CCShaderUniformTexCoord2Extents] = [NSValue valueWithGLKVector2:passInputs.texCoord1Extents];

        passInputs.shaderUniforms[passInputs.uniformTranslationTable[@"u_intensity"]] = weakInterface.conditionedIntensity;
        
    }]];

    return @[pass0, pass1, pass2];
}

@end



#pragma mark - CCEffectBloomImplMetal

@interface CCEffectBloomImplMetal : CCEffectImpl
@property (nonatomic, weak) CCEffectBloom *interface;
@end

@implementation CCEffectBloomImplMetal

-(id)initWithInterface:(CCEffectBloom *)interface
{
    CCEffectBlurParams blurParams = CCEffectUtilsComputeBlurParams(interface.blurRadius, CCEffectBlurOptLinearFiltering);
    blurParams.luminanceThresholdEnabled = YES;
    
    NSArray *renderPasses = [CCEffectBloomImplMetal buildRenderPassesWithInterface:interface];
    NSArray *shaders = [CCEffectBloomImplMetal buildShaders];

    if((self = [super initWithRenderPassDescriptors:renderPasses shaders:[[CCEffectBlurImplMetal buildShadersWithBlurParams:blurParams] arrayByAddingObjectsFromArray:shaders]]))
    {
        self.interface = interface;
        self.debugName = @"CCEffectBloomImplMetal";
        self.stitchFlags = 0;
        return self;
    }
    
    return self;
}

+ (NSArray *)buildShaders
{
    return @[[[CCEffectShader alloc] initWithVertexShaderBuilder:[CCEffectShaderBuilderMetal defaultVertexShaderBuilder] fragmentShaderBuilder:[CCEffectBloomImplMetal fragShaderBuilder]]];
}

+ (CCEffectShaderBuilder *)fragShaderBuilder
{
    NSArray *functions = [CCEffectBloomImplMetal buildFragmentFunctions];
    NSArray *temporaries = @[[CCEffectFunctionTemporary temporaryWithType:@"half4" name:@"tmp" initializer:CCEffectInitFragColor]];
    NSArray *calls = @[[[CCEffectFunctionCall alloc] initWithFunction:functions[0] outputName:@"bloomed" inputs:@{@"cc_FragIn" : @"cc_FragIn",
                                                                                                                  @"cc_PreviousPassTexture" : @"cc_PreviousPassTexture",
                                                                                                                  @"cc_PreviousPassTextureSampler" : @"cc_PreviousPassTextureSampler",
                                                                                                                  @"cc_MainTexture" : @"cc_MainTexture",
                                                                                                                  @"cc_MainTextureSampler" : @"cc_MainTextureSampler",
                                                                                                                  @"cc_FragTexCoordDimensions" : @"cc_FragTexCoordDimensions",
                                                                                                                  @"bloomIntensity" : @"bloomIntensity",
                                                                                                                  @"inputValue" : @"tmp"
                                                                                                                  }]];
    NSArray *arguments = @[
                           [[CCEffectShaderArgument alloc] initWithType:@"const device float&" name:@"bloomIntensity" qualifier:CCEffectShaderArgumentBuffer]
                           ];
    
    return [[CCEffectShaderBuilderMetal alloc] initWithType:CCEffectShaderBuilderFragment
                                                  functions:[[CCEffectShaderBuilderMetal defaultFragmentFunctions] arrayByAddingObjectsFromArray:functions]
                                                      calls:calls
                                                temporaries:temporaries
                                                  arguments:[[CCEffectShaderBuilderMetal defaultFragmentArguments] arrayByAddingObjectsFromArray:arguments]
                                                    structs:[CCEffectShaderBuilderMetal defaultStructDeclarations]];
}

+ (NSArray *)buildFragmentFunctions
{
    NSArray *inputs = @[
                        [[CCEffectFunctionInput alloc] initWithType:@"const CCFragData" name:CCShaderArgumentFragIn],
                        [[CCEffectFunctionInput alloc] initWithType:@"texture2d<half>" name:CCShaderUniformPreviousPassTexture],
                        [[CCEffectFunctionInput alloc] initWithType:@"sampler" name:CCShaderUniformPreviousPassTextureSampler],
                        [[CCEffectFunctionInput alloc] initWithType:@"texture2d<half>" name:CCShaderUniformMainTexture],
                        [[CCEffectFunctionInput alloc] initWithType:@"sampler" name:CCShaderUniformMainTextureSampler],
                        [[CCEffectFunctionInput alloc] initWithType:@"const device CCEffectTexCoordDimensions*" name:CCShaderArgumentTexCoordDimensions],
                        [[CCEffectFunctionInput alloc] initWithType:@"float" name:@"bloomIntensity"],
                        [[CCEffectFunctionInput alloc] initWithType:@"half4" name:@"inputValue"]
                        ];
    
    NSString *effectBody = CC_GLSL(
                                   half4 dst = inputValue * CCEffectSampleWithBounds(cc_FragIn.texCoord2, cc_FragTexCoordDimensions->texCoord2Center, cc_FragTexCoordDimensions->texCoord2Extents, cc_MainTexture, cc_MainTextureSampler);
                                   half4 src = cc_PreviousPassTexture.sample(cc_PreviousPassTextureSampler, cc_FragIn.texCoord1);
                                   return (src * bloomIntensity + dst) - ((src * dst) * bloomIntensity);
                                   );
    
    return @[[[CCEffectFunction alloc] initWithName:@"bloomEffect" body:effectBody inputs:inputs returnType:@"half4"]];
}

+ (NSArray *)buildRenderPassesWithInterface:(CCEffectBloom *)interface
{
    // optmized approach based on linear sampling - http://rastergrid.com/blog/2010/09/efficient-gaussian-blur-with-linear-sampling/ and GPUImage - https://github.com/BradLarson/GPUImage
    // pass 0: blurs (horizontal) texture[0] and outputs blurmap to texture[1]
    // pass 1: blurs (vertical) texture[1] and outputs to texture[2]
    // pass 2: blends texture[0] and texture[2] and outputs to texture[3]
    
    // Why not just use self (or "__weak self" really)? Because at the time these blocks are created,
    // self is not necesssarily valid.
    __weak CCEffectBloom *weakInterface = interface;
    
    
    CCEffectRenderPassDescriptor *pass0 = [CCEffectRenderPassDescriptor descriptor];
    pass0.debugLabel = @"CCEffectBloom pass 0";
    pass0.shaderIndex = 0;
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

        passInputs.shaderUniforms[passInputs.uniformTranslationTable[@"luminanceThreshold"]] = weakInterface.conditionedThreshold;
        
    }]];
    
    
    CCEffectRenderPassDescriptor *pass1 = [CCEffectRenderPassDescriptor descriptor];
    pass1.debugLabel = @"CCEffectBloom pass 1";
    pass1.shaderIndex = 0;
    pass1.beginBlocks = @[[[CCEffectBeginBlockContext alloc] initWithBlock:^(CCEffectRenderPass *pass, CCEffectRenderPassInputs *passInputs){

        passInputs.shaderUniforms[CCShaderUniformPreviousPassTexture] = passInputs.previousPassTexture;
        
        CCEffectTexCoordDimensions tcDims;
        tcDims.texCoord1Center = passInputs.texCoord1Center;
        tcDims.texCoord1Extents = passInputs.texCoord1Extents;
        tcDims.texCoord2Center = passInputs.texCoord2Center;
        tcDims.texCoord2Extents = passInputs.texCoord2Extents;
        passInputs.shaderUniforms[CCShaderArgumentTexCoordDimensions] = [NSValue valueWithBytes:&tcDims objCType:@encode(CCEffectTexCoordDimensions)];
        
        GLKVector2 dur = GLKVector2Make(0.0, 1.0 / (passInputs.previousPassTexture.sizeInPixels.height / passInputs.previousPassTexture.contentScale));
        passInputs.shaderUniforms[passInputs.uniformTranslationTable[@"blurDirection"]] = [NSValue valueWithGLKVector2:dur];
        
        passInputs.shaderUniforms[passInputs.uniformTranslationTable[@"luminanceThreshold"]] = @(0.0f);
        
    }]];
    
    CCEffectRenderPassDescriptor *pass2 = [CCEffectRenderPassDescriptor descriptor];
    pass2.debugLabel = @"CCEffectBloom pass 2";
    pass2.shaderIndex = 1;
    CCEffectTexCoordsMapping texCoordsMapping = { CCEffectTexCoordMapPreviousPassTex, CCEffectTexCoordMapMainTex };
    pass2.texCoordsMapping = texCoordsMapping;
    pass2.beginBlocks = @[[[CCEffectBeginBlockContext alloc] initWithBlock:^(CCEffectRenderPass *pass, CCEffectRenderPassInputs *passInputs){
        
        passInputs.shaderUniforms[CCShaderUniformPreviousPassTexture] = passInputs.previousPassTexture;
        
        CCEffectTexCoordDimensions tcDims;
        tcDims.texCoord1Center = GLKVector2Make(0.5f, 0.5f);
        tcDims.texCoord1Extents = GLKVector2Make(1.0f, 1.0f);
        tcDims.texCoord2Center = passInputs.texCoord1Center;
        tcDims.texCoord2Extents = passInputs.texCoord1Extents;
        passInputs.shaderUniforms[CCShaderArgumentTexCoordDimensions] = [NSValue valueWithBytes:&tcDims objCType:@encode(CCEffectTexCoordDimensions)];

        passInputs.shaderUniforms[passInputs.uniformTranslationTable[@"bloomIntensity"]] = weakInterface.conditionedIntensity;
        
    }]];
    
    return @[pass0, pass1, pass2];
}

@end


#pragma mark - CCEffectBloom

@implementation CCEffectBloom
{
    BOOL _shaderDirty;
}

-(id)init
{
    if((self = [self initWithPixelBlurRadius:2 intensity:1.0f luminanceThreshold:0.0f]))
    {
        return self;
    }
    
    return self;
}

-(id)initWithPixelBlurRadius:(NSUInteger)blurRadius intensity:(float)intensity luminanceThreshold:(float)luminanceThreshold
{
    if(self = [super init])
    {
        self.blurRadius = blurRadius;
        self.intensity = intensity;
        self.luminanceThreshold = luminanceThreshold;
        
        if([CCSetup sharedSetup].graphicsAPI == CCGraphicsAPIMetal)
        {
            self.effectImpl = [[CCEffectBloomImplMetal alloc] initWithInterface:self];
        }
        else
        {
            self.effectImpl = [[CCEffectBloomImplGL alloc] initWithInterface:self];
        }
        self.debugName = @"CCEffectBloom";
        return self;
    }

    return self;
}

+(instancetype)effectWithBlurRadius:(NSUInteger)blurRadius intensity:(float)intensity luminanceThreshold:(float)luminanceThreshold
{
    return [[self alloc] initWithPixelBlurRadius:blurRadius intensity:intensity luminanceThreshold:luminanceThreshold];
}

-(void)setLuminanceThreshold:(float)luminanceThreshold
{
    _luminanceThreshold = luminanceThreshold;
    _conditionedThreshold = [NSNumber numberWithFloat:clampf(luminanceThreshold, 0.0f, 1.0f)];
}

-(void)setIntensity:(float)intensity
{
    _intensity = intensity;
    _conditionedIntensity = [NSNumber numberWithFloat:5.0f * clampf(intensity, 0.0f, 1.0f)];
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
            self.effectImpl = [[CCEffectBloomImplMetal alloc] initWithInterface:self];
        }
        else
        {
            self.effectImpl = [[CCEffectBloomImplGL alloc] initWithInterface:self];
        }
        
        _shaderDirty = NO;
        
        result.status = CCEffectPrepareSuccess;
        result.changes = CCEffectPrepareShaderChanged;
    }
    return result;
}

@end

