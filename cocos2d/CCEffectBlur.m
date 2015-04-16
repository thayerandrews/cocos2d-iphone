//
//  CCEffectBlur.m
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

#import "CCEffectBlur.h"
#import "CCEffectBlur_Private.h"
#import "CCEffectShader.h"
#import "CCEffectShaderBuilderGL.h"
#import "CCEffectShaderBuilderMetal.h"
#import "CCEffectUtils.h"
#import "CCEffect_Private.h"
#import "CCRenderer.h"
#import "CCSetup.h"
#import "CCTexture.h"


#pragma mark - CCEffectBlurImplGL

@implementation CCEffectBlurImplGL

-(id)initWithInterface:(CCEffectBlur *)interface
{
    CCEffectBlurParams blurParams = CCEffectUtilsComputeBlurParams(interface.blurRadius, CCEffectBlurOptLinearFiltering);
    
    NSArray *renderPasses = [CCEffectBlurImplGL buildRenderPasses];
    NSArray *shaders =  [CCEffectBlurImplGL buildShadersWithBlurParams:blurParams];

    if((self = [super initWithRenderPasses:renderPasses shaders:shaders]))
    {
        self.interface = interface;
        self.debugName = @"CCEffectBlurImplGL";
        self.stitchFlags = 0;
        return self;
    }
    
    return self;
}

+ (NSArray *)buildShadersWithBlurParams:(CCEffectBlurParams)blurParams
{
    return @[
             [[CCEffectShader alloc] initWithVertexShaderBuilder:[CCEffectBlurImplGL vertexShaderBuilderWithBlurParams:blurParams]
                                           fragmentShaderBuilder:[CCEffectBlurImplGL fragShaderBuilderWithBlurParams:blurParams]]
             ];
}

+ (CCEffectShaderBuilder *)fragShaderBuilderWithBlurParams:(CCEffectBlurParams)blurParams
{
    NSArray *fragFunctions = [CCEffectBlurImplGL buildFragmentFunctionsWithBlurParams:blurParams];
    NSArray *fragTemporaries = @[[CCEffectFunctionTemporary temporaryWithType:@"vec4" name:@"tmp" initializer:CCEffectInitFragColor]];
    NSArray *fragCalls = @[[[CCEffectFunctionCall alloc] initWithFunction:fragFunctions[0] outputName:@"blur" inputs:@{@"inputValue" : @"tmp"}]];
    NSArray *fragUniforms = @[
                              [CCEffectUniform uniform:@"sampler2D" name:CCShaderUniformPreviousPassTexture value:(NSValue *)[CCTexture none]],
                              [CCEffectUniform uniform:@"vec2" name:CCShaderUniformTexCoord1Center value:[NSValue valueWithGLKVector2:GLKVector2Make(0.0f, 0.0f)]],
                              [CCEffectUniform uniform:@"vec2" name:CCShaderUniformTexCoord1Extents value:[NSValue valueWithGLKVector2:GLKVector2Make(0.0f, 0.0f)]],
                              [CCEffectUniform uniform:@"highp vec2" name:@"u_blurDirection" value:[NSValue valueWithGLKVector2:GLKVector2Make(0.0f, 0.0f)]]
                              ];
    
    return [[CCEffectShaderBuilderGL alloc] initWithType:CCEffectShaderBuilderFragment
                                               functions:[[CCEffectShaderBuilderGL defaultFragmentFunctions] arrayByAddingObjectsFromArray:fragFunctions]
                                                   calls:fragCalls
                                             temporaries:fragTemporaries
                                                uniforms:fragUniforms
                                                varyings:[CCEffectBlurImplGL varyingsWithBlurParams:blurParams]];
}

