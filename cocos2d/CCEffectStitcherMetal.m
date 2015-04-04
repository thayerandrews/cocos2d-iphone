//
//  CCEffectStitcherMetal.m
//  cocos2d
//
//  Created by Thayer J Andrews on 3/24/15.
//
//

#import "CCEffectStitcherMetal.h"
#import "CCEffectFunction.h"
#import "CCEffectRenderPass.h"
#import "CCEffectShader.h"
#import "CCEffectShaderBuilderMetal.h"
#import "CCEffect_Private.h"


static NSString * const CCEffectStitcherFunctions   = @"CCEffectStitcherFunctions";
static NSString * const CCEffectStitcherCalls       = @"CCEffectStitcherCalls";
static NSString * const CCEffectStitcherTemporaries = @"CCEffectStitcherTemporaries";
static NSString * const CCEffectStitcherArguments   = @"CCEffectStitcherArguments";
static NSString * const CCEffectStitcherStructs     = @"CCEffectStitcherStructs";


@interface CCEffectStitcherMetal ()

// Inputs
@property (nonatomic, copy) NSArray *effects;
@property (nonatomic, copy) NSString *manglePrefix;
@property (nonatomic, copy) NSSet *mangleExclusions;
@property (nonatomic, assign) NSUInteger stitchListIndex;
@property (nonatomic, assign) NSUInteger shaderStartIndex;

// Outputs
@property (nonatomic, strong) NSArray *cachedRenderPasses;
@property (nonatomic, strong) NSArray *cachedShaders;

@end


@implementation CCEffectStitcherMetal

- (id)initWithEffects:(NSArray *)effects manglePrefix:(NSString *)prefix stitchListIndex:(NSUInteger)stitchListIndex shaderStartIndex:(NSUInteger)shaderStartIndex;
{
    // Make sure these aren't nil, empty, etc.
    NSAssert(effects.count, @"");
    NSAssert(prefix.length, @"");
    
    if((self = [super init]))
    {
        _effects = [effects copy];
        _manglePrefix = [prefix copy];
        _stitchListIndex = stitchListIndex;
        _shaderStartIndex = shaderStartIndex;
        
        _cachedRenderPasses = nil;
        _cachedShaders = nil;
    }
    return self;
}

- (NSArray *)renderPasses
{
    // The output render pass and shader arrays are computed lazily when requested.
    // One method computes both of them so we need to make sure everything stays
    // in sync (ie if we don't have one we don't have the other and if one gets
    // created so does the other).
    if (!_cachedRenderPasses)
    {
        NSAssert(!_cachedShaders, @"The output render pass array is nil but the output shader array is not.");
        [self stitchEffects:self.effects manglePrefix:self.manglePrefix stitchListIndex:self.stitchListIndex shaderStartIndex:self.shaderStartIndex];
        
        NSAssert(_cachedRenderPasses, @"Failed to create an output render pass array.");
        NSAssert(_cachedShaders, @"Failed to create an output shader array.");
    }
    return _cachedRenderPasses;
}

- (NSArray *)shaders
{
    // The output render pass and shader arrays are computed lazily when requested.
    // One method computes both of them so we need to make sure everything stays
    // in sync (ie if we don't have one we don't have the other and if one gets
    // created so does the other).
    if (!_cachedShaders)
    {
        NSAssert(!_cachedRenderPasses, @"The output shader array is nil but the output render pass array is not.");
        [self stitchEffects:self.effects manglePrefix:self.manglePrefix stitchListIndex:self.stitchListIndex shaderStartIndex:self.shaderStartIndex];
        
        NSAssert(_cachedRenderPasses, @"Failed to create an output render pass array.");
        NSAssert(_cachedShaders, @"Failed to create an output shader array.");
    }
    return _cachedShaders;
}

