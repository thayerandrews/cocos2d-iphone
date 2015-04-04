//
//  CCEffectShaderBuilderMetal.h
//  cocos2d
//
//  Created by Thayer J Andrews on 3/24/15.
//
//

#import "CCEffectShaderBuilder.h"
#import "CCEffectParameterProtocol.h"

@interface CCEffectShaderBuilderMetal : CCEffectShaderBuilder

@property (nonatomic, readonly) NSArray *arguments;
@property (nonatomic, readonly) NSArray *structs;

- (id)initWithType:(CCEffectShaderBuilderType)type functions:(NSArray *)functions calls:(NSArray *)calls temporaries:(NSArray *)temporaries arguments:(NSArray *)arguments structs:(NSArray *)structs;

+ (NSSet *)defaultVertexArgumentNames;
+ (NSArray *)defaultVertexArguments;
+ (NSSet *)defaultFragmentArgumentNames;
+ (NSArray *)defaultFragmentArguments;
+ (NSSet *)defaultStructNames;
+ (NSArray *)defaultStructDeclarations;
+ (CCEffectShaderBuilder *)defaultVertexShaderBuilder;

@end


typedef NS_ENUM(NSUInteger, CCEffectShaderArgumentQualifier)
{
    CCEffectShaderArgumentBuffer       = 0,
    CCEffectShaderArgumentTexture      = 1,
    CCEffectShaderArgumentSampler      = 2,
    
    CCEffectShaderArgumentStageIn      = 3,
    CCEffectShaderArgumentVertexId     = 4,
    
    CCEffectShaderArgumentQualifierCount,
};


@interface CCEffectShaderArgument : NSObject <NSCopying, CCEffectParameterProtocol>

@property (nonatomic, readonly) NSString *name;
@property (nonatomic, readonly) NSString *type;
@property (nonatomic, readonly) CCEffectShaderArgumentQualifier qualifier;
@property (nonatomic, readonly) NSValue *value;

- (id)initWithType:(NSString *)type name:(NSString *)name qualifier:(CCEffectShaderArgumentQualifier)qualifier;

- (NSString *)declarationAtLocation:(NSUInteger)location;

@end

@interface CCEffectShaderStructDeclaration : NSObject <NSCopying>

@property (nonatomic, readonly) NSString *name;
@property (nonatomic, readonly) NSString *body;
@property (nonatomic, readonly) NSString *declaration;

- (id)initWithName:(NSString *)name body:(NSString *)body;

@end