+ (NSArray *)buildFragmentFunctionsWithBlurParams:(CCEffectBlurParams)blurParams
{
    GLfloat* standardGaussianWeights = CCEffectUtilsComputeGaussianWeightsWithBlurParams(blurParams);
    
    NSMutableString *shaderString = [[NSMutableString alloc] init];
    
    // Header
    [shaderString appendFormat:@"\
     lowp vec4 sum = vec4(0.0);\n\
     vec2 blurCoords;\
     "];
    
    // Inner texture loop
    [shaderString appendFormat:@"sum += CCEffectSampleWithBounds(v_blurCoordinates[0], cc_FragTexCoord1Center, cc_FragTexCoord1Extents, cc_PreviousPassTexture) * %f;\n", (blurParams.trueRadius == 0) ? 1.0 : standardGaussianWeights[0]];
    
    for (NSUInteger currentBlurCoordinateIndex = 0; currentBlurCoordinateIndex < blurParams.numberOfOptimizedOffsets; currentBlurCoordinateIndex++)
    {
        GLfloat firstWeight = standardGaussianWeights[currentBlurCoordinateIndex * 2 + 1];
        GLfloat secondWeight = standardGaussianWeights[currentBlurCoordinateIndex * 2 + 2];
        GLfloat optimizedWeight = firstWeight + secondWeight;
        
        [shaderString appendFormat:@"blurCoords = v_blurCoordinates[%lu];", (unsigned long)((currentBlurCoordinateIndex * 2) + 1)];
        [shaderString appendFormat:@"sum += CCEffectSampleWithBounds(blurCoords, cc_FragTexCoord1Center, cc_FragTexCoord1Extents, cc_PreviousPassTexture) * %f;\n", optimizedWeight];
        
        [shaderString appendFormat:@"blurCoords = v_blurCoordinates[%lu];", (unsigned long)((currentBlurCoordinateIndex * 2) + 2)];
        [shaderString appendFormat:@"sum += CCEffectSampleWithBounds(blurCoords, cc_FragTexCoord1Center, cc_FragTexCoord1Extents, cc_PreviousPassTexture) * %f;\n", optimizedWeight];
    }
    
    // If the number of required samples exceeds the amount we can pass in via varyings, we have to do dependent texture reads in the fragment shader
    if (blurParams.trueNumberOfOptimizedOffsets > blurParams.numberOfOptimizedOffsets)
    {
        [shaderString appendString:@"highp vec2 singleStepOffset = u_blurDirection;\n"];
        
        for (NSUInteger currentOverlowTextureRead = blurParams.numberOfOptimizedOffsets; currentOverlowTextureRead < blurParams.trueNumberOfOptimizedOffsets; currentOverlowTextureRead++)
        {
            GLfloat firstWeight = standardGaussianWeights[currentOverlowTextureRead * 2 + 1];
            GLfloat secondWeight = standardGaussianWeights[currentOverlowTextureRead * 2 + 2];
            
            GLfloat optimizedWeight = firstWeight + secondWeight;
            GLfloat optimizedOffset = (firstWeight * (currentOverlowTextureRead * 2 + 1) + secondWeight * (currentOverlowTextureRead * 2 + 2)) / optimizedWeight;

            [shaderString appendFormat:@"blurCoords = v_blurCoordinates[0] + singleStepOffset * %f;", optimizedOffset];
            [shaderString appendFormat:@"sum += CCEffectSampleWithBounds(blurCoords, cc_FragTexCoord1Center, cc_FragTexCoord1Extents, cc_PreviousPassTexture) * %f;\n", optimizedWeight];

            [shaderString appendFormat:@"blurCoords = v_blurCoordinates[0] - singleStepOffset * %f;", optimizedOffset];
            [shaderString appendFormat:@"sum += CCEffectSampleWithBounds(blurCoords, cc_FragTexCoord1Center, cc_FragTexCoord1Extents, cc_PreviousPassTexture) * %f;\n", optimizedWeight];
        }
    }
    
    [shaderString appendString:@"\
     return sum * inputValue;\n"];

    free(standardGaussianWeights);
    
    CCEffectFunctionInput *input = [[CCEffectFunctionInput alloc] initWithType:@"vec4" name:@"inputValue"];
    return @[[[CCEffectFunction alloc] initWithName:@"blurEffect" body:shaderString inputs:@[input] returnType:@"vec4"]];
}

