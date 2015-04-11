//
//  CCEffectBlurReference.m
//  cocos2d
//
//  Created by Thayer J Andrews on 4/9/15.
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


#import "CCEffectBlurReference.h"
#import "CCEffectShader.h"
#import "CCEffectShaderBuilderGL.h"
#import "CCEffectUtils.h"
#import "CCEffect_Private.h"
#import "CCTexture.h"
#import "CCRendererBasicTypes.h"
#import "NSValue+CCRenderer.h"


@interface CCEffectBlurReferenceImplGL : CCEffectImpl
@property (nonatomic, weak) CCEffectBlurReference *interface;
@end

@implementation CCEffectBlurReferenceImplGL

-(id)initWithInterface:(CCEffectBlurReference *)interface
{
    CCEffectBlurParams blurParams = CCEffectUtilsComputeBlurParams(interface.blurRadius);
        
    NSArray *fragFunctions = [CCEffectBlurReferenceImplGL buildFragmentFunctionsWithBlurParams:blurParams];
    NSArray *fragTemporaries = @[[CCEffectFunctionTemporary temporaryWithType:@"vec4" name:@"tmp" initializer:CCEffectInitFragColor]];
    NSArray *fragCalls = @[[[CCEffectFunctionCall alloc] initWithFunction:fragFunctions[0] outputName:@"blurred" inputs:@{@"inputValue" : @"tmp"}]];
    NSArray *fragUniforms = @[
                              [CCEffectUniform uniform:@"sampler2D" name:CCShaderUniformPreviousPassTexture value:(NSValue *)[CCTexture none]],
                              [CCEffectUniform uniform:@"vec2" name:CCShaderUniformTexCoord1Center value:[NSValue valueWithGLKVector2:GLKVector2Make(0.0f, 0.0f)]],
                              [CCEffectUniform uniform:@"vec2" name:CCShaderUniformTexCoord1Extents value:[NSValue valueWithGLKVector2:GLKVector2Make(0.0f, 0.0f)]],
                              [CCEffectUniform uniform:@"highp vec2" name:@"u_sampleStep" value:[NSValue valueWithGLKVector2:GLKVector2Make(0.0f, 0.0f)]]
                              ];
    
    CCEffectShaderBuilder *fragShaderBuilder = [[CCEffectShaderBuilderGL alloc] initWithType:CCEffectShaderBuilderFragment
                                                                                   functions:fragFunctions
                                                                                       calls:fragCalls
                                                                                 temporaries:fragTemporaries
                                                                                    uniforms:fragUniforms
                                                                                    varyings:@[]];
    
    
    NSArray *renderPasses = [CCEffectBlurReferenceImplGL buildRenderPasses];
    NSArray *shaders =  @[[[CCEffectShader alloc] initWithVertexShaderBuilder:[CCEffectShaderBuilderGL defaultVertexShaderBuilder] fragmentShaderBuilder:fragShaderBuilder]];
    
    if((self = [super initWithRenderPasses:renderPasses shaders:shaders]))
    {
        self.interface = interface;
        self.debugName = @"CCEffectBlurReferenceImplGL";
        self.stitchFlags = 0;
        return self;
    }
    
    return self;
}

+ (NSArray *)buildFragmentFunctionsWithBlurParams:(CCEffectBlurParams)blurParams
{
    GLfloat *standardGaussianWeights = CCEffectUtilsComputeGaussianWeightsWithBlurParams(blurParams);
    
    NSMutableString *shaderString = [[NSMutableString alloc] init];
    
    // Header
    [shaderString appendFormat:@"\
     vec4 sum = vec4(0.0);\n\
     vec2 compare;\
     vec2 sampleCoord;\
     float inBounds;\
     "];
    
    // Inner texture loop
    for (NSUInteger currentBlurCoordinateIndex = 0; currentBlurCoordinateIndex < (blurParams.trueRadius * 2 + 1); currentBlurCoordinateIndex++)
    {
        NSInteger offsetFromCenter = currentBlurCoordinateIndex - blurParams.trueRadius;
        NSInteger weightIndex = offsetFromCenter;
        if (offsetFromCenter < 0)
        {
            weightIndex *= -1;
        }
        
        [shaderString appendFormat:@"sampleCoord = cc_FragTexCoord1 + u_sampleStep * %f;", (float)offsetFromCenter];
        [shaderString appendString:@"compare = cc_FragTexCoord1Extents - abs(sampleCoord - cc_FragTexCoord1Center);"];
        [shaderString appendString:@"inBounds = step(0.0, min(compare.x, compare.y));"];
        [shaderString appendFormat:@"sum += texture2D(cc_PreviousPassTexture, sampleCoord) * inBounds * %f;\n", standardGaussianWeights[weightIndex]];
    }
    
    [shaderString appendString:@"\
     return sum * inputValue;\n"];
    
    free(standardGaussianWeights);
    
    CCEffectFunctionInput *input = [[CCEffectFunctionInput alloc] initWithType:@"vec4" name:@"inputValue"];
    return @[[[CCEffectFunction alloc] initWithName:@"blurEffect" body:shaderString inputs:@[input] returnType:@"vec4"]];
}

