//
//  CCEffectSaturation.m
//  cocos2d-ios
//
//  Created by Thayer J Andrews on 5/14/14.
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


#import "CCEffectSaturation.h"
#import "CCDeviceInfo.h"
#import "CCEffectShader.h"
#import "CCEffectShaderBuilderGL.h"
#import "CCEffectShaderBuilderMetal.h"
#import "CCEffect_Private.h"
#import "CCRenderer.h"
#import "CCTexture.h"


static float conditionSaturation(float saturation);


@interface CCEffectSaturation ()
@property (nonatomic, strong) NSNumber *conditionedSaturation;
@end


#pragma mark - CCEffectSaturationImplGL

@interface CCEffectSaturationImplGL : CCEffectImpl
@property (nonatomic, weak) CCEffectSaturation *interface;
@end


@implementation CCEffectSaturationImplGL

-(id)initWithInterface:(CCEffectSaturation *)interface
{
    NSArray *renderPasses = [CCEffectSaturationImplGL buildRenderPassesWithInterface:interface];
    NSArray *shaders = [CCEffectSaturationImplGL buildShaders];
    
    if((self = [super initWithRenderPasses:renderPasses shaders:shaders]))
    {
        self.interface = interface;
        self.debugName = @"CCEffectSaturationImplGL";
    }
    return self;
}

+ (NSArray *)buildShaders
{
    return @[[[CCEffectShader alloc] initWithVertexShaderBuilder:[CCEffectShaderBuilderGL defaultVertexShaderBuilder] fragmentShaderBuilder:[CCEffectSaturationImplGL fragShaderBuilder]]];
}

+ (CCEffectShaderBuilder *)fragShaderBuilder
{
    NSArray *functions = [CCEffectSaturationImplGL buildFragmentFunctions];
    NSArray *temporaries = @[[CCEffectFunctionTemporary temporaryWithType:@"vec4" name:@"tmp" initializer:CCEffectInitPreviousPass]];
    NSArray *calls = @[[[CCEffectFunctionCall alloc] initWithFunction:functions[0] outputName:@"saturation" inputs:@{@"inputValue" : @"tmp"}]];
    
    NSArray *uniforms = @[
                          [CCEffectUniform uniform:@"sampler2D" name:CCShaderUniformPreviousPassTexture value:(NSValue *)[CCTexture none]],
                          [CCEffectUniform uniform:@"vec2" name:CCShaderUniformTexCoord1Center value:[NSValue valueWithGLKVector2:GLKVector2Make(0.0f, 0.0f)]],
                          [CCEffectUniform uniform:@"vec2" name:CCShaderUniformTexCoord1Extents value:[NSValue valueWithGLKVector2:GLKVector2Make(0.0f, 0.0f)]],
                          [CCEffectUniform uniform:@"float" name:@"u_saturation" value:[NSNumber numberWithFloat:1.0f]]
                          ];
    
    return [[CCEffectShaderBuilderGL alloc] initWithType:CCEffectShaderBuilderFragment
                                               functions:functions
                                                   calls:calls
                                             temporaries:temporaries
                                                uniforms:uniforms
                                                varyings:@[]];
}

+ (NSArray *)buildFragmentFunctions
{
    CCEffectFunctionInput *input = [[CCEffectFunctionInput alloc] initWithType:@"vec4" name:@"inputValue"];

    // Image saturation shader based on saturation filter in GPUImage - https://github.com/BradLarson/GPUImage
    NSString* effectBody = CC_GLSL(
                                   const vec3 luminanceWeighting = vec3(0.2125, 0.7154, 0.0721);

                                   float luminance = dot(inputValue.rgb, luminanceWeighting);
                                   vec3 greyScaleColor = vec3(luminance);

                                   return vec4(mix(greyScaleColor, inputValue.rgb, u_saturation), inputValue.a);
                                   );

    CCEffectFunction* fragmentFunction = [[CCEffectFunction alloc] initWithName:@"saturationEffect" body:effectBody inputs:@[input] returnType:@"vec4"];
    return @[fragmentFunction];
}