+ (CCEffectShaderBuilder *)vertexShaderBuilderWithBlurParams:(CCEffectBlurParams)blurParams
{
    unsigned long count = (unsigned long)(1 + (blurParams.numberOfOptimizedOffsets * 2));
    NSArray *varyings = @[
                          [CCEffectVarying varying:@"vec2" name:@"v_blurCoordinates" count:count]
                          ];
    
    NSArray *vertFunctions = [CCEffectBlurImplGL buildVertexFunctionsWithBlurParams:blurParams];
    NSArray *vertCalls = @[[[CCEffectFunctionCall alloc] initWithFunction:vertFunctions[0] outputName:@"blur" inputs:nil]];
    NSArray *vertUniforms = @[
                              [CCEffectUniform uniform:@"highp vec2" name:@"u_blurDirection" value:[NSValue valueWithGLKVector2:GLKVector2Make(0.0f, 0.0f)]]
                              ];
    
    return [[CCEffectShaderBuilderGL alloc] initWithType:CCEffectShaderBuilderVertex
                                               functions:vertFunctions
                                                   calls:vertCalls
                                             temporaries:nil
                                                uniforms:vertUniforms
                                                varyings:[CCEffectBlurImplGL varyingsWithBlurParams:blurParams]];
}

+ (NSArray *)buildVertexFunctionsWithBlurParams:(CCEffectBlurParams)blurParams
{
    GLfloat* standardGaussianWeights = CCEffectUtilsComputeGaussianWeightsWithBlurParams(blurParams);
    
    // From these weights we calculate the offsets to read interpolated values from
    GLfloat* optimizedGaussianOffsets = calloc(blurParams.numberOfOptimizedOffsets, sizeof(GLfloat));
    
    for (NSUInteger currentOptimizedOffset = 0; currentOptimizedOffset < blurParams.numberOfOptimizedOffsets; currentOptimizedOffset++)
    {
        GLfloat firstWeight = standardGaussianWeights[currentOptimizedOffset*2 + 1];
        GLfloat secondWeight = standardGaussianWeights[currentOptimizedOffset*2 + 2];
        
        GLfloat optimizedWeight = firstWeight + secondWeight;
        
        optimizedGaussianOffsets[currentOptimizedOffset] = (firstWeight * (currentOptimizedOffset*2 + 1) + secondWeight * (currentOptimizedOffset*2 + 2)) / optimizedWeight;
    }
    
    NSMutableString *shaderString = [[NSMutableString alloc] init];

    [shaderString appendString:@"\
     \n\
     vec2 singleStepOffset = u_blurDirection;\n"];
    
    // Inner offset loop
    [shaderString appendString:@"v_blurCoordinates[0] = cc_TexCoord1.xy;\n"];
    for (NSUInteger currentOptimizedOffset = 0; currentOptimizedOffset < blurParams.numberOfOptimizedOffsets; currentOptimizedOffset++)
    {
        [shaderString appendFormat:@"\
         v_blurCoordinates[%lu] = cc_TexCoord1.xy + singleStepOffset * %f;\n\
         v_blurCoordinates[%lu] = cc_TexCoord1.xy - singleStepOffset * %f;\n", (unsigned long)((currentOptimizedOffset * 2) + 1), optimizedGaussianOffsets[currentOptimizedOffset], (unsigned long)((currentOptimizedOffset * 2) + 2), optimizedGaussianOffsets[currentOptimizedOffset]];
    }
    
    [shaderString appendString:@"return cc_Position;\n"];

    free(optimizedGaussianOffsets);
    free(standardGaussianWeights);

    CCEffectFunction* vertexFunction = [[CCEffectFunction alloc] initWithName:@"blurEffect" body:shaderString inputs:nil returnType:@"vec4"];
    return @[vertexFunction];
}


