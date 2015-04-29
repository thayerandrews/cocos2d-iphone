//
//  CCEffectLighting.m
//  cocos2d-ios
//
//  Created by Thayer J Andrews on 10/2/14.
//
//

#import "CCEffectLighting.h"
#import "CCEffectShader.h"
#import "CCEffectShaderBuilderGL.h"
#import "CCEffectShaderBuilderMetal.h"

#import "CCDirector.h"
#import "CCEffectUtils.h"
#import "CCLightCollection.h"
#import "CCLightGroups.h"
#import "CCLightNode.h"
#import "CCRenderer.h"
#import "CCScene.h"
#import "CCSetup.h"
#import "CCSpriteFrame.h"
#import "CCTexture.h"

#import "CCEffect_Private.h"
#import "CCSprite_Private.h"
#import "CCNode_Private.h"


typedef struct _CCLightKey
{
    NSUInteger pointLightMask;
    NSUInteger directionalLightMask;

} CCLightKey;

static const NSUInteger CCEffectLightingMaxLightCount = 8;

static CCLightKey CCLightKeyMake(NSArray *lights);
static BOOL CCLightKeyCompare(CCLightKey a, CCLightKey b);
static float conditionShininess(float shininess);


@interface CCEffectLighting ()
@property (nonatomic, strong) NSNumber *conditionedShininess;
@property (nonatomic, assign) CCLightGroupMask groupMask;
@property (nonatomic, assign) BOOL groupMaskDirty;
@property (nonatomic, copy) NSArray *closestLights;
@property (nonatomic, assign) CCLightKey lightKey;
@property (nonatomic, readonly) BOOL needsSpecular;
@property (nonatomic, readonly) BOOL needsNormalMap;
@property (nonatomic, assign) BOOL shaderHasSpecular;
@property (nonatomic, assign) BOOL shaderHasNormalMap;

@end


#pragma mark - CCEffectLightingImplGL

@interface CCEffectLightingImplGL : CCEffectImpl
@property (nonatomic, weak) CCEffectLighting *interface;
@end


@implementation CCEffectLightingImplGL

-(id)initWithInterface:(CCEffectLighting *)interface
{
    NSMutableArray *fragUniforms = [[NSMutableArray alloc] initWithArray:@[
                                                                           [CCEffectUniform uniform:@"sampler2D" name:CCShaderUniformPreviousPassTexture value:(NSValue *)[CCTexture none]],
                                                                           [CCEffectUniform uniform:@"vec2" name:CCShaderUniformTexCoord1Center value:[NSValue valueWithGLKVector2:GLKVector2Make(0.0f, 0.0f)]],
                                                                           [CCEffectUniform uniform:@"vec2" name:CCShaderUniformTexCoord1Extents value:[NSValue valueWithGLKVector2:GLKVector2Make(0.0f, 0.0f)]],
                                                                           [CCEffectUniform uniform:@"vec4" name:@"u_globalAmbientColor" value:[NSValue valueWithGLKVector4:GLKVector4Make(1.0f, 1.0f, 1.0f, 1.0f)]],
                                                                           [CCEffectUniform uniform:@"vec2" name:@"u_worldSpaceTangent" value:[NSValue valueWithGLKVector2:GLKVector2Make(1.0f, 0.0f)]],
                                                                           [CCEffectUniform uniform:@"vec2" name:@"u_worldSpaceBinormal" value:[NSValue valueWithGLKVector2:GLKVector2Make(0.0f, 1.0f)]]
                                                                           ]];
    NSMutableArray *vertUniforms = [[NSMutableArray alloc] initWithArray:@[
                                                                           [CCEffectUniform uniform:@"mat4" name:@"u_ndcToWorld" value:[NSValue valueWithGLKMatrix4:GLKMatrix4Identity]]
                                                                           ]];
    NSMutableArray *varyings = [[NSMutableArray alloc] init];
    
    for (NSUInteger lightIndex = 0; lightIndex < interface.closestLights.count; lightIndex++)
    {
        CCLightNode *light = interface.closestLights[lightIndex];
        
        [vertUniforms addObject:[CCEffectUniform uniform:@"vec3" name:[NSString stringWithFormat:@"u_lightVector%lu", (unsigned long)lightIndex] value:[NSValue valueWithGLKVector3:GLKVector3Make(0.0f, 0.0f, 0.0f)]]];
        [fragUniforms addObject:[CCEffectUniform uniform:@"vec4" name:[NSString stringWithFormat:@"u_lightColor%lu", (unsigned long)lightIndex] value:[NSValue valueWithGLKVector4:GLKVector4Make(1.0f, 1.0f, 1.0f, 1.0f)]]];
        if (interface.needsSpecular)
        {
            [fragUniforms addObject:[CCEffectUniform uniform:@"vec4" name:[NSString stringWithFormat:@"u_lightSpecularColor%lu", (unsigned long)lightIndex] value:[NSValue valueWithGLKVector4:GLKVector4Make(1.0f, 1.0f, 1.0f, 1.0f)]]];
        }
        
        if (light.type != CCLightDirectional)
        {
            [fragUniforms addObject:[CCEffectUniform uniform:@"vec4" name:[NSString stringWithFormat:@"u_lightFalloff%lu", (unsigned long)lightIndex] value:[NSValue valueWithGLKVector4:GLKVector4Make(-1.0f, 1.0f, -1.0f, 1.0f)]]];
        }
        
        [varyings addObject:[CCEffectVarying varying:@"highp vec3" name:[NSString stringWithFormat:@"v_worldSpaceLightDir%lu", (unsigned long)lightIndex]]];
    }
    
    if (interface.needsSpecular)
    {
        [fragUniforms addObject:[CCEffectUniform uniform:@"float" name:@"u_specularExponent" value:[NSNumber numberWithFloat:5.0f]]];
        [fragUniforms addObject:[CCEffectUniform uniform:@"vec4" name:@"u_specularColor" value:[NSValue valueWithGLKVector4:GLKVector4Make(1.0f, 1.0f, 1.0f, 1.0f)]]];
    }
    
    NSArray *fragFunctions = [CCEffectLightingImplGL buildFragmentFunctionsWithLights:interface.closestLights normalMap:interface.needsNormalMap specular:interface.needsSpecular];
    NSArray *fragTemporaries = @[[CCEffectFunctionTemporary temporaryWithType:@"vec4" name:@"tmp" initializer:CCEffectInitPreviousPass]];
    NSArray *fragCalls = @[[[CCEffectFunctionCall alloc] initWithFunction:fragFunctions[0] outputName:@"lighting" inputs:@{@"inputValue" : @"tmp"}]];
    
    CCEffectShaderBuilder *fragShaderBuilder = [[CCEffectShaderBuilderGL alloc] initWithType:CCEffectShaderBuilderFragment
                                                                                   functions:fragFunctions
                                                                                       calls:fragCalls
                                                                                 temporaries:fragTemporaries
                                                                                    uniforms:fragUniforms
                                                                                    varyings:varyings];
    
    
    NSArray *vertFunctions = [CCEffectLightingImplGL buildVertexFunctionsWithLights:interface.closestLights];
    NSArray *vertCalls = @[[[CCEffectFunctionCall alloc] initWithFunction:vertFunctions[0] outputName:@"lighting" inputs:nil]];
    
    CCEffectShaderBuilder *vertShaderBuilder = [[CCEffectShaderBuilderGL alloc] initWithType:CCEffectShaderBuilderVertex
                                                                                   functions:vertFunctions
                                                                                       calls:vertCalls
                                                                                 temporaries:nil
                                                                                    uniforms:vertUniforms
                                                                                    varyings:varyings];
    

    NSArray *shaders = @[[[CCEffectShader alloc] initWithVertexShaderBuilder:vertShaderBuilder fragmentShaderBuilder:fragShaderBuilder]];
    NSArray *renderPasses = [CCEffectLightingImplGL buildRenderPassesWithInterface:interface];
    
    if((self = [super initWithRenderPassDescriptors:renderPasses shaders:shaders]))
    {
        self.interface = interface;
        self.debugName = @"CCEffectLightingImplGL";
    }
    return self;
}