+ (NSArray *)buildRenderPassesWithInterface:(CCEffectSaturation *)interface
{
    __weak CCEffectSaturation *weakInterface = interface;
    
    CCEffectRenderPass *pass0 = [[CCEffectRenderPass alloc] init];
    pass0.debugLabel = @"CCEffectSaturation pass 0";
    pass0.blendMode = [CCBlendMode premultipliedAlphaMode];
    pass0.beginBlocks = @[[[CCEffectRenderPassBeginBlockContext alloc] initWithBlock:^(CCEffectRenderPass *pass, CCEffectRenderPassInputs *passInputs){
        
        passInputs.shaderUniforms[CCShaderUniformPreviousPassTexture] = passInputs.previousPassTexture;
        passInputs.shaderUniforms[CCShaderUniformTexCoord1Center] = [NSValue valueWithGLKVector2:passInputs.texCoord1Center];
        passInputs.shaderUniforms[CCShaderUniformTexCoord1Extents] = [NSValue valueWithGLKVector2:passInputs.texCoord1Extents];

        passInputs.shaderUniforms[passInputs.uniformTranslationTable[@"u_saturation"]] = weakInterface.conditionedSaturation;
    }]];
    
    return @[pass0];
}

@end



#pragma mark - CCEffectSaturationImplMetal

@interface CCEffectSaturationImplMetal : CCEffectImpl
@property (nonatomic, weak) CCEffectSaturation *interface;
@end


@implementation CCEffectSaturationImplMetal

-(id)initWithInterface:(CCEffectSaturation *)interface
{
    NSArray *renderPasses = [CCEffectSaturationImplMetal buildRenderPassesWithInterface:interface];
    NSArray *shaders = [CCEffectSaturationImplMetal buildShaders];
    
    if((self = [super initWithRenderPasses:renderPasses shaders:shaders]))
    {
        self.interface = interface;
        self.debugName = @"CCEffectSaturationImplMetal";
    }
    return self;
}

+ (NSArray *)buildShaders
{
    return @[[[CCEffectShader alloc] initWithVertexShaderBuilder:[CCEffectShaderBuilderMetal defaultVertexShaderBuilder] fragmentShaderBuilder:[CCEffectSaturationImplMetal fragShaderBuilder]]];
}

+ (CCEffectShaderBuilder *)fragShaderBuilder
{
    NSArray *functions = [CCEffectSaturationImplMetal buildFragmentFunctions];
    NSArray *temporaries = @[[CCEffectFunctionTemporary temporaryWithType:@"half4" name:@"tmp" initializer:CCEffectInitPreviousPass]];
    NSArray *calls = @[[[CCEffectFunctionCall alloc] initWithFunction:functions[0] outputName:@"saturationAdjusted" inputs:@{@"saturation" : @"saturation",
                                                                                                                             @"inputValue" : @"tmp"}]];
    NSArray *arguments = @[
                           [[CCEffectShaderArgument alloc] initWithType:@"const device float&" name:@"saturation" qualifier:CCEffectShaderArgumentBuffer]
                           ];
    
    return [[CCEffectShaderBuilderMetal alloc] initWithType:CCEffectShaderBuilderFragment
                                                  functions:functions
                                                      calls:calls
                                                temporaries:temporaries
                                                  arguments:[[CCEffectShaderBuilderMetal defaultFragmentArguments] arrayByAddingObjectsFromArray:arguments]
                                                    structs:[CCEffectShaderBuilderMetal defaultStructDeclarations]];
}

