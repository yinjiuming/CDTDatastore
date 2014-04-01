//
//  CDTConflictResolver.h
//
//
//  Created by G. Adam Cox on 11/03/2014.
//  Copyright (c) 2014 Cloudant. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.
//
#import <Foundation/Foundation.h>

@class CDTDocumentRevision;

/**
 Protocol adopted by classes that implement a conflict resolution algorithm.
 
 Implementing this protocol allows developers to control how to 
 manage a document with a conflicted revision history. The class should be 
 supplied as an argument to 
 
 CDTDatastore+Conflicts resolveConflctsForDocument:(NSString*)docId
                                         resovlver:(CDTConflictResolver*)resolver
                                             error:(NSError **)error
 
 which is intended to be called within a loop iterating over the document IDs with conflicts,
 obtained with CDTDatastore -getConflictedDocumentIds.
 
 @see CDTDatastore+Conflicts
 */

@protocol CDTConflictResolver

/**
 *
 * This method receives the document ID and an NSArray of CDTDocumentRevision
 * objects and is intended to be called by CDTDatastore+Conflicts -resolveConflictsForDocument.
 * The NSArray includes all conflicting revisions of this document,
 * including the current winner, but not in any particular order.
 *
 * The implementation of this method should examine the conflicts and return
 * a winning CDTDocumentRevision object.
 *
 * When called by CDTDatastore+Conflicts -resolveConflictsForDocument,
 * the returned CDTDocumentRevision, barring any errors, 
 * will be added to the document tree as the child of the current winner, and all 
 * the other revisions will be appended by a deleted revision.
 *
 * The output of this method should be deterministic, that is, for the given docId and 
 * conflict set, the same new revision should be returned for all calls. It also shouldn't have 
 * externally visible effects to the database, as we don't guarantee that the 
 * returned revision will be amended to the document tree (there could be an error).
 *
 * You may also delete the document by setting the CDTDocumentRevision.deleted property.
 *
 * If returned CDTDocumentRevision* is nil, nothing is changed in the database.
 *
 * @param docId id of the document with conflicts
 * @param conflicts list of conflicted CDTDocumentRevision, including
 *                  current winner 
 * @return resolved CDTDocumentRevision
 *
 * @see
 */
-(CDTDocumentRevision *)resolve:(NSString*)docId
                      conflicts:(NSArray*)conflicts;


@end
