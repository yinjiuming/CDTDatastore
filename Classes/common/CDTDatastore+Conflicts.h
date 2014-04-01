//
//  CDTDatastore+Conflicts.h
//
//
//  Created by G. Adam Cox on 13/03/2014.
//  Copyright (c) 2014 Cloudant. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CDTDatastore.h"
@protocol CDTConflictResolver;

@interface CDTDatastore (Conflicts)



/**
 * Get all document ids in the datastore that have a conflict in its revision tree.
 *
 * Returns an array of NSString* document ids.
 */
-(NSArray*) getConflictedDocumentIds;

/**
 *
 * Resolve conflicts for specified Document using an object
 * that conforms to the CDTConflictResolver protocol
 *
 * The resolution of the document occurs entirely within a single transaction
 * to the underlying SQL database. Thus, the delegate CDTConflictResolver -resolve:error
 * method should be completely deterministic and should never modify or even queue a
 * new database query. Doing so will create a blocking transaction to the database --
 * the query will never excute and this method will never return.
 *
 * @param docId id of Document to resolve conflicts
 * @param resolver the CDTConflictResolver-conforming object
 used to resolve conflicts
 * @param error  NSError** for error reporting
 * @return YES/NO depending on success.
 *
 * @see CDTConflictResolver
 */
-(BOOL) resolveConflictsForDocument:(NSString*)docId
                           resolver:(NSObject<CDTConflictResolver>*)resolver
                              error:(NSError * __autoreleasing *)error;

@end