- (void)stitchEffects:(NSArray *)effects manglePrefix:(NSString *)prefix stitchListIndex:(NSUInteger)stitchListIndex shaderStartIndex:(NSUInteger)shaderStartIndex
{
    NSAssert(effects.count > 0, @"Unexpectedly empty shader array.");
    
    NSMutableDictionary *allVtxComponents = [[NSMutableDictionary alloc] init];
    NSMutableDictionary *allFragComponents = [[NSMutableDictionary alloc] init];
    NSMutableDictionary *allUTTs = [[NSMutableDictionary alloc] init];
    
    // Decompose the input shaders into their component parts and generate mangled versions of any
    // "file scope" names that could have conflicts (functions, arguments). Then merge them into one
    // big accumulated set of components.
    int shaderIndex = 0;
    for (CCEffectImpl *effect in effects)
    {
        for (CCEffectShader *shader in effect.shaders)
        {
            // Construct the prefix to use for name mangling.
            NSString *shaderPrefix = [NSString stringWithFormat:@"%@%d_", prefix, shaderIndex];
            
            NSAssert([shader.vertexShaderBuilder isKindOfClass:[CCEffectShaderBuilderMetal class]], @"Supplied shader builder is not a Metal shader builder.");
            CCEffectShaderBuilderMetal *vtxBuilder = (CCEffectShaderBuilderMetal *)shader.vertexShaderBuilder;
            NSDictionary *prefixedVtxComponents = nil;
            if (vtxBuilder != [CCEffectShaderBuilderMetal defaultVertexShaderBuilder])
            {
                prefixedVtxComponents = [CCEffectStitcherMetal prefixComponentsFromBuilder:vtxBuilder withPrefix:shaderPrefix stitchListIndex:stitchListIndex];
                [CCEffectStitcherMetal mergePrefixedComponents:prefixedVtxComponents fromShaderAtIndex:shaderIndex intoAllComponents:allVtxComponents];
            }
            
            NSAssert([shader.fragmentShaderBuilder isKindOfClass:[CCEffectShaderBuilderMetal class]], @"Supplied shader builder is not a Metal shader builder.");
            CCEffectShaderBuilderMetal *fragBuilder = (CCEffectShaderBuilderMetal *)shader.fragmentShaderBuilder;
            NSDictionary *prefixedFragComponents = [CCEffectStitcherMetal prefixComponentsFromBuilder:fragBuilder withPrefix:shaderPrefix stitchListIndex:stitchListIndex];
            [CCEffectStitcherMetal mergePrefixedComponents:prefixedFragComponents fromShaderAtIndex:shaderIndex intoAllComponents:allFragComponents];
            
            // Build a new translation table from the mangled vertex and fragment
            // uniform names.
            NSMutableDictionary* translationTable = [[NSMutableDictionary alloc] init];
            for (NSString *key in prefixedVtxComponents[CCEffectStitcherArguments])
            {
                CCEffectShaderArgument *argument = prefixedVtxComponents[CCEffectStitcherArguments][key];
                translationTable[key] = argument.name;
            }
            
            for (NSString *key in prefixedFragComponents[CCEffectStitcherArguments])
            {
                CCEffectShaderArgument *argument = prefixedFragComponents[CCEffectStitcherArguments][key];
                translationTable[key] = argument.name;
            }
            allUTTs[shader] = translationTable;
            
            shaderIndex++;
        }
    }
    
    // Create new shader builders from the accumulated, prefixed components.
    CCEffectShaderBuilder *vtxBuilder = nil;
    if ([allVtxComponents[CCEffectStitcherFunctions] count])
    {
        vtxBuilder = [[CCEffectShaderBuilderMetal alloc] initWithType:CCEffectShaderBuilderVertex
                                                            functions:allVtxComponents[CCEffectStitcherFunctions]
                                                                calls:allVtxComponents[CCEffectStitcherCalls]
                                                          temporaries:allVtxComponents[CCEffectStitcherTemporaries]
                                                            arguments:[allVtxComponents[CCEffectStitcherArguments] allValues]
                                                              structs:[allVtxComponents[CCEffectStitcherStructs] allValues]];
    }
    else
    {
        vtxBuilder = [CCEffectShaderBuilderMetal defaultVertexShaderBuilder];
    }
    CCEffectShaderBuilder *fragBuilder = [[CCEffectShaderBuilderMetal alloc] initWithType:CCEffectShaderBuilderFragment
                                                                                functions:allFragComponents[CCEffectStitcherFunctions]
                                                                                    calls:allFragComponents[CCEffectStitcherCalls]
                                                                              temporaries:allFragComponents[CCEffectStitcherTemporaries]
                                                                                arguments:[allFragComponents[CCEffectStitcherArguments] allValues]
                                                                                  structs:[allFragComponents[CCEffectStitcherStructs] allValues]];
    
    
//    NSLog(@"Stitched Vertex Shader:\n%@\n\n", vtxBuilder.shaderSource);
//    NSLog(@"Stitched Fragment Shader:\n%@\n\n", fragBuilder.shaderSource);
    
    
    // Create a new shader with the new builders.
    _cachedShaders = @[[[CCEffectShader alloc] initWithVertexShaderBuilder:vtxBuilder fragmentShaderBuilder:fragBuilder]];
    
    if (effects.count == 1)
    {
        // If there was only one effect in the stitch list copy its render
        // passes into the output stitched effect. Update the copied passes
        // so they point to the new shader in the stitched effect and update
        // the uniform translation table.
        
        CCEffectImpl *effect = [effects firstObject];
        NSMutableArray *renderPasses = [[NSMutableArray alloc] init];
        for (CCEffectRenderPass *pass in effect.renderPasses)
        {
            CCEffectRenderPass *newPass = [pass copy];
            newPass.shaderIndex += shaderStartIndex;
            
            // Update the uniform translation table in the new pass's begin blocks
            for (CCEffectRenderPassBeginBlockContext *blockContext in newPass.beginBlocks)
            {
                blockContext.uniformTranslationTable = allUTTs[pass.effectShader];
            }
            
            [renderPasses addObject:newPass];
        }
        
        _cachedRenderPasses = [renderPasses copy];
    }
    else
    {
        // Create a new render pass and point it at the stitched shader.
        CCEffectRenderPass *renderPass = [[CCEffectRenderPass alloc] init];
        renderPass.debugLabel = [NSString stringWithFormat:@"CCEffectStack_Stitched_%@", prefix];;
        renderPass.shaderIndex = shaderStartIndex;
        
        NSMutableArray *beginBlocks = [[NSMutableArray alloc] init];
        NSMutableArray *updateBlocks = [[NSMutableArray alloc] init];
        
        // Copy the begin and update blocks from the input passes into the new pass.
        for (CCEffectImpl *effect in effects)
        {
            for (CCEffectRenderPass *pass in effect.renderPasses)
            {
                for (CCEffectRenderPassBeginBlockContext *blockContext in pass.beginBlocks)
                {
                    // Copy the context and set the UTT to the new UTT for the corresponding
                    // shader for this pass.
                    CCEffectRenderPassBeginBlockContext *newContext = [blockContext copy];
                    newContext.uniformTranslationTable = allUTTs[pass.effectShader];
                    
                    [beginBlocks addObject:newContext];
                }
                
                // Copy the update blocks. They don't need any adjustment so they can just
                // be copied outright.
                [updateBlocks addObjectsFromArray:[pass.updateBlocks copy]];
            }
        }
        
        renderPass.beginBlocks = beginBlocks;
        renderPass.updateBlocks = updateBlocks;
        
        _cachedRenderPasses = @[renderPass];
    }
}