+ (NSArray *)buildFragmentFunctions
{
    NSString* effectBody = CC_GLSL(
                                   const half3 luminanceWeighting = half3(0.2125, 0.7154, 0.0721);
                                   
                                   float luminance = dot(inputValue.rgb, luminanceWeighting);
                                   half3 greyScaleColor = half3(luminance);
                                   
                                   return half4(mix(greyScaleColor, inputValue.rgb, (half)saturation), inputValue.a);
                                   );
    
    NSArray *inputs = @[
                        [[CCEffectFunctionInput alloc] initWithType:@"half4" name:@"inputValue"],
                        [[CCEffectFunctionInput alloc] initWithType:@"const device float&" name:@"saturation"],
                        ];
    CCEffectFunction* fragmentFunction = [[CCEffectFunction alloc] initWithName:@"saturationEffect"
                                                                           body:effectBody
                                                                         inputs:inputs
                                                                     returnType:@"half4"];
    
    return @[fragmentFunction];
    
}

+ (NSArray *)buildRenderPassesWithInterface:(CCEffectSaturation *)interface
{
    __weak CCEffectSaturation *weakInterface = interface;
    
    CCEffectRenderPass *pass0 = [[CCEffectRenderPass alloc] init];
    pass0.debugLabel = @"CCEffectSaturation pass 0";
    pass0.beginBlocks = @[[[CCEffectRenderPassBeginBlockContext alloc] initWithBlock:^(CCEffectRenderPass *pass, CCEffectRenderPassInputs *passInputs){
        
        passInputs.shaderUniforms[CCShaderUniformMainTexture] = passInputs.previousPassTexture;
        passInputs.shaderUniforms[CCShaderUniformPreviousPassTexture] = passInputs.previousPassTexture;
        
        CCEffectTexCoordDimensions tcDims;
        tcDims.texCoord1Center = passInputs.texCoord1Center;
        tcDims.texCoord1Extents = passInputs.texCoord1Extents;
        tcDims.texCoord2Center = passInputs.texCoord2Center;
        tcDims.texCoord2Extents = passInputs.texCoord2Extents;
        passInputs.shaderUniforms[CCShaderArgumentTexCoordDimensions] = [NSValue valueWithBytes:&tcDims objCType:@encode(CCEffectTexCoordDimensions)];
        
        passInputs.shaderUniforms[passInputs.uniformTranslationTable[@"saturation"]] = weakInterface.conditionedSaturation;
        
    }]];
    
    return @[pass0];
}

@end


#pragma mark - CCEffectSaturation

@implementation CCEffectSaturation

-(id)init
{
    return [self initWithSaturation:0.0f];
}

-(id)initWithSaturation:(float)saturation
{
    if((self = [super init]))
    {
        _saturation = saturation;
        _conditionedSaturation = [NSNumber numberWithFloat:conditionSaturation(saturation)];

        if([CCDeviceInfo sharedDeviceInfo].graphicsAPI == CCGraphicsAPIMetal)
        {
            self.effectImpl = [[CCEffectSaturationImplMetal alloc] initWithInterface:self];
        }
        else
        {
            self.effectImpl = [[CCEffectSaturationImplGL alloc] initWithInterface:self];
        }
        self.debugName = @"CCEffectSaturation";
    }
    return self;
}

+(instancetype)effectWithSaturation:(float)saturation
{
    return [[self alloc] initWithSaturation:saturation];
}

-(void)setSaturation:(float)saturation
{
    _saturation = saturation;
    _conditionedSaturation = [NSNumber numberWithFloat:conditionSaturation(saturation)];
}

@end


float conditionSaturation(float saturation)
{
    NSCAssert((saturation >= -1.0) && (saturation <= 1.0), @"Supplied saturation out of range [-1..1].");
    
    // Map from [-1..1] to [0..2]. The input values are photoshop equivalents
    // (-1 is complete desaturation, 0 is no change, and 1 is saturation boost)
    // while the output values are fed into the GLSL mix mix(a, b, t) function
    // where t=0 yields a and t=1 yields b. In our case a is the grayscale value
    // and b is the unmodified color value.
    float clampedSaturation = clampf(saturation, -1.0f, 1.0f);
    return clampedSaturation += 1.0f;
}