+(NSArray *)buildFragmentFunctionsWithLights:(NSArray*)lights normalMap:(BOOL)needsNormalMap specular:(BOOL)needsSpecular
{
    CCEffectFunctionInput *input = [[CCEffectFunctionInput alloc] initWithType:@"vec4" name:@"inputValue"];
    
    NSMutableString *effectBody = [[NSMutableString alloc] init];
    [effectBody appendString:CC_GLSL(
                                     vec3 lightColor;
                                     vec3 lightSpecularColor;
                                     vec3 diffuseSum = u_globalAmbientColor.rgb;
                                     vec3 specularSum = vec3(0,0,0);
                                     
                                     vec3 worldSpaceLightDir;
                                     vec3 halfAngleDir;
                                     
                                     float lightDist;
                                     float falloffTermA;
                                     float falloffTermB;
                                     float falloffSelect;
                                     float falloffTerm;
                                     float diffuseTerm;
                                     float specularTerm;
                                     float composedAlpha = inputValue.a;
                                     )];

    if (needsNormalMap)
    {
        [effectBody appendString:CC_GLSL(
                                         // Index the normal map and expand the color value from [0..1] to [-1..1]
                                         vec4 normalMap = texture2D(cc_NormalMapTexture, cc_FragTexCoord2);
                                         vec3 tangentSpaceNormal = normalize(normalMap.xyz * 2.0 - 1.0);
                                         
                                         // Convert the normal vector from tangent space to world space
                                         vec3 worldSpaceNormal = normalize(vec3(u_worldSpaceTangent, 0.0) * tangentSpaceNormal.x + vec3(u_worldSpaceBinormal, 0.0) * tangentSpaceNormal.y + vec3(0.0, 0.0, tangentSpaceNormal.z));

                                         composedAlpha *= normalMap.a;
                                         )];
    }
    else
    {
        [effectBody appendString:@"vec3 worldSpaceNormal = vec3(0,0,1);\n"];
    }
    
    [effectBody appendString:CC_GLSL(
                                     if (composedAlpha == 0.0)
                                     {
                                         return inputValue;
                                     }
                                     )];
    
    for (NSUInteger lightIndex = 0; lightIndex < lights.count; lightIndex++)
    {
        CCLightNode *light = lights[lightIndex];
        if (light.type == CCLightDirectional)
        {
            [effectBody appendFormat:@"worldSpaceLightDir = v_worldSpaceLightDir%lu.xyz;\n", (unsigned long)lightIndex];
            [effectBody appendFormat:@"lightColor = u_lightColor%lu.rgb;\n", (unsigned long)lightIndex];
            if (needsSpecular)
            {
                [effectBody appendFormat:@"lightSpecularColor = u_lightSpecularColor%lu.rgb;\n", (unsigned long)lightIndex];
            }
        }
        else
        {
            [effectBody appendFormat:@"worldSpaceLightDir = normalize(v_worldSpaceLightDir%lu.xyz);\n", (unsigned long)lightIndex];
            [effectBody appendFormat:@"lightDist = length(v_worldSpaceLightDir%lu.xy);\n", (unsigned long)lightIndex];
            
            [effectBody appendFormat:@"falloffTermA = clamp((lightDist * u_lightFalloff%lu.y + 1.0), 0.0, 1.0);\n", (unsigned long)lightIndex];
            [effectBody appendFormat:@"falloffTermB = clamp((lightDist * u_lightFalloff%lu.z + u_lightFalloff%lu.w), 0.0, 1.0);\n", (unsigned long)lightIndex, (unsigned long)lightIndex];
            [effectBody appendFormat:@"falloffSelect = step(u_lightFalloff%lu.x, lightDist);\n", (unsigned long)lightIndex];
            [effectBody appendFormat:@"falloffTerm = (1.0 - falloffSelect) * falloffTermA + falloffSelect * falloffTermB;\n"];

            [effectBody appendFormat:@"lightColor = u_lightColor%lu.rgb * falloffTerm;\n", (unsigned long)lightIndex];
            if (needsSpecular)
            {
                [effectBody appendFormat:@"lightSpecularColor = u_lightSpecularColor%lu.rgb * falloffTerm;\n", (unsigned long)lightIndex];
            }
        }
        [effectBody appendString:@"diffuseTerm = max(0.0, dot(worldSpaceNormal, worldSpaceLightDir));\n"];
        [effectBody appendString:@"diffuseSum += lightColor * diffuseTerm;\n"];
        
        if (needsSpecular)
        {
            [effectBody appendString:@"halfAngleDir = (2.0 * dot(worldSpaceLightDir, worldSpaceNormal) * worldSpaceNormal - worldSpaceLightDir);\n"];
            [effectBody appendString:@"specularTerm = max(0.0, dot(halfAngleDir, vec3(0,0,1))) * step(0.0, diffuseTerm);\n"];
            [effectBody appendString:@"specularSum += lightSpecularColor * pow(specularTerm, u_specularExponent);\n"];
        }
    }
    [effectBody appendString:@"vec3 resultColor = diffuseSum * inputValue.rgb;\n"];
    if (needsSpecular)
    {
        [effectBody appendString:@"resultColor += specularSum * u_specularColor.rgb * inputValue.a;\n"];
    }
    [effectBody appendString:@"return vec4(resultColor, inputValue.a);\n"];
    
    CCEffectFunction* fragmentFunction = [[CCEffectFunction alloc] initWithName:@"lightingEffectFrag" body:effectBody inputs:@[input] returnType:@"vec4"];
    return @[fragmentFunction];
}