+ (void)mergePrefixedComponents:(NSDictionary *)prefixedComponents fromShaderAtIndex:(NSUInteger)shaderIndex intoAllComponents:(NSMutableDictionary *)allComponents
{
    CCEffectFunctionCall *lastCall = nil;
    if (shaderIndex > 0)
    {
        NSAssert([allComponents[CCEffectStitcherCalls] count], @"");
        
        lastCall = [allComponents[CCEffectStitcherCalls] lastObject];
    }

    // Structs
    if (!allComponents[CCEffectStitcherStructs])
    {
        allComponents[CCEffectStitcherStructs] = [[NSMutableDictionary alloc] init];
    }
    for (CCEffectShaderStructDeclaration *structDecl in [prefixedComponents[CCEffectStitcherStructs] allValues])
    {
        if (!allComponents[CCEffectStitcherStructs][structDecl.name])
        {
            allComponents[CCEffectStitcherStructs][structDecl.name] = structDecl;
        }
    }

    // Functions
    if (!allComponents[CCEffectStitcherFunctions])
    {
        allComponents[CCEffectStitcherFunctions] = [[NSMutableArray alloc] init];
    }
    [allComponents[CCEffectStitcherFunctions] addObjectsFromArray:[prefixedComponents[CCEffectStitcherFunctions] allValues]];
    
    // Arguments
    if (!allComponents[CCEffectStitcherArguments])
    {
        allComponents[CCEffectStitcherArguments] = [[NSMutableDictionary alloc] init];
    }
    for (CCEffectShaderArgument *argument in [prefixedComponents[CCEffectStitcherArguments] allValues])
    {
        if (!allComponents[CCEffectStitcherArguments][argument.name])
        {
            allComponents[CCEffectStitcherArguments][argument.name] = argument;
        }
    }

    // Temporaries
    if (!allComponents[CCEffectStitcherTemporaries])
    {
        allComponents[CCEffectStitcherTemporaries] = [[NSMutableArray alloc] init];
    }
    if (shaderIndex == 0)
    {
        // For the first shader we just copy its temporaries. The temporaries of subsequent shaders aren't
        // needed because function call inputs that had referenced temporaries are remapped to reference
        // shader arguments or outputs.
        [allComponents[CCEffectStitcherTemporaries] addObjectsFromArray:[prefixedComponents[CCEffectStitcherTemporaries] allValues]];
    }
    
    // Calls
    if (!allComponents[CCEffectStitcherCalls])
    {
        allComponents[CCEffectStitcherCalls] = [[NSMutableArray alloc] init];
    }
    
    if (shaderIndex == 0)
    {
        // If we're processing the first shader then we don't need to do anything special here and we can
        // just copy the function call information.
        [allComponents[CCEffectStitcherCalls] addObjectsFromArray:prefixedComponents[CCEffectStitcherCalls]];
    }
    else
    {
        // For shaders after the first one, we have to tweak each function call's input map if it has references
        // to any temporaries. Temporaries that would have been initialized with the previous pass output texture
        // are replaced with the output of the last shader's last function call.
        for (CCEffectFunctionCall *call in prefixedComponents[CCEffectStitcherCalls])
        {
            NSMutableDictionary *remappedInputs = [[NSMutableDictionary alloc] init];
            for (NSString *inputName in call.inputs)
            {
                NSString *connectedVariableName = call.inputs[inputName];
                if (prefixedComponents[CCEffectStitcherTemporaries][connectedVariableName])
                {
                    remappedInputs[inputName] = lastCall.outputName;
                }
                else
                {
                    remappedInputs[inputName] = connectedVariableName;
                }
            }
            if (remappedInputs.count)
            {
                CCEffectFunctionCall *newCall = [[CCEffectFunctionCall alloc] initWithFunction:call.function outputName:call.outputName inputs:remappedInputs];
                [allComponents[CCEffectStitcherCalls] addObject:newCall];
            }
            else
            {
                [allComponents[CCEffectStitcherCalls] addObject:call];
            }
        }
    }
}

