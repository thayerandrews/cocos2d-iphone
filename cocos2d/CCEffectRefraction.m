//
//  CCEffectRefraction.m
//  cocos2d-ios
//
//  Created by Thayer J Andrews on 6/19/14.
//
//

#import "CCEffectRefraction.h"
#import "CCDeviceInfo.h"
#import "CCEffectShader.h"
#import "CCEffectShaderBuilderGL.h"
#import "CCEffectShaderBuilderMetal.h"

#import "CCDirector.h"
#import "CCEffectUtils.h"
#import "CCRenderer.h"
#import "CCSpriteFrame.h"
#import "CCTexture.h"

#import "CCEffect_Private.h"
#import "CCSprite_Private.h"


@interface CCEffectRefraction ()
@property (nonatomic, assign) float conditionedRefraction;
@end


#pragma mark - CCEffectRefractionImplGL

@interface CCEffectRefractionImplGL : CCEffectImpl
@property (nonatomic, weak) CCEffectRefraction *interface;
@end


@implementation CCEffectRefractionImplGL

-(id)initWithInterface:(CCEffectRefraction *)interface
{
    NSArray *renderPasses = [CCEffectRefractionImplGL buildRenderPassesWithInterface:interface];
    NSArray *shaders = [CCEffectRefractionImplGL buildShaders];
    
    if((self = [super initWithRenderPasses:renderPasses shaders:shaders]))
    {
        self.interface = interface;
        self.debugName = @"CCEffectRefractionImplGL";
    }
    return self;
}

+ (NSArray *)buildShaders
{
    return @[[[CCEffectShader alloc] initWithVertexShaderBuilder:[CCEffectRefractionImplGL vertexShaderBuilder] fragmentShaderBuilder:[CCEffectRefractionImplGL fragShaderBuilder]]];
}

+ (CCEffectShaderBuilder *)fragShaderBuilder
{
    NSArray *functions = [CCEffectRefractionImplGL buildFragmentFunctions];
    NSArray *temporaries = @[[CCEffectFunctionTemporary temporaryWithType:@"vec4" name:@"tmp" initializer:CCEffectInitPreviousPass]];
    NSArray *calls = @[[[CCEffectFunctionCall alloc] initWithFunction:functions[0] outputName:@"refraction" inputs:@{@"inputValue" : @"tmp"}]];
    
    NSArray *uniforms = @[
                          [CCEffectUniform uniform:@"sampler2D" name:CCShaderUniformPreviousPassTexture value:(NSValue *)[CCTexture none]],
                          [CCEffectUniform uniform:@"vec2" name:CCShaderUniformTexCoord1Center value:[NSValue valueWithGLKVector2:GLKVector2Make(0.0f, 0.0f)]],
                          [CCEffectUniform uniform:@"vec2" name:CCShaderUniformTexCoord1Extents value:[NSValue valueWithGLKVector2:GLKVector2Make(0.0f, 0.0f)]],
                          [CCEffectUniform uniform:@"float" name:@"u_refraction" value:[NSNumber numberWithFloat:1.0f]],
                          [CCEffectUniform uniform:@"sampler2D" name:@"u_envMap" value:(NSValue*)[CCTexture none]],
                          [CCEffectUniform uniform:@"vec2" name:@"u_tangent" value:[NSValue valueWithGLKVector2:GLKVector2Make(1.0f, 0.0f)]],
                          [CCEffectUniform uniform:@"vec2" name:@"u_binormal" value:[NSValue valueWithGLKVector2:GLKVector2Make(0.0f, 1.0f)]]
                          ];
    NSArray *varyings = [CCEffectRefractionImplGL buildVaryings];
    
    return [[CCEffectShaderBuilderGL alloc] initWithType:CCEffectShaderBuilderFragment
                                               functions:functions
                                                   calls:calls
                                             temporaries:temporaries
                                                uniforms:uniforms
                                                varyings:varyings];
}