+ (NSArray *)varyingsWithBlurParams:(CCEffectBlurParams)blurParams
{
    unsigned long count = (unsigned long)(1 + (blurParams.numberOfOptimizedOffsets * 2));
    return @[
             [CCEffectVarying varying:@"vec2" name:@"v_blurCoordinates" count:count]
             ];
}

+ (NSArray *)buildRenderPasses
{
    // optmized approach based on linear sampling - http://rastergrid.com/blog/2010/09/efficient-gaussian-blur-with-linear-sampling/ and GPUImage - https://github.com/BradLarson/GPUImage
    // pass 0: blurs (horizontal) texture[0] and outputs blurmap to texture[1]
    // pass 1: blurs (vertical) texture[1] and outputs to texture[2]

    CCEffectRenderPass *pass0 = [[CCEffectRenderPass alloc] initWithIndex:0];
    pass0.debugLabel = @"CCEffectBlur pass 0";
    pass0.blendMode = [CCBlendMode premultipliedAlphaMode];
    pass0.beginBlocks = @[[[CCEffectRenderPassBeginBlockContext alloc] initWithBlock:^(CCEffectRenderPass *pass, CCEffectRenderPassInputs *passInputs){

        passInputs.shaderUniforms[CCShaderUniformMainTexture] = passInputs.previousPassTexture;
        passInputs.shaderUniforms[CCShaderUniformPreviousPassTexture] = passInputs.previousPassTexture;
        
        passInputs.shaderUniforms[CCShaderUniformTexCoord1Center] = [NSValue valueWithGLKVector2:passInputs.texCoord1Center];
        passInputs.shaderUniforms[CCShaderUniformTexCoord1Extents] = [NSValue valueWithGLKVector2:passInputs.texCoord1Extents];
        
        GLKVector2 dur = GLKVector2Make(1.0 / (passInputs.previousPassTexture.sizeInPixels.width / passInputs.previousPassTexture.contentScale), 0.0);
        passInputs.shaderUniforms[passInputs.uniformTranslationTable[@"u_blurDirection"]] = [NSValue valueWithGLKVector2:dur];
        
    }]];

    
    CCEffectRenderPass *pass1 = [[CCEffectRenderPass alloc] initWithIndex:1];
    pass1.debugLabel = @"CCEffectBlur pass 1";
    pass1.blendMode = [CCBlendMode premultipliedAlphaMode];
    pass1.beginBlocks = @[[[CCEffectRenderPassBeginBlockContext alloc] initWithBlock:^(CCEffectRenderPass *pass, CCEffectRenderPassInputs *passInputs){

        passInputs.shaderUniforms[CCShaderUniformPreviousPassTexture] = passInputs.previousPassTexture;
        
        passInputs.shaderUniforms[CCShaderUniformTexCoord1Center] = [NSValue valueWithGLKVector2:GLKVector2Make(0.5f, 0.5f)];
        passInputs.shaderUniforms[CCShaderUniformTexCoord1Extents] = [NSValue valueWithGLKVector2:GLKVector2Make(1.0f, 1.0f)];
        
        GLKVector2 dur = GLKVector2Make(0.0, 1.0 / (passInputs.previousPassTexture.sizeInPixels.height / passInputs.previousPassTexture.contentScale));
        passInputs.shaderUniforms[passInputs.uniformTranslationTable[@"u_blurDirection"]] = [NSValue valueWithGLKVector2:dur];
        
    }]];
    
    return @[pass0, pass1];
}

@end


#pragma mark - CCEffectBlurImplMetal

@interface CCEffectBlurImplMetal : CCEffectImpl
@property (nonatomic, weak) CCEffectBlur *interface;
@end

@implementation CCEffectBlurImplMetal

-(id)initWithInterface:(CCEffectBlur *)interface
{
    CCEffectBlurParams blurParams = CCEffectUtilsComputeBlurParams(interface.blurRadius, CCEffectBlurOptNone);

    NSArray *renderPasses = [CCEffectBlurImplMetal buildRenderPasses];
    NSArray *shaders =  [CCEffectBlurImplMetal buildShadersWithBlurParams:blurParams];
    
    if((self = [super initWithRenderPasses:renderPasses shaders:shaders]))
    {
        self.interface = interface;
        self.debugName = @"CCEffectBlurImplGL";
        self.stitchFlags = 0;
        return self;
    }
    
    return self;
}