+ (NSDictionary *)prefixComponentsFromBuilder:(CCEffectShaderBuilderMetal *)builder withPrefix:(NSString *)prefix stitchListIndex:(NSUInteger)stitchListIndex
{
    NSMutableDictionary *prefixedComponents = [[NSMutableDictionary alloc] init];
    
    NSSet *defaultArgumentNames = nil;
    if (builder.type == CCEffectShaderBuilderVertex)
    {
        defaultArgumentNames = [CCEffectShaderBuilderMetal defaultVertexArgumentNames];
    }
    else
    {
        defaultArgumentNames = [CCEffectShaderBuilderMetal defaultFragmentArgumentNames];
    }
    
    prefixedComponents[CCEffectStitcherStructs] = [CCEffectStitcherMetal structsByApplyingPrefix:prefix toStructs:builder.structs withExclusions:[CCEffectShaderBuilderMetal defaultStructNames]];
    prefixedComponents[CCEffectStitcherArguments] = [CCEffectStitcherMetal argumentsByApplyingPrefix:prefix
                                                                                  structReplacements:prefixedComponents[CCEffectStitcherStructs]
                                                                                         toArguments:builder.arguments
                                                                                      withExclusions:defaultArgumentNames];
    prefixedComponents[CCEffectStitcherFunctions] = [CCEffectStitcherMetal functionsByApplyingPrefix:prefix
                                                                                  structReplacements:prefixedComponents[CCEffectStitcherStructs]
                                                                                argumentReplacements:prefixedComponents[CCEffectStitcherArguments]
                                                                                         toFunctions:builder.functions];
    prefixedComponents[CCEffectStitcherTemporaries] = [CCEffectStitcherMetal temporariesByApplyingPrefix:prefix
                                                                                      structReplacements:prefixedComponents[CCEffectStitcherStructs]
                                                                                           toTemporaries:builder.temporaries
                                                                                         stitchListIndex:stitchListIndex];
    prefixedComponents[CCEffectStitcherCalls] = [CCEffectStitcherMetal callsByApplyingPrefix:prefix
                                                                        functionReplacements:prefixedComponents[CCEffectStitcherFunctions]
                                                                                     toCalls:builder.calls
                                                                              withExclusions:defaultArgumentNames];
    return prefixedComponents;
}