+(NSArray *)buildVertexFunctionsWithLights:(NSArray*)lights
{
    NSMutableString *effectBody = [[NSMutableString alloc] init];
    for (NSUInteger lightIndex = 0; lightIndex < lights.count; lightIndex++)
    {
        CCLightNode *light = lights[lightIndex];
        
        if (light.type == CCLightDirectional)
        {
            [effectBody appendFormat:@"v_worldSpaceLightDir%lu = u_lightVector%lu;", (unsigned long)lightIndex, (unsigned long)lightIndex];
        }
        else
        {
            [effectBody appendFormat:@"v_worldSpaceLightDir%lu = u_lightVector%lu - (u_ndcToWorld * cc_Position).xyz;", (unsigned long)lightIndex, (unsigned long)lightIndex];
        }
    }
    [effectBody appendString:@"return cc_Position;"];
    
    CCEffectFunction *vertexFunction = [[CCEffectFunction alloc] initWithName:@"lightingEffectVtx" body:effectBody inputs:nil returnType:@"vec4"];
    return @[vertexFunction];
}

+(NSArray *)buildRenderPassesWithInterface:(CCEffectLighting *)interface
{
    __weak CCEffectLighting *weakInterface = interface;

    CCEffectRenderPassDescriptor *pass0 = [CCEffectRenderPassDescriptor descriptor];
    pass0.debugLabel = @"CCEffectLighting pass 0";
    pass0.beginBlocks = @[[[CCEffectBeginBlockContext alloc] initWithBlock:^(CCEffectRenderPass *pass, CCEffectRenderPassInputs *passInputs){
        
        passInputs.shaderUniforms[CCShaderUniformMainTexture] = passInputs.previousPassTexture;
        passInputs.shaderUniforms[CCShaderUniformPreviousPassTexture] = passInputs.previousPassTexture;
        passInputs.shaderUniforms[CCShaderUniformTexCoord1Center] = [NSValue valueWithGLKVector2:passInputs.texCoord1Center];
        passInputs.shaderUniforms[CCShaderUniformTexCoord1Extents] = [NSValue valueWithGLKVector2:passInputs.texCoord1Extents];

        GLKMatrix4 nodeLocalToWorld = passInputs.sprite.nodeToWorldMatrix;
        GLKMatrix4 ndcToWorld = GLKMatrix4Multiply(nodeLocalToWorld, passInputs.ndcToNodeLocal);
        
        // Tangent and binormal vectors are the x/y basis vectors from the nodeLocalToWorldMatrix
        GLKVector2 reflectTangent = GLKVector2Normalize(GLKVector2Make(nodeLocalToWorld.m[0], nodeLocalToWorld.m[1]));
        GLKVector2 reflectBinormal = GLKVector2Normalize(GLKVector2Make(nodeLocalToWorld.m[4], nodeLocalToWorld.m[5]));

        passInputs.shaderUniforms[passInputs.uniformTranslationTable[@"u_worldSpaceTangent"]] = [NSValue valueWithGLKVector2:reflectTangent];
        passInputs.shaderUniforms[passInputs.uniformTranslationTable[@"u_worldSpaceBinormal"]] = [NSValue valueWithGLKVector2:reflectBinormal];

        
        // Matrix for converting NDC (normalized device coordinates (aka normalized render target coordinates)
        // to node local coordinates.
        passInputs.shaderUniforms[passInputs.uniformTranslationTable[@"u_ndcToWorld"]] = [NSValue valueWithGLKMatrix4:ndcToWorld];

        for (NSUInteger lightIndex = 0; lightIndex < weakInterface.closestLights.count; lightIndex++)
        {
            CCLightNode *light = weakInterface.closestLights[lightIndex];
            
            // Get the transform from the light's coordinate space to the effect's coordinate space.
            GLKMatrix4 lightNodeToWorld = light.nodeToWorldMatrix;
            
            // Compute the light's position in the effect node's coordinate system.
            GLKVector4 lightVector = GLKVector4Make(0.0f, 0.0f, 0.0f, 0.0f);
            if (light.type == CCLightDirectional)
            {
                lightVector = GLKVector4Normalize(GLKMatrix4MultiplyVector4(lightNodeToWorld, GLKVector4Make(0.0f, 1.0f, light.depth, 0.0f)));
            }
            else
            {
                lightVector = GLKMatrix4MultiplyVector4(lightNodeToWorld, GLKVector4Make(light.anchorPointInPoints.x, light.anchorPointInPoints.y, light.depth, 1.0f));

                float scale0 = GLKVector4Length(GLKMatrix4GetColumn(lightNodeToWorld, 0));
                float scale1 = GLKVector4Length(GLKMatrix4GetColumn(lightNodeToWorld, 1));
                float maxScale = MAX(scale0, scale1);

                float cutoffRadius = light.cutoffRadius * maxScale;

                GLKVector4 falloffTerms = GLKVector4Make(0.0f, 0.0f, 0.0f, 1.0f);
                if (cutoffRadius > 0.0f)
                {
                    float xIntercept = cutoffRadius * light.halfRadius;
                    float r1 = 2.0f * xIntercept;
                    float r2 = cutoffRadius;
                    
                    falloffTerms.x = xIntercept;
                    
                    if (light.halfRadius > 0.0f)
                    {
                        falloffTerms.y = -1.0f / r1;
                    }
                    else
                    {
                        falloffTerms.y = 0.0f;
                    }
                    
                    if (light.halfRadius < 1.0f)
                    {
                        falloffTerms.z = -0.5f / (r2 - xIntercept);
                        falloffTerms.w = 0.5f - xIntercept * falloffTerms.z;
                    }
                    else
                    {
                        falloffTerms.z = 0.0f;
                        falloffTerms.w = 0.0f;
                    }
                }
                
                NSString *lightFalloffLabel = [NSString stringWithFormat:@"u_lightFalloff%lu", (unsigned long)lightIndex];
                passInputs.shaderUniforms[passInputs.uniformTranslationTable[lightFalloffLabel]] = [NSValue valueWithGLKVector4:falloffTerms];
            }
            
            // Compute the real light color based on color and intensity.
            GLKVector4 lightColor = GLKVector4MultiplyScalar(light.color.glkVector4, light.intensity);
            
            NSString *lightColorLabel = [NSString stringWithFormat:@"u_lightColor%lu", (unsigned long)lightIndex];
            passInputs.shaderUniforms[passInputs.uniformTranslationTable[lightColorLabel]] = [NSValue valueWithGLKVector4:lightColor];

            NSString *lightVectorLabel = [NSString stringWithFormat:@"u_lightVector%lu", (unsigned long)lightIndex];
            passInputs.shaderUniforms[passInputs.uniformTranslationTable[lightVectorLabel]] = [NSValue valueWithGLKVector3:GLKVector3Make(lightVector.x, lightVector.y, lightVector.z)];

            if (weakInterface.needsSpecular)
            {
                GLKVector4 lightSpecularColor = GLKVector4MultiplyScalar(light.specularColor.glkVector4, light.specularIntensity);

                NSString *lightSpecularColorLabel = [NSString stringWithFormat:@"u_lightSpecularColor%lu", (unsigned long)lightIndex];
                passInputs.shaderUniforms[passInputs.uniformTranslationTable[lightSpecularColorLabel]] = [NSValue valueWithGLKVector4:lightSpecularColor];
            }
        }

        CCColor *ambientColor = [CCEffectUtilsGetNodeScene(passInputs.sprite).lights findAmbientSumForLightsWithMask:weakInterface.groupMask];
        passInputs.shaderUniforms[passInputs.uniformTranslationTable[@"u_globalAmbientColor"]] = [NSValue valueWithGLKVector4:ambientColor.glkVector4];
        
        if (weakInterface.needsSpecular)
        {
            passInputs.shaderUniforms[passInputs.uniformTranslationTable[@"u_specularExponent"]] = weakInterface.conditionedShininess;
            passInputs.shaderUniforms[passInputs.uniformTranslationTable[@"u_specularColor"]] = [NSValue valueWithGLKVector4:weakInterface.specularColor.glkVector4];
        }
        
    }]];
    
    return @[pass0];
}

