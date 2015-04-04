//
//  CCEffectParameterProtocol.h
//  cocos2d
//
//  Created by Thayer J Andrews on 3/26/15.
//
//

#import <Foundation/Foundation.h>

@protocol CCEffectParameterProtocol <NSObject>

@property (nonatomic, readonly) NSString *name;
@property (nonatomic, readonly) NSValue* value;

@end