+ (NSDictionary *)functionsByApplyingPrefix:(NSString *)prefix structReplacements:(NSDictionary *)structReplacements argumentReplacements:(NSDictionary *)argumentReplacements toFunctions:(NSArray *)functions
{
    // Functions
    NSMutableDictionary *functionReplacements = [[NSMutableDictionary alloc] init];
    for(CCEffectFunction *function in functions)
    {
        CCEffectFunction *prefixedFunction = [CCEffectStitcherMetal functionByApplyingPrefix:prefix structReplacements:structReplacements allFunctions:functions toEffectFunction:function];
        functionReplacements[function.name] = prefixedFunction;
    }
    return [functionReplacements copy];
}

+ (CCEffectFunction *)functionByApplyingPrefix:(NSString *)prefix structReplacements:(NSDictionary *)structReplacements allFunctions:(NSArray*)allFunctions toEffectFunction:(CCEffectFunction *)function
{
    NSString *prefixedBody = [CCEffectStitcherMetal functionBodyByApplyingPrefix:prefix structReplacements:structReplacements toAllFunctions:(NSArray *)allFunctions inFunctionBody:function.body];
    NSString *prefixedName = [NSString stringWithFormat:@"%@%@", prefix, function.name];
    NSString *prefixedReturnType = [CCEffectStitcherMetal stringFromString:function.returnType byApplyingStructReplacements:structReplacements];
    
    NSMutableArray *prefixedInputs = [NSMutableArray array];
    for (CCEffectFunctionInput *input in function.inputs)
    {
        NSString *prefixedType = [CCEffectStitcherMetal stringFromString:input.type byApplyingStructReplacements:structReplacements];
        [prefixedInputs addObject:[CCEffectFunctionInput inputWithType:prefixedType name:input.name]];
    }
    
    return [[CCEffectFunction alloc] initWithName:prefixedName body:prefixedBody inputs:prefixedInputs returnType:prefixedReturnType];
}

+ (NSString *)functionBodyByApplyingPrefix:prefix structReplacements:(NSDictionary *)structReplacements toAllFunctions:(NSArray *)allFunctions inFunctionBody:(NSString *)body
{
    for (CCEffectFunction *function in allFunctions)
    {
        NSString *prefixedName = [NSString stringWithFormat:@"%@%@", prefix, function.name];
        body = [body stringByReplacingOccurrencesOfString:function.name withString:prefixedName];
    }
    
    return [CCEffectStitcherMetal stringFromString:body byApplyingStructReplacements:structReplacements];
}

+ (NSDictionary *)structsByApplyingPrefix:(NSString *)prefix toStructs:(NSArray *)structs withExclusions:(NSSet *)exclusions
{
    NSMutableDictionary *structReplacements = [[NSMutableDictionary alloc] init];
    for(CCEffectShaderStructDeclaration *structDecl in structs)
    {
        if (![exclusions containsObject:structDecl.name])
        {
            CCEffectShaderStructDeclaration *prefixedStruct = [CCEffectStitcherMetal structByApplyingPrefix:prefix toStruct:structDecl allStructs:structs];
            structReplacements[structDecl.name] = prefixedStruct;
        }
        else
        {
            structReplacements[structDecl.name] = [structDecl copy];
        }
    }
    return [structReplacements copy];
}

+ (CCEffectShaderStructDeclaration *)structByApplyingPrefix:(NSString *)prefix toStruct:(CCEffectShaderStructDeclaration *)structDecl allStructs:(NSArray*)allStructs
{
    NSString *prefixedBody = [CCEffectStitcherMetal structBodyByApplyingPrefix:prefix toAllStructs:(NSArray *)allStructs inStructBody:structDecl.body];
    NSString *prefixedName = [NSString stringWithFormat:@"%@%@", prefix, structDecl.name];
    
    return [[CCEffectShaderStructDeclaration alloc] initWithName:prefixedName body:prefixedBody];
}