+ (NSArray *)buildFragmentFunctions
{
    CCEffectFunctionInput *input = [[CCEffectFunctionInput alloc] initWithType:@"vec4" name:@"inputValue"];

    NSString* effectBody = CC_GLSL(
                                   // Index the normal map and expand the color value from [0..1] to [-1..1]
                                   vec4 normalMap = texture2D(cc_NormalMapTexture, cc_FragTexCoord2);
                                   vec4 tangentSpaceNormal = normalMap * 2.0 - 1.0;
                                   
                                   // Convert the normal vector from tangent space to environment space
                                   vec3 normal = normalize(vec3(u_tangent * tangentSpaceNormal.x + u_binormal * tangentSpaceNormal.y, tangentSpaceNormal.z));
                                   vec2 refractOffset = refract(vec3(0,0,1), normal, 1.0).xy * u_refraction;
                                   
                                   // Perturb the screen space texture coordinate by the scaled normal
                                   // vector.
                                   vec2 refractTexCoords = v_envSpaceTexCoords + refractOffset;
                                   
                                   // This is positive if refractTexCoords is in [0..1] and negative otherwise.
                                   vec2 compare = 0.5 - abs(refractTexCoords - 0.5);
                                   
                                   // This is 1.0 if both refracted texture coords are in bounds and 0.0 otherwise.
                                   float inBounds = step(0.0, min(compare.x, compare.y));

                                   // Compute the combination of the sprite's color and texture.
                                   vec4 primaryColor = inputValue;

                                   // If the refracted texture coordinates are within the bounds of the environment map
                                   // blend the primary color with the refracted environment. Multiplying by the normal
                                   // map alpha also allows the effect to be disabled for specific pixels.
                                   primaryColor += inBounds * normalMap.a * texture2D(u_envMap, refractTexCoords) * (1.0 - primaryColor.a);
                                   
                                   return primaryColor;
                                   );
    
    CCEffectFunction* fragmentFunction = [[CCEffectFunction alloc] initWithName:@"refractionEffectFrag" body:effectBody inputs:@[input] returnType:@"vec4"];
    return @[fragmentFunction];
}

+ (CCEffectShaderBuilder *)vertexShaderBuilder
{
    NSArray *functions = [CCEffectRefractionImplGL buildVertexFunctions];
    NSArray *calls = @[[[CCEffectFunctionCall alloc] initWithFunction:functions[0] outputName:@"refraction" inputs:nil]];
    
    NSArray *uniforms = @[
                          [CCEffectUniform uniform:@"mat4" name:@"u_ndcToEnv" value:[NSValue valueWithGLKMatrix4:GLKMatrix4Identity]],
                          ];
    NSArray *varyings = [CCEffectRefractionImplGL buildVaryings];
    
    return [[CCEffectShaderBuilderGL alloc] initWithType:CCEffectShaderBuilderVertex
                                               functions:functions
                                                   calls:calls
                                             temporaries:nil
                                                uniforms:uniforms
                                                varyings:varyings];
}

+ (NSArray *)buildVertexFunctions
{
    NSString* effectBody = CC_GLSL(
                                   // Compute environment space texture coordinates from the vertex positions.
                                   vec4 envSpaceTexCoords = u_ndcToEnv * cc_Position;
                                   v_envSpaceTexCoords = envSpaceTexCoords.xy;
                                   return cc_Position;
                                   );
    
    CCEffectFunction *vertexFunction = [[CCEffectFunction alloc] initWithName:@"refractionEffectVtx" body:effectBody inputs:nil returnType:@"vec4"];
    return @[vertexFunction];
}

+ (NSArray *)buildVaryings
{
    return @[[CCEffectVarying varying:@"vec2" name:@"v_envSpaceTexCoords"]];
}