@end


#pragma mark - CCEffectLightingImplMetal

// Thayer says: If I did not keep these structs sorted by largest to smallest
// size of their component types (GLKMatrix4, GLKVector4, int) then I found
// unexpected values in the components when reading them in the shader.
//
// I'm not sure if this a problem with our code in NSValue+CCRenderer (it doesn't
// seem like it should be) or if it's an issue with compiling Metal source
// on-the-fly in the driver as we do for effects.
//
typedef struct CCEffectLightingVertParams
{
    GLKMatrix4 ndcToWorld;
    GLKVector4 lightVector[CCEffectLightingMaxLightCount];
    int lightCount;
    int lightType[CCEffectLightingMaxLightCount];
    
} CCEffectLightingVertParams;

typedef struct CCEffectLightingFragParams
{
    GLKVector4 globalAmbientColor;
    GLKVector4 lightColor[CCEffectLightingMaxLightCount];
    GLKVector4 lightSpecularColor[CCEffectLightingMaxLightCount];
    GLKVector4 lightFalloff[CCEffectLightingMaxLightCount];
    GLKVector4 specularColor;
    GLKVector2 worldSpaceTangent;
    GLKVector2 worldSpaceBinormal;
    float specularExponent;
    int lightCount;
    int lightType[CCEffectLightingMaxLightCount];

} CCEffectLightingFragParams;


@interface CCEffectLightingImplMetal : CCEffectImpl
@property (nonatomic, weak) CCEffectLighting *interface;
@end


@implementation CCEffectLightingImplMetal


-(id)initWithInterface:(CCEffectLighting *)interface
{
    NSArray *renderPasses = [CCEffectLightingImplMetal buildRenderPassesWithInterface:interface];
    NSArray *shaders = [CCEffectLightingImplMetal buildShaders];
    
    if((self = [super initWithRenderPassDescriptors:renderPasses shaders:shaders]))
    {
        self.interface = interface;
        self.debugName = @"CCEffectLightingImplMetal";
        self.stitchFlags = CCEffectFunctionStitchAfter;
    }
    return self;
}

