//
//  CDTTopLevelKeyIndexer.h
//  Project
//
//  Created by Adam Cox on 4/25/14.
//  Copyright (c) 2014 Cloudant. All rights reserved.
//

#import "CDTTopLevelKeyIndexer.h"

#import "CDTDocumentRevision.h"

@implementation CDTTopLevelKeyIndexer

-(NSArray*)valuesForRevision:(CDTDocumentRevision*)revision
                   indexName:(NSString*)indexName
{
    NSDictionary *jsonDoc = [revision documentAsDictionary];
    
    NSString *value = [jsonDoc objectForKey:indexName];

    if (value != nil) {
        return [value componentsSeparatedByString:@" "];
    }
    
    return nil;
}

@end