+ (NSArray *)buildRenderPassesWithInterface:(CCEffectRefraction *)interface
{
    __weak CCEffectRefraction *weakInterface = interface;

    CCEffectRenderPass *pass0 = [[CCEffectRenderPass alloc] init];
    pass0.debugLabel = @"CCEffectRefraction pass 0";
    pass0.beginBlocks = @[[[CCEffectRenderPassBeginBlockContext alloc] initWithBlock:^(CCEffectRenderPass *pass, CCEffectRenderPassInputs *passInputs){
        
        passInputs.shaderUniforms[CCShaderUniformMainTexture] = passInputs.previousPassTexture;
        passInputs.shaderUniforms[CCShaderUniformPreviousPassTexture] = passInputs.previousPassTexture;
        passInputs.shaderUniforms[CCShaderUniformTexCoord1Center] = [NSValue valueWithGLKVector2:passInputs.texCoord1Center];
        passInputs.shaderUniforms[CCShaderUniformTexCoord1Extents] = [NSValue valueWithGLKVector2:passInputs.texCoord1Extents];

        if (weakInterface.normalMap)
        {
            passInputs.shaderUniforms[CCShaderUniformNormalMapTexture] = weakInterface.normalMap.texture;

            CCSpriteTexCoordSet texCoords = [CCSprite textureCoordsForTexture:weakInterface.normalMap.texture withRect:weakInterface.normalMap.rect rotated:weakInterface.normalMap.rotated xFlipped:NO yFlipped:NO];
            CCSpriteVertexes verts = passInputs.verts;
            verts.bl.texCoord2 = texCoords.bl;
            verts.br.texCoord2 = texCoords.br;
            verts.tr.texCoord2 = texCoords.tr;
            verts.tl.texCoord2 = texCoords.tl;
            passInputs.verts = verts;
        }
        
        passInputs.shaderUniforms[passInputs.uniformTranslationTable[@"u_refraction"]] = [NSNumber numberWithFloat:weakInterface.conditionedRefraction];
        passInputs.shaderUniforms[passInputs.uniformTranslationTable[@"u_envMap"]] = weakInterface.environment.texture ?: [CCTexture none];
        
        // Get the transform from the affected node's local coordinates to the environment node.
        GLKMatrix4 effectNodeToRefractEnvNode = weakInterface.environment ? CCEffectUtilsTransformFromNodeToNode(passInputs.sprite, weakInterface.environment, nil) : GLKMatrix4Identity;

        // Concatenate the node to environment transform with the environment node to environment texture transform.
        // The result takes us from the affected node's coordinates to the environment's texture coordinates. We need
        // this when computing the tangent and normal vectors below.
        GLKMatrix4 effectNodeToRefractEnvTexture = GLKMatrix4Multiply(weakInterface.environment.nodeToTextureTransform, effectNodeToRefractEnvNode);

        // Concatenate the node to environment texture transform together with the transform from NDC to local node
        // coordinates. (NDC == normalized device coordinates == render target coordinates that are normalized to the
        // range 0..1). The shader uses this to map from NDC directly to environment texture coordinates.
        GLKMatrix4 ndcToRefractEnvTexture = GLKMatrix4Multiply(effectNodeToRefractEnvTexture, passInputs.ndcToNodeLocal);
        passInputs.shaderUniforms[passInputs.uniformTranslationTable[@"u_ndcToEnv"]] = [NSValue valueWithGLKMatrix4:ndcToRefractEnvTexture];
        
        // Setup the tangent and binormal vectors for the refraction environment
        GLKVector4 refractTangent = GLKVector4Normalize(GLKMatrix4MultiplyVector4(effectNodeToRefractEnvTexture, GLKVector4Make(1.0f, 0.0f, 0.0f, 0.0f)));
        GLKVector4 refractNormal = GLKVector4Make(0.0f, 0.0f, 1.0f, 1.0f);
        GLKVector4 refractBinormal = GLKVector4CrossProduct(refractNormal, refractTangent);
        passInputs.shaderUniforms[passInputs.uniformTranslationTable[@"u_tangent"]] = [NSValue valueWithGLKVector2:GLKVector2Make(refractTangent.x, refractTangent.y)];
        passInputs.shaderUniforms[passInputs.uniformTranslationTable[@"u_binormal"]] = [NSValue valueWithGLKVector2:GLKVector2Make(refractBinormal.x, refractBinormal.y)];
        
    }]];
    
    return @[pass0];
}

-(void)setRefraction:(float)refraction
{
}

@end


#pragma mark - CCEffectRefractionImplMetal

typedef struct CCEffectRefractionParameters
{
    float refraction;
    GLKMatrix4 ndcToEnv;
    GLKVector2 tangent;
    GLKVector2 binormal;
} CCEffectRefractionParameters;


@interface CCEffectRefractionImplMetal : CCEffectImpl
@property (nonatomic, weak) CCEffectRefraction *interface;
@end

@implementation CCEffectRefractionImplMetal