+ (NSArray *)buildStructDeclarations
{
    NSString *lightingVertParams =
    @"float4x4 ndcToWorld;\n"
    @"float4 lightVector[8];\n"
    @"int lightCount;\n"
    @"int lightType[8];\n";
    
    NSString *lightingFragParams =
    @"float4 globalAmbientColor;\n"
    @"float4 lightColor[8];\n"
    @"float4 lightSpecularColor[8];\n"
    @"float4 lightFalloff[8];\n"
    @"float4 specularColor;\n"
    @"float2 worldSpaceTangent;\n"
    @"float2 worldSpaceBinormal;\n"
    @"float specularExponent;\n"
    @"int lightCount;\n"
    @"int lightType[8];\n";

    NSString *lightingFragData =
    @"float4 position [[position]];\n"
    @"float2 texCoord1;\n"
    @"float2 texCoord2;\n"
    @"half4  color;\n"
    @"float3 worldSpaceLightDir0;\n"
    @"float3 worldSpaceLightDir1;\n"
    @"float3 worldSpaceLightDir2;\n"
    @"float3 worldSpaceLightDir3;\n"
    @"float3 worldSpaceLightDir4;\n"
    @"float3 worldSpaceLightDir5;\n"
    @"float3 worldSpaceLightDir6;\n"
    @"float3 worldSpaceLightDir7;\n";
    
    return @[
             [[CCEffectShaderStructDeclaration alloc] initWithName:@"CCEffectLightingVertParams" body:lightingVertParams],
             [[CCEffectShaderStructDeclaration alloc] initWithName:@"CCEffectLightingFragParams" body:lightingFragParams],
             [[CCEffectShaderStructDeclaration alloc] initWithName:@"CCEffectLightingFragData" body:lightingFragData]
             ];
}

+ (NSArray *)buildShaders
{
    return @[[[CCEffectShader alloc] initWithVertexShaderBuilder:[CCEffectLightingImplMetal vertShaderBuilder] fragmentShaderBuilder:[CCEffectLightingImplMetal fragShaderBuilder]]];
}

+ (CCEffectShaderBuilder *)fragShaderBuilder
{
    NSArray *functions = [CCEffectLightingImplMetal buildFragmentFunctions];
    NSArray *temporaries = @[[CCEffectFunctionTemporary temporaryWithType:@"half4" name:@"tmp" initializer:CCEffectInitPreviousPass]];
    NSArray *calls = @[[[CCEffectFunctionCall alloc] initWithFunction:functions[0] outputName:@"lightingResult" inputs:@{@"cc_FragIn" : @"cc_FragIn",
                                                                                                                         @"cc_NormalMapTexture" : @"cc_NormalMapTexture",
                                                                                                                         @"cc_NormalMapTextureSampler" : @"cc_NormalMapTextureSampler",
                                                                                                                         @"cc_FragTexCoordDimensions" : @"cc_FragTexCoordDimensions",
                                                                                                                         @"lightingFragParams" : @"lightingFragParams",
                                                                                                                         @"inputValue" : @"tmp"
                                                                                                                         }]];
    
    
    NSArray *arguments = @[
                           [[CCEffectShaderArgument alloc] initWithType:@"const CCEffectLightingFragData" name:CCShaderArgumentFragIn qualifier:CCEffectShaderArgumentStageIn],
                           [[CCEffectShaderArgument alloc] initWithType:@"texture2d<half>" name:CCShaderUniformPreviousPassTexture qualifier:CCEffectShaderArgumentTexture],
                           [[CCEffectShaderArgument alloc] initWithType:@"sampler" name:CCShaderUniformPreviousPassTextureSampler qualifier:CCEffectShaderArgumentSampler],
                           [[CCEffectShaderArgument alloc] initWithType:@"texture2d<half>" name:CCShaderUniformNormalMapTexture qualifier:CCEffectShaderArgumentTexture],
                           [[CCEffectShaderArgument alloc] initWithType:@"sampler" name:CCShaderUniformNormalMapTextureSampler qualifier:CCEffectShaderArgumentSampler],
                           [[CCEffectShaderArgument alloc] initWithType:@"const device CCEffectTexCoordDimensions*" name:CCShaderArgumentTexCoordDimensions qualifier:CCEffectShaderArgumentBuffer],
                           [[CCEffectShaderArgument alloc] initWithType:@"const device CCEffectLightingFragParams*" name:@"lightingFragParams" qualifier:CCEffectShaderArgumentBuffer]
                           ];
    
    NSArray *structs = [CCEffectLightingImplMetal buildStructDeclarations];
    
    return [[CCEffectShaderBuilderMetal alloc] initWithType:CCEffectShaderBuilderFragment
                                                  functions:functions
                                                      calls:calls
                                                temporaries:temporaries
                                                  arguments:arguments
                                                    structs:[[CCEffectShaderBuilderMetal defaultStructDeclarations] arrayByAddingObjectsFromArray:structs]];
}