+ (NSArray *)buildStructDeclarationsWithBlurParams:(CCEffectBlurParams)blurParams
{
    NSString* structBlurFragData =
    @"float4 position [[position]];\n"
    @"float2 texCoord1;\n"
    @"float2 texCoord2;\n"
    @"half4  color;\n";

    for (int i = 0; i < 2 * blurParams.numberOfOptimizedOffsets; i++)
    {
        structBlurFragData = [structBlurFragData stringByAppendingFormat:@"float2 blurCoordinates%d;\n", i+1];
    }

    return @[
             [[CCEffectShaderStructDeclaration alloc] initWithName:@"CCEffectBlurFragData" body:structBlurFragData],
             ];
}

+ (NSArray *)buildShadersWithBlurParams:(CCEffectBlurParams)blurParams
{
    CCEffectShaderBuilder *vertexShaderBuiler = [CCEffectBlurImplMetal vertexShaderBuilderWithBlurParams:blurParams];
    CCEffectShaderBuilder *fragmentShaderBuiler = [CCEffectBlurImplMetal fragmentShaderBuilderWithBlurParams:blurParams];
    return @[[[CCEffectShader alloc] initWithVertexShaderBuilder:vertexShaderBuiler fragmentShaderBuilder:fragmentShaderBuiler]];
}

+ (CCEffectShaderBuilder *)fragmentShaderBuilderWithBlurParams:(CCEffectBlurParams)blurParams
{
    NSArray *functions = [CCEffectBlurImplMetal buildFragmentFunctionsWithBlurParams:blurParams];
    NSArray *temporaries = @[[CCEffectFunctionTemporary temporaryWithType:@"half4" name:@"tmp" initializer:CCEffectInitFragColor]];
    NSArray *calls = @[[[CCEffectFunctionCall alloc] initWithFunction:functions[1] outputName:@"blurredResult" inputs:@{@"cc_FragIn" : @"cc_FragIn",
                                                                                                                        @"cc_PreviousPassTexture" : @"cc_PreviousPassTexture",
                                                                                                                        @"cc_PreviousPassTextureSampler" : @"cc_PreviousPassTextureSampler",
                                                                                                                        @"cc_FragTexCoordDimensions" : @"cc_FragTexCoordDimensions",
                                                                                                                        @"blurDirection" : @"blurDirection",
                                                                                                                        @"inputValue" : @"tmp"
                                                                                                                        }]];
    
    
    NSArray *arguments = @[
                           [[CCEffectShaderArgument alloc] initWithType:@"const CCEffectBlurFragData" name:CCShaderArgumentFragIn qualifier:CCEffectShaderArgumentStageIn],
                           [[CCEffectShaderArgument alloc] initWithType:@"texture2d<half>" name:CCShaderUniformPreviousPassTexture qualifier:CCEffectShaderArgumentTexture],
                           [[CCEffectShaderArgument alloc] initWithType:@"sampler" name:CCShaderUniformPreviousPassTextureSampler qualifier:CCEffectShaderArgumentSampler],
                           [[CCEffectShaderArgument alloc] initWithType:@"const device CCEffectTexCoordDimensions*" name:CCShaderArgumentTexCoordDimensions qualifier:CCEffectShaderArgumentBuffer],
                           [[CCEffectShaderArgument alloc] initWithType:@"const device float2&" name:@"blurDirection" qualifier:CCEffectShaderArgumentBuffer]
                           ];
    
    NSArray *structs = [CCEffectBlurImplMetal buildStructDeclarationsWithBlurParams:blurParams];

    return [[CCEffectShaderBuilderMetal alloc] initWithType:CCEffectShaderBuilderFragment
                                                  functions:functions
                                                      calls:calls
                                                temporaries:temporaries
                                                  arguments:arguments
                                                    structs:[[CCEffectShaderBuilderMetal defaultStructDeclarations] arrayByAddingObjectsFromArray:structs]];
}

