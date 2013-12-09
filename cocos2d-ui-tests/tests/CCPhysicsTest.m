//
// Parallax Demo
// a cocos2d example
// http://www.cocos2d-iphone.org
//
//  Created by Andy Korth on 11/15/13.
//

#import "cocos2d.h"
#import "TestBase.h"

@interface CCPhysicsTest : TestBase @end

@implementation CCPhysicsTest

-(void) setupBasicShapeTest
{
	CCPhysicsNode *physics = [CCPhysicsNode node];
	physics.debugDraw = YES;
	[self.contentNode addChild:physics];
	
	{
		CCSprite *sprite = [CCSprite spriteWithImageNamed:@"Sprites/shape-0.png"];
		sprite.position = ccp(100, 100);
		sprite.rotation = 13;
		
		CGRect rect = {CGPointZero, sprite.contentSize};
		CCPhysicsBody *body = sprite.physicsBody = [CCPhysicsBody bodyWithRect:rect cornerRadius:0.0];
		body.velocity = ccp(10, 10);
		body.angularVelocity = 0.1;
		
		[physics addChild:sprite];
	}{
		CCSprite *sprite = [CCSprite spriteWithImageNamed:@"Sprites/shape-1.png"];
		sprite.position = ccp(100, 220);
		sprite.rotation = 13;
		
		CGSize size = sprite.contentSize;
		CGPoint points[] = {
			ccp(0, 0),
			ccp(size.width, 0),
			ccp(size.width/2, size.height),
		};
		
		CCPhysicsBody *body = sprite.physicsBody = [CCPhysicsBody bodyWithPolygonFromPoints:points count:3 cornerRadius:0.0];
		body.velocity = ccp(10, -10);
		body.angularVelocity = -0.1;
		
		[physics addChild:sprite];
	}{
		CCSprite *sprite = [CCSprite spriteWithImageNamed:@"Sprites/shape-2.png"];
		sprite.position = ccp(380, 220);
		sprite.rotation = 13;
		
		CGRect rect = {CGPointZero, sprite.contentSize};
		CCPhysicsBody *body = sprite.physicsBody = [CCPhysicsBody bodyWithRect:rect cornerRadius:0.0];
		body.velocity = ccp(-10, -10);
		body.angularVelocity = 0.1;
		
		[physics addChild:sprite];
	}{
		CCSprite *sprite = [CCSprite spriteWithImageNamed:@"Sprites/shape-3.png"];
		sprite.position = ccp(380, 100);
		sprite.rotation = 13;
		
		CGRect rect = {CGPointZero, sprite.contentSize};
		CCPhysicsBody *body = sprite.physicsBody = [CCPhysicsBody bodyWithRect:rect cornerRadius:0.0];
		body.velocity = ccp(-10, 10);
		body.angularVelocity = -0.1;
		
		[physics addChild:sprite];
	}
}

-(void) setupScaledBasicShapeTest
{
	CCPhysicsNode *physics = [CCPhysicsNode node];
	physics.debugDraw = YES;
	[self.contentNode addChild:physics];
	
	{
		CCSprite *sprite = [CCSprite spriteWithImageNamed:@"Sprites/shape-0.png"];
		sprite.position = ccp(100, 100);
		sprite.rotation = 13;
		sprite.scale = 0.5;
		
		CGRect rect = {CGPointZero, sprite.contentSize};
		CCPhysicsBody *body = sprite.physicsBody = [CCPhysicsBody bodyWithRect:rect cornerRadius:0.0];
		body.velocity = ccp(10, 10);
		body.angularVelocity = 0.1;
		
		[physics addChild:sprite];
	}{
		CCSprite *sprite = [CCSprite spriteWithImageNamed:@"Sprites/shape-1.png"];
		sprite.position = ccp(100, 220);
		sprite.rotation = 13;
		sprite.scaleY = 1.5;
		
		CGSize size = sprite.contentSize;
		CGPoint points[] = {
			ccp(0, 0),
			ccp(size.width, 0),
			ccp(size.width/2, size.height),
		};
		
		CCPhysicsBody *body = sprite.physicsBody = [CCPhysicsBody bodyWithPolygonFromPoints:points count:3 cornerRadius:0.0];
		body.velocity = ccp(10, -10);
		body.angularVelocity = -0.1;
		
		[physics addChild:sprite];
	}{
		CCSprite *sprite = [CCSprite spriteWithImageNamed:@"Sprites/shape-2.png"];
		sprite.position = ccp(380, 220);
		sprite.rotation = 13;
		sprite.scaleX = 0.5;
		
		CGRect rect = {CGPointZero, sprite.contentSize};
		CCPhysicsBody *body = sprite.physicsBody = [CCPhysicsBody bodyWithRect:rect cornerRadius:0.0];
		body.velocity = ccp(-10, -10);
		body.angularVelocity = 0.1;
		
		[physics addChild:sprite];
	}{
		CCSprite *sprite = [CCSprite spriteWithImageNamed:@"Sprites/shape-3.png"];
		sprite.position = ccp(380, 100);
		sprite.rotation = 13;
		sprite.scaleY = 1.5;
		
		CGRect rect = {CGPointZero, sprite.contentSize};
		CCPhysicsBody *body = sprite.physicsBody = [CCPhysicsBody bodyWithRect:rect cornerRadius:0.0];
		body.velocity = ccp(-10, 10);
		body.angularVelocity = -0.1;
		
		[physics addChild:sprite];
	}
}

