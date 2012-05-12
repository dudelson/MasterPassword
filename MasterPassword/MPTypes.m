//
//  MPTypes.m
//  MasterPassword
//
//  Created by Maarten Billemont on 02/01/12.
//  Copyright (c) 2012 Lyndir. All rights reserved.
//

#import "MPTypes.h"
#import "MPElementGeneratedEntity.h"
#import "MPElementStoredEntity.h"
#include <endian.h>


#define MP_salt     nil
#define MP_N        16384
#define MP_r        8
#define MP_p        1
#define MP_dkLen    64
#define MP_hash     PearlDigestSHA256

NSData *keyForPassword(NSString *password) {
    
    NSData *key = [PearlSCrypt deriveKeyWithLength:MP_dkLen fromPassword:[password dataUsingEncoding:NSUTF8StringEncoding]
                                         usingSalt:MP_salt N:MP_N r:MP_r p:MP_p];

    trc(@"Password: %@ derives to key ID: %@", password, [keyHashForKey(key) encodeHex]);
    return key;
}
NSData *keyHashForPassword(NSString *password) {
    
    return keyHashForKey(keyForPassword(password));
}
NSData *keyHashForKey(NSData *key) {
    
    return [key hashWith:MP_hash];
}
NSString *NSStringFromMPElementType(MPElementType type) {
    
    if (!type)
        return nil;
    
    switch (type) {
        case MPElementTypeGeneratedLong:
            return @"Long Password";
            
        case MPElementTypeGeneratedMedium:
            return @"Medium Password";
            
        case MPElementTypeGeneratedShort:
            return @"Short Password";
            
        case MPElementTypeGeneratedBasic:
            return @"Basic Password";
            
        case MPElementTypeGeneratedPIN:
            return @"PIN";
            
        case MPElementTypeStoredPersonal:
            return @"Personal Password";
            
        case MPElementTypeStoredDevicePrivate:
            return @"Device Private Password";
            
        default:
            [NSException raise:NSInternalInconsistencyException format:@"Type not supported: %d", type];
    }
}

Class ClassFromMPElementType(MPElementType type) {
    
    if (!type)
        return nil;
    
    switch (type) {
        case MPElementTypeGeneratedLong:
            return [MPElementGeneratedEntity class];
            
        case MPElementTypeGeneratedMedium:
            return [MPElementGeneratedEntity class];
            
        case MPElementTypeGeneratedShort:
            return [MPElementGeneratedEntity class];
            
        case MPElementTypeGeneratedBasic:
            return [MPElementGeneratedEntity class];
            
        case MPElementTypeGeneratedPIN:
            return [MPElementGeneratedEntity class];
            
        case MPElementTypeStoredPersonal:
            return [MPElementStoredEntity class];
            
        case MPElementTypeStoredDevicePrivate:
            return [MPElementStoredEntity class];
            
        default:
            [NSException raise:NSInternalInconsistencyException format:@"Type not supported: %d", type];
    }
}

NSString *ClassNameFromMPElementType(MPElementType type) {
    
    return NSStringFromClass(ClassFromMPElementType(type));
}

static NSDictionary *MPTypes_ciphers = nil;
NSString *MPCalculateContent(MPElementType type, NSString *name, NSData *key, int32_t counter) {
    
    if (!(type & MPElementTypeClassGenerated)) {
        err(@"Incorrect type (is not MPElementTypeClassGenerated): %d, for: %@", type, name);
        return nil;
    }
    if (!name) {
        err(@"Missing name.");
        return nil;
    }
    if (!key) {
        err(@"Key not set.");
        return nil;
    }
    uint32_t salt = (unsigned)counter;
    if (!counter)
        // Counter unset, go into OTP mode.
        // Get the UNIX timestamp of the start of the interval of 5 minutes that the current time is in.
        salt = ((uint32_t)([[NSDate date] timeIntervalSince1970] / 300)) * 300;
    
    if (MPTypes_ciphers == nil)
        MPTypes_ciphers = [NSDictionary dictionaryWithContentsOfURL:[[NSBundle mainBundle] URLForResource:@"ciphers"
                                                                                            withExtension:@"plist"]];
    
    // Determine the hash whose bytes will be used for calculating a password: md4(name-key)
    uint32_t nsalt = htonl(salt);
    trc(@"key hash from: %@-%@-%u", name, key, nsalt);
    NSData *keyHash = [[NSData dataByConcatenatingWithDelimitor:'-' datas:
                        [name dataUsingEncoding:NSUTF8StringEncoding],
                        key,
                        [NSData dataWithBytes:&nsalt length:sizeof(nsalt)],
                        nil] hashWith:PearlDigestSHA1];
    trc(@"key hash is: %@", keyHash);
    const char *keyBytes = keyHash.bytes;
    
    // Determine the cipher from the first hash byte.
    assert([keyHash length]);
    NSArray *typeCiphers = [[MPTypes_ciphers valueForKey:ClassNameFromMPElementType(type)]
                            valueForKey:NSStringFromMPElementType(type)];
    NSString *cipher = [typeCiphers objectAtIndex:htons(keyBytes[0]) % [typeCiphers count]];
    trc(@"type %d, ciphers: %@, selected: %@", type, typeCiphers, cipher);
    
    // Encode the content, character by character, using subsequent hash bytes and the cipher.
    assert([keyHash length] >= [cipher length] + 1);
    NSMutableString *content = [NSMutableString stringWithCapacity:[cipher length]];
    for (NSUInteger c = 0; c < [cipher length]; ++c) {
        uint16_t keyByte = htons(keyBytes[c + 1]);
        NSString *cipherClass = [cipher substringWithRange:NSMakeRange(c, 1)];
        NSString *cipherClassCharacters = [[MPTypes_ciphers valueForKey:@"MPCharacterClasses"] valueForKey:cipherClass];
        NSString *character = [cipherClassCharacters substringWithRange:NSMakeRange(keyByte % [cipherClassCharacters length], 1)];
        
        trc(@"class %@ has characters: %@, selected: %@", cipherClass, cipherClassCharacters, character);
        [content appendString:character];
    }
    
    return content;
}