+ (NSArray *)buildFragmentFunctionsWithBlurParams:(CCEffectBlurParams)blurParams
{
    NSArray *sampleWithBoundsInputs = @[
                                        [[CCEffectFunctionInput alloc] initWithType:@"float2" name:@"texCoord"],
                                        [[CCEffectFunctionInput alloc] initWithType:@"float2" name:@"texCoordCenter"],
                                        [[CCEffectFunctionInput alloc] initWithType:@"float2" name:@"texCoordExtents"],
                                        [[CCEffectFunctionInput alloc] initWithType:@"texture2d<half>" name:@"inputTexture"],
                                        [[CCEffectFunctionInput alloc] initWithType:@"sampler" name:@"inputSampler"]
                                        ];
    NSString *sampleWithBoundsBody = CC_GLSL(
                                             float2 compare = texCoordExtents - abs(texCoord - texCoordCenter);
                                             float inBounds = step(0.0, min(compare.x, compare.y));
                                             return inputTexture.sample(inputSampler, texCoord) * inBounds;
                                             );
    CCEffectFunction* sampleWithBoundsFunction = [[CCEffectFunction alloc] initWithName:@"sampleWithBounds" body:sampleWithBoundsBody inputs:sampleWithBoundsInputs returnType:@"half4"];

    
    
    GLfloat* standardGaussianWeights = CCEffectUtilsComputeGaussianWeightsWithBlurParams(blurParams);
    
    NSMutableString *shaderString = [[NSMutableString alloc] init];
    
    // Header
    [shaderString appendFormat:@"\
     half4 sum = half4(0);\n\
     "];
    
    // Inner texture loop
    [shaderString appendFormat:@"sum += sampleWithBounds(cc_FragIn.texCoord1, cc_FragTexCoordDimensions->texCoord1Center, cc_FragTexCoordDimensions->texCoord1Extents, cc_PreviousPassTexture, cc_PreviousPassTextureSampler) * %f;\n", standardGaussianWeights[0]];
    
    for (NSUInteger currentBlurCoordinateIndex = 0; currentBlurCoordinateIndex < blurParams.numberOfOptimizedOffsets; currentBlurCoordinateIndex++)
    {
        [shaderString appendFormat:@"sum += sampleWithBounds(cc_FragIn.blurCoordinates%lu, cc_FragTexCoordDimensions->texCoord1Center, cc_FragTexCoordDimensions->texCoord1Extents, cc_PreviousPassTexture, cc_PreviousPassTextureSampler) * %f;\n", (unsigned long)((currentBlurCoordinateIndex * 2) + 1), standardGaussianWeights[currentBlurCoordinateIndex+1]];
        [shaderString appendFormat:@"sum += sampleWithBounds(cc_FragIn.blurCoordinates%lu, cc_FragTexCoordDimensions->texCoord1Center, cc_FragTexCoordDimensions->texCoord1Extents, cc_PreviousPassTexture, cc_PreviousPassTextureSampler) * %f;\n", (unsigned long)((currentBlurCoordinateIndex * 2) + 2), standardGaussianWeights[currentBlurCoordinateIndex+1]];
    }
    
    // If the number of required samples exceeds the amount we can pass in via varyings, we have to do dependent texture reads in the fragment shader
    if (blurParams.trueNumberOfOptimizedOffsets > blurParams.numberOfOptimizedOffsets)
    {
        [shaderString appendString:@"float2 singleStepOffset = blurDirection;\n"];
        
        for (NSUInteger currentOverlowTextureRead = blurParams.numberOfOptimizedOffsets; currentOverlowTextureRead < blurParams.trueNumberOfOptimizedOffsets; currentOverlowTextureRead++)
        {
            [shaderString appendFormat:@"sum += sampleWithBounds(cc_FragIn.texCoord1 + singleStepOffset * %f, cc_FragTexCoordDimensions->texCoord1Center, cc_FragTexCoordDimensions->texCoord1Extents, cc_PreviousPassTexture, cc_PreviousPassTextureSampler) * %f;\n", (float)(currentOverlowTextureRead+1), standardGaussianWeights[currentOverlowTextureRead+1]];
            [shaderString appendFormat:@"sum += sampleWithBounds(cc_FragIn.texCoord1 + singleStepOffset * %f, cc_FragTexCoordDimensions->texCoord1Center, cc_FragTexCoordDimensions->texCoord1Extents, cc_PreviousPassTexture, cc_PreviousPassTextureSampler) * %f;\n", -((float)(currentOverlowTextureRead+1)), standardGaussianWeights[currentOverlowTextureRead+1]];
        }
    }
    
    [shaderString appendString:@"\
     return sum * inputValue;\n"];
    
    free(standardGaussianWeights);
    
    
    NSArray *inputs = @[
                        [[CCEffectFunctionInput alloc] initWithType:@"const CCEffectBlurFragData" name:CCShaderArgumentFragIn],
                        [[CCEffectFunctionInput alloc] initWithType:@"texture2d<half>" name:CCShaderUniformPreviousPassTexture],
                        [[CCEffectFunctionInput alloc] initWithType:@"sampler" name:CCShaderUniformPreviousPassTextureSampler],
                        [[CCEffectFunctionInput alloc] initWithType:@"const device CCEffectTexCoordDimensions*" name:CCShaderArgumentTexCoordDimensions],
                        [[CCEffectFunctionInput alloc] initWithType:@"const device float2&" name:@"blurDirection"],
                        [[CCEffectFunctionInput alloc] initWithType:@"half4" name:@"inputValue"]
                        ];
    
    CCEffectFunction *blurEffectFunction = [[CCEffectFunction alloc] initWithName:@"blurEffect" body:shaderString inputs:inputs returnType:@"half4"];
    return @[sampleWithBoundsFunction, blurEffectFunction];
}