-(void) setupJointTest
{
	CCPhysicsNode *physics = [CCPhysicsNode node];
	physics.gravity = ccp(0, -100);
	physics.debugDraw = YES;
	[self.contentNode addChild:physics];
	
	{
		CCSprite *sprite1 = [CCSprite spriteWithImageNamed:@"Sprites/shape-0.png"];
		sprite1.position = ccp(100, 200);
		
		CGRect rect = {CGPointZero, sprite1.contentSize};
		CCPhysicsBody *body1 = sprite1.physicsBody = [CCPhysicsBody bodyWithRect:rect cornerRadius:0.0];
		body1.type = CCPhysicsBodyTypeStatic;
		
		[physics addChild:sprite1];
		
		CCSprite *sprite2 = [CCSprite spriteWithImageNamed:@"Sprites/shape-0.png"];
		sprite2.position = ccp(100, 100);
		
		CCPhysicsBody *body2 = sprite2.physicsBody = [CCPhysicsBody bodyWithRect:rect cornerRadius:0.0];
		body2.velocity = ccp(10, 0);
		
		[physics addChild:sprite2];
		
		[CCPhysicsJoint connectedPivotJointWithBodyA:body1 bodyB:body2 anchorA:ccp(rect.size.width/2.0, -rect.size.height/4.0)];
	}{
		CCSprite *sprite1 = [CCSprite spriteWithImageNamed:@"Sprites/shape-0.png"];
		sprite1.position = ccp(200, 200);
		
		CGRect rect = {CGPointZero, sprite1.contentSize};
		CCPhysicsBody *body1 = sprite1.physicsBody = [CCPhysicsBody bodyWithRect:rect cornerRadius:0.0];
		body1.type = CCPhysicsBodyTypeStatic;
		
		[physics addChild:sprite1];
		
		CCSprite *sprite2 = [CCSprite spriteWithImageNamed:@"Sprites/shape-0.png"];
		sprite2.position = ccp(200, 100);
		
		CCPhysicsBody *body2 = sprite2.physicsBody = [CCPhysicsBody bodyWithRect:rect cornerRadius:0.0];
		body2.velocity = ccp(10, 0);
		
		[physics addChild:sprite2];
		
		[CCPhysicsJoint connectedDistanceJointWithBodyA:body1 bodyB:body2 anchorA:ccp(rect.size.width/2.0, 0.0) anchorB:ccp(rect.size.width/2.0, rect.size.height)];
	}{
		CCSprite *sprite1 = [CCSprite spriteWithImageNamed:@"Sprites/shape-0.png"];
		sprite1.position = ccp(300, 200);
		
		CGRect rect = {CGPointZero, sprite1.contentSize};
		CCPhysicsBody *body1 = sprite1.physicsBody = [CCPhysicsBody bodyWithRect:rect cornerRadius:0.0];
		body1.type = CCPhysicsBodyTypeStatic;
		
		[physics addChild:sprite1];
		
		CCSprite *sprite2 = [CCSprite spriteWithImageNamed:@"Sprites/shape-0.png"];
		sprite2.position = ccp(300, 100);
		
		CCPhysicsBody *body2 = sprite2.physicsBody = [CCPhysicsBody bodyWithRect:rect cornerRadius:0.0];
		body2.velocity = ccp(10, 500);
		
		[physics addChild:sprite2];
		
		[CCPhysicsJoint connectedDistanceJointWithBodyA:body1 bodyB:body2 anchorA:ccp(rect.size.width/2.0, 0.0) anchorB:ccp(rect.size.width/2.0, rect.size.height) minDistance:20 maxDistance:70];
	}
}

@end