-(id)initWithInterface:(CCEffectRefraction *)interface
{
    NSArray *renderPasses = [CCEffectRefractionImplMetal buildRenderPassesWithInterface:interface];
    NSArray *shaders = [CCEffectRefractionImplMetal buildShaders];
    
    if((self = [super initWithRenderPasses:renderPasses shaders:shaders]))
    {
        self.interface = interface;
        self.debugName = @"CCEffectRefractionImplMetal";
        self.stitchFlags = CCEffectFunctionStitchAfter;
    }
    return self;
}

+ (NSArray *)buildStructDeclarations
{
    NSString* structRefractionFragData =
    @"float4 position [[position]];\n"
    @"float2 texCoord1;\n"
    @"float2 texCoord2;\n"
    @"half4  color;\n"
    @"float2 envSpaceTexCoords;\n";
    
    NSString* structRefractionParams =
    @"float refraction;\n"
    @"float4x4 ndcToEnv;\n"
    @"float2 tangent;\n"
    @"float2 binormal;\n";
    
    return @[
             [[CCEffectShaderStructDeclaration alloc] initWithName:@"CCEffectRefractionFragData" body:structRefractionFragData],
             [[CCEffectShaderStructDeclaration alloc] initWithName:@"CCEffectRefractionParameters" body:structRefractionParams]
             ];
}

+ (NSArray *)buildShaders
{
    return @[[[CCEffectShader alloc] initWithVertexShaderBuilder:[CCEffectRefractionImplMetal vertexShaderBuilder] fragmentShaderBuilder:[CCEffectRefractionImplMetal fragShaderBuilder]]];
}

+ (CCEffectShaderBuilder *)fragShaderBuilder
{
    NSArray *functions = [CCEffectRefractionImplMetal buildFragmentFunctions];
    NSArray *temporaries = @[[CCEffectFunctionTemporary temporaryWithType:@"half4" name:@"tmp" initializer:CCEffectInitPreviousPass]];
    NSArray *calls = @[[[CCEffectFunctionCall alloc] initWithFunction:functions[0] outputName:@"refractionResult" inputs:@{@"cc_FragIn" : @"cc_FragIn",
                                                                                                                           @"cc_NormalMapTexture" : @"cc_NormalMapTexture",
                                                                                                                           @"cc_NormalMapTextureSampler" : @"cc_NormalMapTextureSampler",
                                                                                                                           @"envMapTexture" : @"envMapTexture",
                                                                                                                           @"envMapTextureSampler" : @"envMapTextureSampler",
                                                                                                                           @"cc_FragTexCoordDimensions" : @"cc_FragTexCoordDimensions",
                                                                                                                           @"refractionParams" : @"refractionParams",
                                                                                                                           @"inputValue" : @"tmp"
                                                                                                                           }]];
    
    
    NSArray *arguments = @[
                           [[CCEffectShaderArgument alloc] initWithType:@"const CCEffectRefractionFragData" name:CCShaderArgumentFragIn qualifier:CCEffectShaderArgumentStageIn],
                           [[CCEffectShaderArgument alloc] initWithType:@"texture2d<half>" name:CCShaderUniformPreviousPassTexture qualifier:CCEffectShaderArgumentTexture],
                           [[CCEffectShaderArgument alloc] initWithType:@"sampler" name:CCShaderUniformPreviousPassTextureSampler qualifier:CCEffectShaderArgumentSampler],
                           [[CCEffectShaderArgument alloc] initWithType:@"texture2d<half>" name:CCShaderUniformNormalMapTexture qualifier:CCEffectShaderArgumentTexture],
                           [[CCEffectShaderArgument alloc] initWithType:@"sampler" name:CCShaderUniformNormalMapTextureSampler qualifier:CCEffectShaderArgumentSampler],
                           [[CCEffectShaderArgument alloc] initWithType:@"texture2d<half>" name:@"envMapTexture" qualifier:CCEffectShaderArgumentTexture],
                           [[CCEffectShaderArgument alloc] initWithType:@"sampler" name:@"envMapTextureSampler" qualifier:CCEffectShaderArgumentSampler],
                           [[CCEffectShaderArgument alloc] initWithType:@"const device CCEffectTexCoordDimensions*" name:CCShaderArgumentTexCoordDimensions qualifier:CCEffectShaderArgumentBuffer],
                           [[CCEffectShaderArgument alloc] initWithType:@"const device CCEffectRefractionParameters*" name:@"refractionParams" qualifier:CCEffectShaderArgumentBuffer]
                           ];
    
    NSArray *structs = [CCEffectRefractionImplMetal buildStructDeclarations];
    
    return [[CCEffectShaderBuilderMetal alloc] initWithType:CCEffectShaderBuilderFragment
                                                  functions:functions
                                                      calls:calls
                                                temporaries:temporaries
                                                  arguments:arguments
                                                    structs:[[CCEffectShaderBuilderMetal defaultStructDeclarations] arrayByAddingObjectsFromArray:structs]];
}