+(NSArray *)buildFragmentFunctions
{
    NSString *effectBody = CC_GLSL(
                                   // Index the normal map and expand the color value from [0..1] to [-1..1]
                                   float4 normalMap = (float4)cc_NormalMapTexture.sample(cc_NormalMapTextureSampler, cc_FragIn.texCoord2);
                                   float3 tangentSpaceNormal = normalize(normalMap.xyz * 2.0 - 1.0);
                                   
                                   // Convert the normal vector from tangent space to world space
                                   float3 worldSpaceNormal = normalize(float3(lightingFragParams->worldSpaceTangent, 0.0) * tangentSpaceNormal.x + float3(lightingFragParams->worldSpaceBinormal, 0.0) * tangentSpaceNormal.y + float3(0.0, 0.0, tangentSpaceNormal.z));
                                   
                                   if (inputValue.a * normalMap.a == 0.0)
                                   {
                                       return inputValue;
                                   }
                                   
                                   float3 diffuseSum = lightingFragParams->globalAmbientColor.rgb;
                                   float3 specularSum = float3(0,0,0);
                                   
                                   for (int lightIndex = 0; lightIndex < lightingFragParams->lightCount; lightIndex++)
                                   {
                                       // Is this really how we have to handle arrays of attributes in a
                                       // stage_in struct?
                                       float3 worldSpaceLightDir;
                                       switch (lightIndex)
                                       {
                                           case 0:
                                               worldSpaceLightDir = cc_FragIn.worldSpaceLightDir0;
                                               break;
                                           case 1:
                                               worldSpaceLightDir = cc_FragIn.worldSpaceLightDir1;
                                               break;
                                           case 2:
                                               worldSpaceLightDir = cc_FragIn.worldSpaceLightDir2;
                                               break;
                                           case 3:
                                               worldSpaceLightDir = cc_FragIn.worldSpaceLightDir3;
                                               break;
                                           case 4:
                                               worldSpaceLightDir = cc_FragIn.worldSpaceLightDir4;
                                               break;
                                           case 5:
                                               worldSpaceLightDir = cc_FragIn.worldSpaceLightDir5;
                                               break;
                                           case 6:
                                               worldSpaceLightDir = cc_FragIn.worldSpaceLightDir6;
                                               break;
                                           case 7:
                                               worldSpaceLightDir = cc_FragIn.worldSpaceLightDir7;
                                               break;
                                       }
                                       
                                       float3 lightColor;
                                       float3 lightSpecularColor;
                                       if (lightingFragParams->lightType[lightIndex] == 0)
                                       {
                                           float lightDist = length(worldSpaceLightDir.xy);
                                           worldSpaceLightDir = normalize(worldSpaceLightDir);

                                           float falloffTermA = clamp((lightDist * lightingFragParams->lightFalloff[lightIndex].y + 1.0), 0.0, 1.0);
                                           float falloffTermB = clamp((lightDist * lightingFragParams->lightFalloff[lightIndex].z + lightingFragParams->lightFalloff[lightIndex].w), 0.0, 1.0);
                                           float falloffSelect = step(lightingFragParams->lightFalloff[lightIndex].x, lightDist);
                                           float falloffTerm = (1.0 - falloffSelect) * falloffTermA + falloffSelect * falloffTermB;
                                           
                                           lightColor = lightingFragParams->lightColor[lightIndex].rgb * falloffTerm;
                                           lightSpecularColor = lightingFragParams->lightSpecularColor[lightIndex].rgb * falloffTerm;
                                       }
                                       else
                                       {
                                           lightColor = lightingFragParams->lightColor[lightIndex].rgb;
                                           lightSpecularColor = lightingFragParams->lightSpecularColor[lightIndex].rgb;
                                       }
                                       
                                       float diffuseTerm = max(0.0, dot(worldSpaceNormal, worldSpaceLightDir));
                                       diffuseSum += lightColor * diffuseTerm;
                                       
                                       float3 halfAngleDir = (2.0 * dot(worldSpaceLightDir, worldSpaceNormal) * worldSpaceNormal - worldSpaceLightDir);
                                       float specularTerm = max(0.0, dot(halfAngleDir, float3(0,0,1))) * step(0.0, diffuseTerm);
                                       specularSum += lightSpecularColor * pow(specularTerm, lightingFragParams->specularExponent);
                                   }
                                   
                                   float4 fInputValue = (float4)inputValue;
                                   float4 resultColor = float4(diffuseSum * fInputValue.rgb + specularSum * lightingFragParams->specularColor.rgb * fInputValue.a, fInputValue.a);
                                   
                                   return (half4) resultColor;
                                   );
    
    NSArray *inputs = @[
                        [[CCEffectFunctionInput alloc] initWithType:@"const CCEffectLightingFragData" name:CCShaderArgumentFragIn],
                        [[CCEffectFunctionInput alloc] initWithType:@"texture2d<half>" name:CCShaderUniformNormalMapTexture],
                        [[CCEffectFunctionInput alloc] initWithType:@"sampler" name:CCShaderUniformNormalMapTextureSampler],
                        [[CCEffectFunctionInput alloc] initWithType:@"const device CCEffectTexCoordDimensions*" name:CCShaderArgumentTexCoordDimensions],
                        [[CCEffectFunctionInput alloc] initWithType:@"const device CCEffectLightingFragParams*" name:@"lightingFragParams"],
                        [[CCEffectFunctionInput alloc] initWithType:@"half4" name:@"inputValue"]
                        ];
    
    return @[[[CCEffectFunction alloc] initWithName:@"lightingEffectFrag" body:effectBody inputs:inputs returnType:@"half4"]];
}


+ (CCEffectShaderBuilder *)vertShaderBuilder
{
    NSArray *functions = [CCEffectLightingImplMetal buildVertexFunctions];
    NSArray *temporaries = @[[CCEffectFunctionTemporary temporaryWithType:@"CCEffectLightingFragData" name:@"tmp" initializer:CCEffectInitVertexAttributes]];
    NSArray *calls = @[[[CCEffectFunctionCall alloc] initWithFunction:functions[0] outputName:@"lightingResult" inputs:@{@"fragData" : @"tmp",
                                                                                                                         @"lightingVertParams" : @"lightingVertParams",
                                                                                                                         @"vertexId" : @"cc_VertexId"
                                                                                                                         }]];
    
    
    NSArray *arguments = @[
                           [[CCEffectShaderArgument alloc] initWithType:@"const device CCVertex*" name:CCShaderArgumentVertexAtttributes qualifier:CCEffectShaderArgumentBuffer],
                           [[CCEffectShaderArgument alloc] initWithType:@"unsigned int" name:CCShaderArgumentVertexId qualifier:CCEffectShaderArgumentVertexId],
                           [[CCEffectShaderArgument alloc] initWithType:@"const device CCEffectLightingVertParams*" name:@"lightingVertParams" qualifier:CCEffectShaderArgumentBuffer]
                           ];
    
    NSArray *structs = [CCEffectLightingImplMetal buildStructDeclarations];
    
    return [[CCEffectShaderBuilderMetal alloc] initWithType:CCEffectShaderBuilderVertex
                                                  functions:functions
                                                      calls:calls
                                                temporaries:temporaries
                                                  arguments:arguments
                                                    structs:[[CCEffectShaderBuilderMetal defaultStructDeclarations] arrayByAddingObjectsFromArray:structs]];
}