+ (NSString *)structBodyByApplyingPrefix:prefix toAllStructs:(NSArray *)allStructs inStructBody:(NSString *)body
{
    for (CCEffectShaderStructDeclaration *structDecl in allStructs)
    {
        NSString *prefixedName = [NSString stringWithFormat:@"%@%@", prefix, structDecl.name];
        body = [body stringByReplacingOccurrencesOfString:structDecl.name withString:prefixedName];
    }
    
    return body;
}

+ (NSDictionary *)argumentsByApplyingPrefix:(NSString *)prefix structReplacements:(NSDictionary *)structReplacements toArguments:(NSArray *)arguments withExclusions:(NSSet *)exclusions
{
    NSMutableDictionary *argumentReplacements = [[NSMutableDictionary alloc] init];
    for(CCEffectShaderArgument *argument in arguments)
    {
        NSString *prefixedType = [CCEffectStitcherMetal stringFromString:argument.type byApplyingStructReplacements:structReplacements];
        NSString *prefixedName = argument.name;
        if (![exclusions containsObject:argument.name])
        {
            prefixedName = [NSString stringWithFormat:@"%@%@", prefix, argument.name];
        }
        argumentReplacements[argument.name] = [[CCEffectShaderArgument alloc] initWithType:prefixedType name:prefixedName qualifier:argument.qualifier];
    }
    return [argumentReplacements copy];
}

+ (NSDictionary *)temporariesByApplyingPrefix:(NSString *)prefix structReplacements:(NSDictionary *)structReplacements toTemporaries:(NSArray *)temporaries stitchListIndex:(NSUInteger)stitchListIndex
{
    NSMutableDictionary *temporaryReplacements = [[NSMutableDictionary alloc] init];
    for(CCEffectFunctionTemporary *temporary in temporaries)
    {
        NSString *prefixedType = [CCEffectStitcherMetal stringFromString:temporary.type byApplyingStructReplacements:structReplacements];
        NSString *prefixedName = [NSString stringWithFormat:@"%@%@", prefix, temporary.name];
        
        if (stitchListIndex == 0)
        {
            // If this stitch group is the first in the stack, we only need to adjust each temporary's name.
            temporaryReplacements[prefixedName] = [CCEffectFunctionTemporary temporaryWithType:prefixedType name:prefixedName initializer:temporary.initializer];
        }
        else
        {
            // If this stitch group is not first in the stack, we need to adjust each temporary's name _and_ adjust
            // its initializer to make sure cc_FragColor doesn't contribute to the initializer expression again.
            temporaryReplacements[prefixedName] = [CCEffectFunctionTemporary temporaryWithType:prefixedType name:prefixedName initializer:[CCEffectFunctionTemporary promoteInitializer:temporary.initializer]];
        }
    }
    return [temporaryReplacements copy];
}

+ (NSArray *)callsByApplyingPrefix:(NSString *)prefix functionReplacements:(NSDictionary *)functionReplacements toCalls:(NSArray *)calls withExclusions:(NSSet *)exclusions
{
    NSMutableArray *callReplacements = [[NSMutableArray alloc] init];
    for(CCEffectFunctionCall *call in calls)
    {
        NSString *prefixedOutputName = [NSString stringWithFormat:@"%@%@", prefix, call.outputName];
        
        CCEffectFunction *function = functionReplacements[call.function.name];
        
        NSMutableDictionary *prefixedInputs = [[NSMutableDictionary alloc] init];
        for (NSString *localInputName in call.inputs.allKeys)
        {
            NSString *externalInputName = call.inputs[localInputName];
            if (![exclusions containsObject:externalInputName])
            {
                NSString *prefixedInputName = [NSString stringWithFormat:@"%@%@", prefix, externalInputName];
                prefixedInputs[localInputName] = prefixedInputName;
            }
            else
            {
                prefixedInputs[localInputName] = externalInputName;
            }
        }
        [callReplacements addObject:[[CCEffectFunctionCall alloc] initWithFunction:function outputName:prefixedOutputName inputs:prefixedInputs]];
    }
    return [callReplacements copy];
}

+ (NSString *)stringFromString:(NSString*)input byApplyingStructReplacements:(NSDictionary *)structReplacements
{
    for (NSString *oldStructName in structReplacements)
    {
        CCEffectShaderStructDeclaration *newStruct = structReplacements[oldStructName];
        input = [input stringByReplacingOccurrencesOfString:oldStructName withString:newStruct.name];
    }
    return input;
}

@end