+ (NSArray *)buildFragmentFunctions
{
    NSArray *inputs = @[
                        [[CCEffectFunctionInput alloc] initWithType:@"const CCEffectRefractionFragData" name:CCShaderArgumentFragIn],
                        [[CCEffectFunctionInput alloc] initWithType:@"texture2d<half>" name:CCShaderUniformNormalMapTexture],
                        [[CCEffectFunctionInput alloc] initWithType:@"sampler" name:CCShaderUniformNormalMapTextureSampler],
                        [[CCEffectFunctionInput alloc] initWithType:@"texture2d<half>" name:@"envMapTexture"],
                        [[CCEffectFunctionInput alloc] initWithType:@"sampler" name:@"envMapTextureSampler"],
                        [[CCEffectFunctionInput alloc] initWithType:@"const device CCEffectTexCoordDimensions*" name:CCShaderArgumentTexCoordDimensions],
                        [[CCEffectFunctionInput alloc] initWithType:@"const device CCEffectRefractionParameters*" name:@"refractionParams"],
                        [[CCEffectFunctionInput alloc] initWithType:@"half4" name:@"inputValue"]
                        ];
    
    NSString* effectBody = CC_GLSL(
                                   // Index the normal map and expand the color value from [0..1] to [-1..1]
                                   half4 normalMap = cc_NormalMapTexture.sample(cc_NormalMapTextureSampler, cc_FragIn.texCoord2);
                                   float4 tangentSpaceNormal = (float4)normalMap * 2.0 - 1.0;
                                   
                                   // Convert the normal vector from tangent space to environment space
                                   float3 normal = normalize(float3(refractionParams->tangent * tangentSpaceNormal.x + refractionParams->binormal * tangentSpaceNormal.y, tangentSpaceNormal.z));
                                   float2 refractOffset = refract(float3(0,0,1), normal, 1.0).xy * refractionParams->refraction;
                                   
                                   // Perturb the screen space texture coordinate by the scaled normal
                                   // vector.
                                   float2 refractTexCoords = cc_FragIn.envSpaceTexCoords + refractOffset;
                                   
                                   // This is positive if refractTexCoords is in [0..1] and negative otherwise.
                                   float2 compare = 0.5 - abs(refractTexCoords - 0.5);
                                   
                                   // This is 1.0 if both refracted texture coords are in bounds and 0.0 otherwise.
                                   float inBounds = step(0.0, min(compare.x, compare.y));
                                   
                                   // Compute the combination of the sprite's color and texture.
                                   half4 primaryColor = inputValue;
                                   
                                   // If the refracted texture coordinates are within the bounds of the environment map
                                   // blend the primary color with the refracted environment. Multiplying by the normal
                                   // map alpha also allows the effect to be disabled for specific pixels.
                                   primaryColor += inBounds * normalMap.a * envMapTexture.sample(envMapTextureSampler, refractTexCoords) * (1.0 - primaryColor.a);
                                   
                                   return primaryColor;
                                   );
    
    return @[[[CCEffectFunction alloc] initWithName:@"refractionEffectFrag" body:effectBody inputs:inputs returnType:@"half4"]];
}