+ (CCEffectShaderBuilder *)vertexShaderBuilderWithBlurParams:(CCEffectBlurParams)blurParams
{
    NSArray *functions = [CCEffectBlurImplMetal buildVertexFunctionsWithBlurParams:blurParams];
    NSArray *temporaries = @[[CCEffectFunctionTemporary temporaryWithType:@"CCEffectBlurFragData" name:@"tmp" initializer:CCEffectInitVertexAttributes]];
    NSArray *calls = @[[[CCEffectFunctionCall alloc] initWithFunction:functions[0] outputName:@"blurResult" inputs:@{@"fragData" : @"tmp",
                                                                                                                     @"blurDirection" : @"blurDirection" }]];
    
    NSArray *arguments = @[
                           [[CCEffectShaderArgument alloc] initWithType:@"const device CCVertex*" name:CCShaderArgumentVertexAtttributes qualifier:CCEffectShaderArgumentBuffer],
                           [[CCEffectShaderArgument alloc] initWithType:@"unsigned int" name:CCShaderArgumentVertexId qualifier:CCEffectShaderArgumentVertexId],
                           [[CCEffectShaderArgument alloc] initWithType:@"const device float2&" name:@"blurDirection" qualifier:CCEffectShaderArgumentBuffer]
                           ];
    
    NSArray *structs = [CCEffectBlurImplMetal buildStructDeclarationsWithBlurParams:blurParams];
    
    return [[CCEffectShaderBuilderMetal alloc] initWithType:CCEffectShaderBuilderVertex
                                                  functions:functions
                                                      calls:calls
                                                temporaries:temporaries
                                                  arguments:arguments
                                                    structs:[[CCEffectShaderBuilderMetal defaultStructDeclarations] arrayByAddingObjectsFromArray:structs]];

    
    
    return nil;
}

