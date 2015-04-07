//
//  CCEffectNode.m
//  cocos2d-ios
//
//  Created by Oleg Osin on 3/26/14.
//
//

#import "CCEffectNode.h"
#import "CCEffectStack.h"
#import "CCEffectRenderer.h"
#import "CCDirector.h"
#import "ccMacros.h"
#import "CCShader.h"
#import "CCSetup.h"
#import "Support/ccUtils.h"
#import "CCFileLocator.h"
#import "Support/CGPointExtension.h"

#import "CCTexture_Private.h"
#import "CCDirector_Private.h"
#import "CCNode_Private.h"
#import "CCRenderer_Private.h"
#import "CCRenderTexture_Private.h"
#import "CCEffect_Private.h"

#if __CC_PLATFORM_MAC
#import <ApplicationServices/ApplicationServices.h>
#endif

@interface CCEffectNode()
{
    CCEffect *_effect;
    CCEffectRenderer *_effectRenderer;
    CGSize _allocatedSize;
}

@end

@implementation CCEffectNode


-(id)init
{
    return [self initWithWidth:1 height:1];
}

-(id)initWithWidth:(int)width height:(int)height
{
    return [self initWithWidth:width height:height depthStencilFormat:0];
}

-(id)initWithWidth:(int)width height:(int)height depthStencilFormat:(GLuint)depthStencilFormat
{
    if((self = [super initWithWidth:width height:height depthStencilFormat:depthStencilFormat]))
    {
        _effectRenderer = [[CCEffectRenderer alloc] init];
        _allocatedSize = CGSizeMake(0.0f, 0.0f);
        self.clearFlags = GL_COLOR_BUFFER_BIT;
	}
	return self;
}

+(instancetype)effectNodeWithWidth:(int)w height:(int)h
{
    return [[CCEffectNode alloc] initWithWidth:w height:h];
}

+(instancetype)effectNodeWithWidth:(int)w height:(int)h depthStencilFormat:(GLuint)depthStencilFormat
{
    return [[CCEffectNode alloc] initWithWidth:w height:h depthStencilFormat:depthStencilFormat];
}

-(CCEffect *)effect
{
	return _effect;
}

-(void)setEffect:(CCEffect *)effect
{
    _effect = effect;
    if (effect)
    {
        [self updateShaderUniformsFromEffect];
    }
    else
    {
        _shaderUniforms = nil;
    }
}

-(void)create
{
    _allocatedSize = self.contentSizeInPoints;
    CGSize pixelSize = CGSizeMake(_allocatedSize.width * _contentScale, _allocatedSize.height * _contentScale);
    [self createTextureAndFboWithPixelSize:pixelSize];

    CGRect rect = CGRectMake(0, 0, _allocatedSize.width, _allocatedSize.height);
	[_sprite setTextureRect:rect];
    
    _projection = GLKMatrix4MakeOrtho(0.0f, _allocatedSize.width, 0.0f, _allocatedSize.height, -1024.0f, 1024.0f);
    if([CCSetup sharedSetup].graphicsAPI == CCGraphicsAPIMetal)
    {
        // Metal has inverted Y
        _projection = GLKMatrix4Multiply(GLKMatrix4MakeScale(1.0, -1.0, 1.0), _projection);
    }
}

-(void)destroy
{
    [super destroy];
    _allocatedSize = CGSizeMake(0.0f, 0.0f);
}

-(void)visit:(CCRenderer *)renderer parentTransform:(const GLKMatrix4 *)parentTransform
{
	// override visit.
	// Don't call visit on its children
	if(!self.visible) return;
    
    CGSize pointSize = self.contentSizeInPoints;
    if (!CGSizeEqualToSize(pointSize, _allocatedSize))
    {
        [self destroy];
        [self contentSizeChanged];
        _contentSizeChanged = NO;
    }
	
    GLKMatrix4 transform = GLKMatrix4Multiply(*parentTransform, [self nodeToParentMatrix]);
    [self draw:renderer transform:&transform];
}

-(void)draw:(CCRenderer *)renderer transform:(const GLKMatrix4 *)transform
{
    // Render children of this effect node into an FBO for use by the
    // remainder of the effects.
    CCRenderer *rtRenderer = [self begin];

    [rtRenderer enqueueClear:self.clearFlags color:_clearColor depth:self.clearDepth stencil:self.clearStencil globalSortOrder:NSIntegerMin];
    
    //! make sure all children are drawn
    [self sortAllChildren];
    
    for(CCNode *child in self.children){
        if( child != _sprite) [child visit:rtRenderer parentTransform:&_projection];
    }
    [self end];

    // Done pre-render
    
    if (_effect)
    {
        _effectRenderer.contentSize = self.contentSizeInPoints;

        CCEffectPrepareResult prepResult = [_effect prepareForRenderingWithSprite:_sprite];
        NSAssert(prepResult.status == CCEffectPrepareSuccess, @"Effect preparation failed.");

        if (prepResult.changes & CCEffectPrepareUniformsChanged)
        {
            // Preparing an effect for rendering can modify its uniforms
            // dictionary which means we need to reinitialize our copy of the
            // uniforms.
            [self updateShaderUniformsFromEffect];
        }
        [_effectRenderer drawSprite:_sprite withEffect:_effect uniforms:_shaderUniforms renderer:renderer transform:transform];
    }
    else
    {
        _sprite.anchorPoint = ccp(0.0f, 0.0f);
        _sprite.position = ccp(0.0f, 0.0f);
        [_sprite visit:renderer parentTransform:transform];
    }
}

- (void)updateShaderUniformsFromEffect
{
    // Initialize the shader uniforms dictionary with the effect's parameters.
    _shaderUniforms = [_effect.effectImpl.shaderParameters mutableCopy];
    
    // And update it with the node's main texture. The normap map is nil since
    // effect nodes don't have them.
    _shaderUniforms[CCShaderUniformMainTexture] = (_texture ?: [CCTexture none]);
    _shaderUniforms[CCShaderUniformNormalMapTexture] = [CCTexture none];
}

@end