+ (CCEffectShaderBuilder *)vertexShaderBuilder
{
    NSArray *functions = [CCEffectRefractionImplMetal buildVertexFunctions];
    NSArray *temporaries = @[[CCEffectFunctionTemporary temporaryWithType:@"CCEffectRefractionFragData" name:@"tmp" initializer:CCEffectInitVertexAttributes]];
    NSArray *calls = @[[[CCEffectFunctionCall alloc] initWithFunction:functions[0] outputName:@"refractionResult" inputs:@{@"fragData" : @"tmp",
                                                                                                                           @"refractionParams" : @"refractionParams" }]];
    
    NSArray *arguments = @[
                           [[CCEffectShaderArgument alloc] initWithType:@"const device CCVertex*" name:CCShaderArgumentVertexAtttributes qualifier:CCEffectShaderArgumentBuffer],
                           [[CCEffectShaderArgument alloc] initWithType:@"unsigned int" name:CCShaderArgumentVertexId qualifier:CCEffectShaderArgumentVertexId],
                           [[CCEffectShaderArgument alloc] initWithType:@"const device CCEffectRefractionParameters*" name:@"refractionParams" qualifier:CCEffectShaderArgumentBuffer]
                           ];
    
    NSArray *structs = [CCEffectRefractionImplMetal buildStructDeclarations];
    
    return [[CCEffectShaderBuilderMetal alloc] initWithType:CCEffectShaderBuilderVertex
                                                  functions:functions
                                                      calls:calls
                                                temporaries:temporaries
                                                  arguments:arguments
                                                    structs:[[CCEffectShaderBuilderMetal defaultStructDeclarations] arrayByAddingObjectsFromArray:structs]];
}

+ (NSArray *)buildVertexFunctions
{
    
    NSArray *inputs = @[
                        [[CCEffectFunctionInput alloc] initWithType:@"CCEffectRefractionFragData" name:@"fragData"],
                        [[CCEffectFunctionInput alloc] initWithType:@"const device CCEffectRefractionParameters*" name:@"refractionParams"]
                        ];
    
    NSString* body = CC_GLSL(
                             // Compute environment space texture coordinates from the vertex positions.
                             float4 envSpaceTexCoords = refractionParams->ndcToEnv * fragData.position;
                             fragData.envSpaceTexCoords = envSpaceTexCoords.xy;
                             return fragData;
                             );
    
    return @[[[CCEffectFunction alloc] initWithName:@"refractionEffectVtx" body:body inputs:inputs returnType:@"CCEffectRefractionFragData"]];
}