+ (NSArray *)buildVertexFunctionsWithBlurParams:(CCEffectBlurParams)blurParams
{
    GLfloat* standardGaussianWeights = CCEffectUtilsComputeGaussianWeightsWithBlurParams(blurParams);
    
    NSMutableString *shaderString = [[NSMutableString alloc] init];
    [shaderString appendString:@"float2 singleStepOffset = blurDirection;\n"];
    
    // Inner offset loop
    for (NSUInteger currentOptimizedOffset = 0; currentOptimizedOffset < blurParams.numberOfOptimizedOffsets; currentOptimizedOffset++)
    {
        [shaderString appendFormat:@"\
         fragData.blurCoordinates%lu = fragData.texCoord1 + singleStepOffset * %f;\n\
         fragData.blurCoordinates%lu = fragData.texCoord1 - singleStepOffset * %f;\n", (unsigned long)((currentOptimizedOffset * 2) + 1), (float)(currentOptimizedOffset + 1), (unsigned long)((currentOptimizedOffset * 2) + 2), (float)(currentOptimizedOffset + 1)];
    }
    
    [shaderString appendString:@"return fragData;\n"];
    
    free(standardGaussianWeights);
    
    NSArray *inputs = @[
                        [[CCEffectFunctionInput alloc] initWithType:@"CCEffectBlurFragData" name:@"fragData"],
                        [[CCEffectFunctionInput alloc] initWithType:@"const device float2&" name:@"blurDirection"]
                        ];
    
    return @[[[CCEffectFunction alloc] initWithName:@"blurEffect" body:shaderString inputs:inputs returnType:@"CCEffectBlurFragData"]];
}

+ (NSArray *)buildRenderPasses
{
    // optmized approach based on linear sampling - http://rastergrid.com/blog/2010/09/efficient-gaussian-blur-with-linear-sampling/ and GPUImage - https://github.com/BradLarson/GPUImage
    // pass 0: blurs (horizontal) texture[0] and outputs blurmap to texture[1]
    // pass 1: blurs (vertical) texture[1] and outputs to texture[2]
    
    CCEffectRenderPass *pass0 = [[CCEffectRenderPass alloc] initWithIndex:0];
    pass0.debugLabel = @"CCEffectBlur pass 0";
    pass0.blendMode = [CCBlendMode premultipliedAlphaMode];
    pass0.beginBlocks = @[[[CCEffectRenderPassBeginBlockContext alloc] initWithBlock:^(CCEffectRenderPass *pass, CCEffectRenderPassInputs *passInputs){
        
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
    
    
    CCEffectRenderPass *pass1 = [[CCEffectRenderPass alloc] initWithIndex:1];
    pass1.debugLabel = @"CCEffectBlur pass 1";
    pass1.blendMode = [CCBlendMode premultipliedAlphaMode];
    pass1.beginBlocks = @[[[CCEffectRenderPassBeginBlockContext alloc] initWithBlock:^(CCEffectRenderPass *pass, CCEffectRenderPassInputs *passInputs){

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
    
    return @[pass0, pass1];
}

@end


#pragma mark - CCEffectBlur

@implementation CCEffectBlur
{
    BOOL _shaderDirty;
}

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
        
        if([CCSetup sharedSetup].graphicsAPI == CCGraphicsAPIMetal)
        {
            self.effectImpl = [[CCEffectBlurImplMetal alloc] initWithInterface:self];
        }
        else
        {
            self.effectImpl = [[CCEffectBlurImplGL alloc] initWithInterface:self];
        }
        self.debugName = @"CCEffectBlur";
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
        if([CCSetup sharedSetup].graphicsAPI == CCGraphicsAPIMetal)
        {
            self.effectImpl = [[CCEffectBlurImplMetal alloc] initWithInterface:self];
        }
        else
        {
            self.effectImpl = [[CCEffectBlurImplGL alloc] initWithInterface:self];
        }
        _shaderDirty = NO;
        
        result.status = CCEffectPrepareSuccess;
        result.changes = CCEffectPrepareShaderChanged;
    }
    return result;
}

@end