+ (NSArray *)buildRenderPasses
{
    CCEffectRenderPass *pass0 = [[CCEffectRenderPass alloc] initWithIndex:0];
    pass0.debugLabel = @"CCEffectBlurReference pass 0";
    pass0.blendMode = [CCBlendMode premultipliedAlphaMode];
    pass0.beginBlocks = @[[[CCEffectRenderPassBeginBlockContext alloc] initWithBlock:^(CCEffectRenderPass *pass, CCEffectRenderPassInputs *passInputs){
        
        passInputs.shaderUniforms[CCShaderUniformMainTexture] = passInputs.previousPassTexture;
        passInputs.shaderUniforms[CCShaderUniformPreviousPassTexture] = passInputs.previousPassTexture;
        
        passInputs.shaderUniforms[CCShaderUniformTexCoord1Center] = [NSValue valueWithGLKVector2:passInputs.texCoord1Center];
        passInputs.shaderUniforms[CCShaderUniformTexCoord1Extents] = [NSValue valueWithGLKVector2:passInputs.texCoord1Extents];
        
        GLKVector2 step = GLKVector2Make(1.0 / (passInputs.previousPassTexture.sizeInPixels.width / passInputs.previousPassTexture.contentScale), 0.0);
        passInputs.shaderUniforms[passInputs.uniformTranslationTable[@"u_sampleStep"]] = [NSValue valueWithGLKVector2:step];
        
    }]];
    
    
    CCEffectRenderPass *pass1 = [[CCEffectRenderPass alloc] initWithIndex:1];
    pass1.debugLabel = @"CCEffectBlurReference pass 1";
    pass1.blendMode = [CCBlendMode premultipliedAlphaMode];
    pass1.beginBlocks = @[[[CCEffectRenderPassBeginBlockContext alloc] initWithBlock:^(CCEffectRenderPass *pass, CCEffectRenderPassInputs *passInputs){
        
        passInputs.shaderUniforms[CCShaderUniformPreviousPassTexture] = passInputs.previousPassTexture;
        
        passInputs.shaderUniforms[CCShaderUniformTexCoord1Center] = [NSValue valueWithGLKVector2:GLKVector2Make(0.5f, 0.5f)];
        passInputs.shaderUniforms[CCShaderUniformTexCoord1Extents] = [NSValue valueWithGLKVector2:GLKVector2Make(1.0f, 1.0f)];
        
        GLKVector2 step = GLKVector2Make(0.0, 1.0 / (passInputs.previousPassTexture.sizeInPixels.height / passInputs.previousPassTexture.contentScale));
        passInputs.shaderUniforms[passInputs.uniformTranslationTable[@"u_sampleStep"]] = [NSValue valueWithGLKVector2:step];
        
    }]];
    
    return @[pass0/*, pass1*/];
}

@end


@interface CCEffectBlurReference ()
@property (nonatomic, assign) BOOL shaderDirty;
@end

@implementation CCEffectBlurReference

-(id)init
{
    if((self = [self initWithPixelBlurRadius:2]))
    {
        return self;
    }
    
    return self;
}

-(id)initWithPixelBlurRadius:(NSUInteger)blurRadius
{
    if(self = [super init])
    {
        self.blurRadius = blurRadius;
        
        self.effectImpl = [[CCEffectBlurReferenceImplGL alloc] initWithInterface:self];
        self.debugName = @"CCEffectBlurReference";
        return self;
    }
    
    return self;
}

+(instancetype)effectWithBlurRadius:(NSUInteger)blurRadius
{
    return [[self alloc] initWithPixelBlurRadius:blurRadius];
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
        self.effectImpl = [[CCEffectBlurReferenceImplGL alloc] initWithInterface:self];
        
        _shaderDirty = NO;
        
        result.status = CCEffectPrepareSuccess;
        result.changes = CCEffectPrepareShaderChanged;
    }
    return result;
}

@end