+(NSArray *)buildVertexFunctions
{
    NSString *effectBody = CC_GLSL(
                                   for (int lightIndex = 0; lightIndex < lightingVertParams->lightCount; lightIndex++)
                                   {
                                       float3 worldSpaceLightDir;
                                       if (lightingVertParams->lightType[lightIndex] == 0)
                                       {
                                           worldSpaceLightDir = (lightingVertParams->lightVector[lightIndex] - lightingVertParams->ndcToWorld * fragData.position).xyz;
                                       }
                                       else
                                       {
                                           worldSpaceLightDir = (lightingVertParams->lightVector[lightIndex]).xyz;
                                       }
                                       
                                       // Is this really how we have to handle arrays of attributes in a
                                       // stage_in struct?
                                       switch (lightIndex)
                                       {
                                           case 0:
                                               fragData.worldSpaceLightDir0 = worldSpaceLightDir;
                                               break;
                                           case 1:
                                               fragData.worldSpaceLightDir1 = worldSpaceLightDir;
                                               break;
                                           case 2:
                                               fragData.worldSpaceLightDir2 = worldSpaceLightDir;
                                               break;
                                           case 3:
                                               fragData.worldSpaceLightDir3 = worldSpaceLightDir;
                                               break;
                                           case 4:
                                               fragData.worldSpaceLightDir4 = worldSpaceLightDir;
                                               break;
                                           case 5:
                                               fragData.worldSpaceLightDir5 = worldSpaceLightDir;
                                               break;
                                           case 6:
                                               fragData.worldSpaceLightDir6 = worldSpaceLightDir;
                                               break;
                                           case 7:
                                               fragData.worldSpaceLightDir7 = worldSpaceLightDir;
                                               break;
                                       }
                                   }
                                   return fragData;
                                   );
    
    NSArray *inputs = @[
                        [[CCEffectFunctionInput alloc] initWithType:@"CCEffectLightingFragData" name:@"fragData"],
                        [[CCEffectFunctionInput alloc] initWithType:@"const device CCEffectLightingVertParams*" name:@"lightingVertParams"],
                        [[CCEffectFunctionInput alloc] initWithType:@"unsigned int" name:@"vertexId"]
                        ];

    return @[[[CCEffectFunction alloc] initWithName:@"lightingEffectVert" body:effectBody inputs:inputs returnType:@"CCEffectLightingFragData"]];
}

+(NSArray *)buildRenderPassesWithInterface:(CCEffectLighting *)interface
{
    __weak CCEffectLighting *weakInterface = interface;
    
    CCEffectRenderPassDescriptor *pass0 = [CCEffectRenderPassDescriptor descriptor];
    pass0.debugLabel = @"CCEffectLighting pass 0";
    pass0.beginBlocks = @[[[CCEffectBeginBlockContext alloc] initWithBlock:^(CCEffectRenderPass *pass, CCEffectRenderPassInputs *passInputs){
        
        
        passInputs.shaderUniforms[CCShaderUniformMainTexture] = passInputs.previousPassTexture;
        passInputs.shaderUniforms[CCShaderUniformPreviousPassTexture] = passInputs.previousPassTexture;
        
        CCEffectTexCoordDimensions tcDims;
        tcDims.texCoord1Center = passInputs.texCoord1Center;
        tcDims.texCoord1Extents = passInputs.texCoord1Extents;
        tcDims.texCoord2Center = passInputs.texCoord2Center;
        tcDims.texCoord2Extents = passInputs.texCoord2Extents;
        passInputs.shaderUniforms[CCShaderArgumentTexCoordDimensions] = [NSValue valueWithBytes:&tcDims objCType:@encode(CCEffectTexCoordDimensions)];

        
        CCEffectLightingVertParams vertParams;
        CCEffectLightingFragParams fragParams;

        GLKMatrix4 nodeLocalToWorld = passInputs.sprite.nodeToWorldMatrix;
        vertParams.ndcToWorld = GLKMatrix4Multiply(nodeLocalToWorld, passInputs.ndcToNodeLocal);
        
        // Tangent and binormal vectors are the x/y basis vectors from the nodeLocalToWorldMatrix
        fragParams.worldSpaceTangent = GLKVector2Normalize(GLKVector2Make(nodeLocalToWorld.m[0], nodeLocalToWorld.m[1]));
        fragParams.worldSpaceBinormal = GLKVector2Normalize(GLKVector2Make(nodeLocalToWorld.m[4], nodeLocalToWorld.m[5]));
        
        vertParams.lightCount = (int)weakInterface.closestLights.count;
        fragParams.lightCount = (int)weakInterface.closestLights.count;
        
        for (NSUInteger lightIndex = 0; lightIndex < weakInterface.closestLights.count; lightIndex++)
        {
            CCLightNode *light = weakInterface.closestLights[lightIndex];
            
            vertParams.lightType[lightIndex] = light.type;
            fragParams.lightType[lightIndex] = light.type;
        
            // Get the transform from the light's coordinate space to the effect's coordinate space.
            GLKMatrix4 lightNodeToWorld = light.nodeToWorldMatrix;
            
            // Compute the light's position in the effect node's coordinate system.
            if (light.type == CCLightDirectional)
            {
                vertParams.lightVector[lightIndex] = GLKVector4Normalize(GLKMatrix4MultiplyVector4(lightNodeToWorld, GLKVector4Make(0.0f, 1.0f, light.depth, 0.0f)));
            }
            else
            {
                vertParams.lightVector[lightIndex] = GLKMatrix4MultiplyVector4(lightNodeToWorld, GLKVector4Make(light.anchorPointInPoints.x, light.anchorPointInPoints.y, light.depth, 1.0f));

                float scale0 = GLKVector4Length(GLKMatrix4GetColumn(lightNodeToWorld, 0));
                float scale1 = GLKVector4Length(GLKMatrix4GetColumn(lightNodeToWorld, 1));
                float maxScale = MAX(scale0, scale1);
                
                float cutoffRadius = light.cutoffRadius * maxScale;
                
                GLKVector4 falloffTerms = GLKVector4Make(0.0f, 0.0f, 0.0f, 1.0f);
                if (cutoffRadius > 0.0f)
                {
                    float xIntercept = cutoffRadius * light.halfRadius;
                    float r1 = 2.0f * xIntercept;
                    float r2 = cutoffRadius;
                    
                    falloffTerms.x = xIntercept;
                    
                    if (light.halfRadius > 0.0f)
                    {
                        falloffTerms.y = -1.0f / r1;
                    }
                    else
                    {
                        falloffTerms.y = 0.0f;
                    }
                    
                    if (light.halfRadius < 1.0f)
                    {
                        falloffTerms.z = -0.5f / (r2 - xIntercept);
                        falloffTerms.w = 0.5f - xIntercept * falloffTerms.z;
                    }
                    else
                    {
                        falloffTerms.z = 0.0f;
                        falloffTerms.w = 0.0f;
                    }
                }
                
                fragParams.lightFalloff[lightIndex] = falloffTerms;
            }
            
            // Compute the real light color based on color and intensity.
            fragParams.lightColor[lightIndex] = GLKVector4MultiplyScalar(light.color.glkVector4, light.intensity);
            fragParams.lightSpecularColor[lightIndex] = GLKVector4MultiplyScalar(light.specularColor.glkVector4, light.specularIntensity);
        }
        
        CCColor *ambientColor = [CCEffectUtilsGetNodeScene(passInputs.sprite).lights findAmbientSumForLightsWithMask:weakInterface.groupMask];
        fragParams.globalAmbientColor = ambientColor.glkVector4;
        
        fragParams.specularExponent = weakInterface.conditionedShininess.floatValue;
        fragParams.specularColor = weakInterface.specularColor.glkVector4;
        
        passInputs.shaderUniforms[passInputs.uniformTranslationTable[@"lightingVertParams"]] = [NSValue valueWithBytes:&vertParams objCType:@encode(CCEffectLightingVertParams)];
        passInputs.shaderUniforms[passInputs.uniformTranslationTable[@"lightingFragParams"]] = [NSValue valueWithBytes:&fragParams objCType:@encode(CCEffectLightingFragParams)];
    }]];
    
    return @[pass0];
}

