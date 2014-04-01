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
 * The NSArray includes all conflicting revisions of this document, including the current 
 * winner, but not in any particular order.
 *
 * If there are no conflicts for this document ID, then CDTConflictResolver -resolve:conflicts
 * will not be called.
 *
 * The implementation of this method should examine the conflicts and return
 * the winning CDTDocumentRevision object. CDTDocumentRevision is an immutable
 * object. Until the development of CDTMutableDocumentRevision is complete (it is on
 * the roadmap to be completed soon), implementations should simply
 * returning the winning CDTDocumentRevision object. Additionally, due to this
 * restriction, documents may not be deleted with this conflict resolution mechanism.
 *
 * When called by CDTDatastore+Conflicts -resolveConflictsForDocument,
 * the returned CDTDocumentRevision, barring any errors, 
 * will be added to the document tree as the child of the current winner, and all 
 * other conflicting revisions will be deleted.
 *
 * The output of this method should be deterministic. That is, for the given document ID and
 * conflict set, the same revision should be always be returned. It also shouldn't have
 * externally visible effects, as we don't guarantee that the returned revision will be 
 * amended to the document tree (there could be an error).
 *
 * Additionally, this method should not modify or even attempt to query the database 
 * (via calls to CDTDatastore methods). Doing so will create a blocking transaction to 
 * the database and the code will never excute.
 *
 * Finally, if nil is returned by the implementation of this method, nothing will be 
 * changed in the database.
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