+ (NSArray *)buildRenderPassesWithInterface:(CCEffectRefraction *)interface
{
    __weak CCEffectRefraction *weakInterface = interface;
    
    CCEffectRenderPass *pass0 = [[CCEffectRenderPass alloc] init];
    pass0.debugLabel = @"CCEffectRefraction pass 0";
    pass0.beginBlocks = @[[[CCEffectRenderPassBeginBlockContext alloc] initWithBlock:^(CCEffectRenderPass *pass, CCEffectRenderPassInputs *passInputs){
                
        passInputs.shaderUniforms[CCShaderUniformMainTexture] = passInputs.previousPassTexture;
        passInputs.shaderUniforms[CCShaderUniformPreviousPassTexture] = passInputs.previousPassTexture;
        
        CCEffectTexCoordDimensions tcDims;
        tcDims.texCoord1Center = passInputs.texCoord1Center;
        tcDims.texCoord1Extents = passInputs.texCoord1Extents;
        tcDims.texCoord2Center = passInputs.texCoord2Center;
        tcDims.texCoord2Extents = passInputs.texCoord2Extents;
        passInputs.shaderUniforms[CCShaderArgumentTexCoordDimensions] = [NSValue valueWithBytes:&tcDims objCType:@encode(CCEffectTexCoordDimensions)];
        
        if (weakInterface.normalMap)
        {
            passInputs.shaderUniforms[CCShaderUniformNormalMapTexture] = weakInterface.normalMap.texture;
            
            CCSpriteTexCoordSet texCoords = [CCSprite textureCoordsForTexture:weakInterface.normalMap.texture withRect:weakInterface.normalMap.rect rotated:weakInterface.normalMap.rotated xFlipped:NO yFlipped:NO];
            CCSpriteVertexes verts = passInputs.verts;
            verts.bl.texCoord2 = texCoords.bl;
            verts.br.texCoord2 = texCoords.br;
            verts.tr.texCoord2 = texCoords.tr;
            verts.tl.texCoord2 = texCoords.tl;
            passInputs.verts = verts;
        }
        
        passInputs.shaderUniforms[passInputs.uniformTranslationTable[@"envMapTexture"]] = weakInterface.environment.texture ?: [CCTexture none];
        
        // Get the transform from the affected node's local coordinates to the environment node.
        GLKMatrix4 effectNodeToRefractEnvNode = weakInterface.environment ? CCEffectUtilsTransformFromNodeToNode(passInputs.sprite, weakInterface.environment, nil) : GLKMatrix4Identity;
        
        // Concatenate the node to environment transform with the environment node to environment texture transform.
        // The result takes us from the affected node's coordinates to the environment's texture coordinates. We need
        // this when computing the tangent and normal vectors below.
        GLKMatrix4 effectNodeToRefractEnvTexture = GLKMatrix4Multiply(weakInterface.environment.nodeToTextureTransform, effectNodeToRefractEnvNode);
        
        // Concatenate the node to environment texture transform together with the transform from NDC to local node
        // coordinates. (NDC == normalized device coordinates == render target coordinates that are normalized to the
        // range 0..1). The shader uses this to map from NDC directly to environment texture coordinates.
        GLKMatrix4 ndcToRefractEnvTexture = GLKMatrix4Multiply(effectNodeToRefractEnvTexture, passInputs.ndcToNodeLocal);
        
        // Setup the tangent and binormal vectors for the refraction environment
        GLKVector4 refractTangent = GLKVector4Normalize(GLKMatrix4MultiplyVector4(effectNodeToRefractEnvTexture, GLKVector4Make(1.0f, 0.0f, 0.0f, 0.0f)));
        GLKVector4 refractNormal = GLKVector4Make(0.0f, 0.0f, 1.0f, 1.0f);
        GLKVector4 refractBinormal = GLKVector4CrossProduct(refractNormal, refractTangent);

        CCEffectRefractionParameters parameters;
        parameters.refraction = weakInterface.conditionedRefraction;
        parameters.ndcToEnv = ndcToRefractEnvTexture;
        parameters.tangent = GLKVector2Make(refractTangent.x, refractTangent.y);
        parameters.binormal = GLKVector2Make(refractBinormal.x, refractBinormal.y);
        passInputs.shaderUniforms[passInputs.uniformTranslationTable[@"refractionParams"]] = [NSValue valueWithBytes:&parameters objCType:@encode(CCEffectRefractionParameters)];
        
    }]];
    
    return @[pass0];
}

@end

#pragma mark - CCEffectRefraction


@implementation CCEffectRefraction

-(id)init
{
    return [self initWithRefraction:1.0f environment:nil normalMap:nil];
}

-(id)initWithRefraction:(float)refraction environment:(CCSprite *)environment
{
    return [self initWithRefraction:refraction environment:environment normalMap:nil];
}

-(id)initWithRefraction:(float)refraction environment:(CCSprite *)environment normalMap:(CCSpriteFrame *)normalMap
{
    if((self = [super init]))
    {
        _refraction = refraction;
        _environment = environment;
        _normalMap = normalMap;

        _conditionedRefraction = CCEffectUtilsConditionRefraction(refraction);
        
        if([CCDeviceInfo sharedDeviceInfo].graphicsAPI == CCGraphicsAPIMetal)
        {
            self.effectImpl = [[CCEffectRefractionImplMetal alloc] initWithInterface:self];
        }
        else
        {
            self.effectImpl = [[CCEffectRefractionImplGL alloc] initWithInterface:self];
        }
        
        self.debugName = @"CCEffectRefraction";
    }
    return self;
}

+(instancetype)effectWithRefraction:(float)refraction environment:(CCSprite *)environment
{
    return [[self alloc] initWithRefraction:refraction environment:environment];
}

+(instancetype)effectWithRefraction:(float)refraction environment:(CCSprite *)environment normalMap:(CCSpriteFrame *)normalMap
{
    return [[self alloc] initWithRefraction:refraction environment:environment normalMap:normalMap];
}

-(void)setRefraction:(float)refraction
{
    _refraction = refraction;
    _conditionedRefraction = CCEffectUtilsConditionRefraction(refraction);
}

@end