@end


#pragma mark - CCEffectLighting

@implementation CCEffectLighting

-(id)init
{
    return [self initWithGroups:@[] specularColor:[CCColor whiteColor] shininess:0.5f];
}

-(id)initWithGroups:(NSArray *)groups specularColor:(CCColor *)specularColor shininess:(float)shininess
{
    if((self = [super init]))
    {
        if([CCSetup sharedSetup].graphicsAPI == CCGraphicsAPIMetal)
        {
            self.effectImpl = [[CCEffectLightingImplMetal alloc] initWithInterface:self];
        }
        else
        {
            self.effectImpl = [[CCEffectLightingImplGL alloc] initWithInterface:self];
        }
        self.debugName = @"CCEffectLighting";
        
        _groups = [groups copy];
        _groupMaskDirty = YES;
        _specularColor = specularColor;
        _shininess = shininess;
        _conditionedShininess = [NSNumber numberWithFloat:conditionShininess(shininess)];
    }
    return self;
}


+(instancetype)effectWithGroups:(NSArray *)groups specularColor:(CCColor *)specularColor shininess:(float)shininess
{
    return [[self alloc] initWithGroups:groups specularColor:specularColor shininess:shininess];
}

- (CCEffectPrepareResult)prepareForRenderingWithSprite:(CCSprite *)sprite
{
    CCEffectPrepareResult result = CCEffectPrepareNoop;

    _needsNormalMap = (sprite.normalMapSpriteFrame != nil);
    
    GLKMatrix4 spriteTransform = sprite.nodeToWorldMatrix;
    CGPoint spritePosition = CGPointApplyGLKMatrix4(sprite.anchorPointInPoints, sprite.nodeToWorldMatrix);
    
    CCLightCollection *lightCollection = CCEffectUtilsGetNodeScene(sprite).lights;
    if (self.groupMaskDirty)
    {
        self.groupMask = [lightCollection maskForGroups:self.groups];
        self.groupMaskDirty = NO;
    }
    
    self.closestLights = [lightCollection findClosestKLights:CCEffectLightingMaxLightCount toPoint:spritePosition withMask:self.groupMask];
    
    if([CCSetup sharedSetup].graphicsAPI == CCGraphicsAPIGL)
    {
        CCLightKey newLightKey = CCLightKeyMake(self.closestLights);
        
        if (!CCLightKeyCompare(newLightKey, self.lightKey) ||
            (self.shaderHasSpecular != self.needsSpecular) ||
            (self.shaderHasNormalMap != self.needsNormalMap))
        {
            self.lightKey = newLightKey;
            self.shaderHasSpecular = self.needsSpecular;
            self.shaderHasNormalMap = _needsNormalMap;
            
            self.effectImpl = [[CCEffectLightingImplGL alloc] initWithInterface:self];
            
            result.status = CCEffectPrepareSuccess;
            result.changes = CCEffectPrepareShaderChanged | CCEffectPrepareUniformsChanged;
        }
    }
    else
    {
        // Unlike the GL implementation, the Metal shader is not regenerated as the closest
        // light list changes so we do not create a new implementation object here.
        result.status = CCEffectPrepareSuccess;
        result.changes = CCEffectPrepareUniformsChanged;
    }
    return result;
}

- (BOOL)needsSpecular
{
    return (!GLKVector4AllEqualToScalar(self.specularColor.glkVector4, 0.0f) && (self.shininess > 0.0f));
}

-(void)setGroups:(NSArray *)groups
{
    _groups = [groups copy];
    _groupMaskDirty = YES;
}

-(void)setShininess:(float)shininess
{
    _shininess = shininess;
    _conditionedShininess = [NSNumber numberWithFloat:conditionShininess(shininess)];
}

@end


CCLightKey CCLightKeyMake(NSArray *lights)
{
    CCLightKey lightKey;
    lightKey.pointLightMask = 0;
    lightKey.directionalLightMask = 0;
    
    for (NSUInteger lightIndex = 0; lightIndex < lights.count; lightIndex++)
    {
        CCLightNode *light = lights[lightIndex];
        if (light.type == CCLightPoint)
        {
            lightKey.pointLightMask |= (1 << lightIndex);
        }
        else if (light.type == CCLightDirectional)
        {
            lightKey.directionalLightMask |= (1 << lightIndex);
        }
    }
    return lightKey;
}

BOOL CCLightKeyCompare(CCLightKey a, CCLightKey b)
{
    return (((a.pointLightMask) == (b.pointLightMask)) &&
            ((a.directionalLightMask) == (b.directionalLightMask)));
}

float conditionShininess(float shininess)
{
    // Map supplied shininess from [0..1] to [1..100]
    NSCAssert((shininess >= 0.0f) && (shininess <= 1.0f), @"Supplied shininess out of range [0..1].");
    shininess = clampf(shininess, 0.0f, 1.0f);
    return ((shininess * 99.0f) + 1.0f);
}

