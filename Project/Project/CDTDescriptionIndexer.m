//
//  CDTDescriptionIndexer.m
//  Project
//
//  Created by Adam Cox on 4/25/14.
//  Copyright (c) 2014 Cloudant. All rights reserved.
//

#import "CDTDescriptionIndexer.h"

#import "CDTDocumentRevision.h"

@implementation CDTDescriptionIndexer

-(NSArray*)valuesForRevision:(CDTDocumentRevision*)revision
                   indexName:(NSString*)indexName
{
    NSDictionary *jsonDoc = [revision documentAsDictionary];
    
    NSString *value = [jsonDoc objectForKey:@"description"];

    if (value != nil) {
        return [value componentsSeparatedByString:@" "];
    }
    
    return nil;
}

@end
