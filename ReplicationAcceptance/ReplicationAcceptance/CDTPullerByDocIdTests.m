//
//  CDTPullerByDocIdTests.m
//  ReplicationAcceptance
//
//  Created by Michael Rhodes on 14/01/2015.
//
//

#import <XCTest/XCTest.h>

#import <CloudantSync.h>
#import <UNIRest.h>
#import <TRVSMonitor.h>

#import "CloudantReplicationBase.h"
#import "CloudantReplicationBase+CompareDb.h"
#import "ReplicationAcceptance+CRUD.h"
#import "ReplicatorDelegates.h"
#import "ReplicatorURLProtocol.h"
#import "ReplicatorURLProtocolTester.h"

#import "CDTDatastoreManager.h"
#import "CDTDatastore.h"
#import "CDTDocumentBody.h"
#import "CDTDocumentRevision.h"
#import "CDTPullReplication.h"
#import "CDTPushReplication.h"
#import "TDReplicatorManager.h"
#import "TDReplicator.h"
#import "CDTReplicator.h"
#import "CDTPullerByDocId.h"

@interface CDTPullerByDocIdTests : CloudantReplicationBase

@property (nonatomic, strong) CDTDatastore *datastore;
@property (nonatomic, strong) CDTReplicatorFactory *replicatorFactory;

@property (nonatomic, strong) NSURL *primaryRemoteDatabaseURL;

/** This database is used as the primary remote database. Some tests create further
 databases, but all use this one.
 */
@property (nonatomic, strong) NSString *primaryRemoteDatabaseName;

@end

@implementation CDTPullerByDocIdTests

#pragma mark Setup/teardown

- (void)setUp
{
    [super setUp];
    
    // Create local and remote databases, start the replicator
    
    NSError *error;
    self.datastore = [self.factory datastoreNamed:@"test" error:&error];
    XCTAssertNotNil(self.datastore, @"datastore is nil");
    
    self.primaryRemoteDatabaseName = [NSString stringWithFormat:@"%@-test-database-%@",
                                      self.remoteDbPrefix,
                                      [CloudantReplicationBase generateRandomString:5]];
    self.primaryRemoteDatabaseURL = [self.remoteRootURL URLByAppendingPathComponent:self.primaryRemoteDatabaseName];
    [self createRemoteDatabase:self.primaryRemoteDatabaseName instanceURL:self.remoteRootURL];
    
    self.replicatorFactory = [[CDTReplicatorFactory alloc] initWithDatastoreManager:self.factory];
    
}

- (void)tearDown
{
    // Tear-down code here.
    
    // Delete remote database, stop the replicator.
    [self deleteRemoteDatabase:self.primaryRemoteDatabaseName instanceURL:self.remoteRootURL];
    
    self.datastore = nil;
    
    self.replicatorFactory = nil;
    
    [super tearDown];
}

#pragma mark Replication helper methods

- (void)replicateFrom:(NSURL*)source
                   to:(CDTDatastore*)target
               docIds:(NSArray*)docIds
{
    
    CDTPullerByDocId *p1 = [[CDTPullerByDocId alloc] initWithSource:source
                                                             target:target
                                                       docIdsToPull:docIds];
    
    dispatch_semaphore_t latch1 = dispatch_semaphore_create(0);
    p1.completionBlock = ^{
        dispatch_semaphore_signal(latch1);
    };
    [p1 start];
    
    dispatch_time_t wait_until = dispatch_walltime(DISPATCH_TIME_NOW, 600 * NSEC_PER_SEC);
    long value1 = dispatch_semaphore_wait(latch1, wait_until);
    NSLog(@"(T) Test thread did wait on latch (timeout=%@)", value1 == 0 ? @"NO" : @"YES");
}

#pragma mark Test we bring in only given docs

-(void) testPullClientFilterUpdates2 {
    // create n docs and pull a subset of them, filtered by ID
    // update them and pull the same subset, filtered by ID
    
    // Create docs in remote database
    NSLog(@"Creating documents...");
    
    int ndocs = 50; //don't need 100k docs
    
    [self createRemoteDocs:ndocs];
    
    NSArray *filterDocIds = @[[NSString stringWithFormat:@"doc-%i", 1],
                              [NSString stringWithFormat:@"doc-%i", 3],
                              [NSString stringWithFormat:@"doc-%i", 13],
                              [NSString stringWithFormat:@"doc-%i", 23],
                              [NSString stringWithFormat:@"doc-%i", 70]];
    
    [self replicateFrom:self.primaryRemoteDatabaseURL
                     to:self.datastore
                 docIds:filterDocIds];
    
    XCTAssertEqual([self.datastore.database lastSequence], 4ll, @"Incorrect sequence number");
    XCTAssertEqual(self.datastore.documentCount, 4ul,
                   @"Incorrect number of documents created");
    
    // now do some updates
    for (CDTDocumentRevision *rev in [self.datastore getAllDocuments]) {
        NSMutableDictionary *dict = [rev.body mutableCopy];
        [dict setValue:rev.revId forKey:@"_rev"];
        [dict setValue:@YES forKey:@"updated"];
        [self createRemoteDocWithId:rev.docId body:dict];
    }
    
    [self replicateFrom:self.primaryRemoteDatabaseURL
                     to:self.datastore
                 docIds:filterDocIds];
    
    for (CDTDocumentRevision *rev in [self.datastore getAllDocuments]) {
        XCTAssertTrue([rev.revId hasPrefix:@"2-"], @"rev id does not start 2-");
    }
    
    XCTAssertEqual([self.datastore.database lastSequence], 8ll, @"Incorrect sequence number");
    XCTAssertEqual(self.datastore.documentCount, 4ul,
                   @"Incorrect number of documents updated");
}

-(void) testReplicateManyDocs {
    // create n docs and pull a subset of them, filtered by ID
    // update them and pull the same subset, filtered by ID
    
    // Create docs in remote database
    NSLog(@"Creating documents...");
    
    int ndocs = 5000;
    
    [self createRemoteDocs:ndocs];
    
    NSMutableArray *filterDocIds = [NSMutableArray array];
    for (int i = 1; i <= ndocs; i +=2) {
        [filterDocIds addObject:[NSString stringWithFormat:@"doc-%i", i]];
    }
    
    [self replicateFrom:self.primaryRemoteDatabaseURL
                     to:self.datastore
                 docIds:filterDocIds];
    
    XCTAssertEqual([self.datastore.database lastSequence], 
                   filterDocIds.count, 
                   @"Incorrect sequence number");
    XCTAssertEqual(self.datastore.documentCount, filterDocIds.count,
                   @"Incorrect number of documents created");
    
    // now do some updates
    for (CDTDocumentRevision *rev in [self.datastore getAllDocuments]) {
        NSMutableDictionary *dict = [rev.body mutableCopy];
        [dict setValue:rev.revId forKey:@"_rev"];
        [dict setValue:@YES forKey:@"updated"];
        [self createRemoteDocWithId:rev.docId body:dict];
    }
    
    [self replicateFrom:self.primaryRemoteDatabaseURL
                     to:self.datastore
                 docIds:filterDocIds];
    
    for (CDTDocumentRevision *rev in [self.datastore getAllDocuments]) {
        XCTAssertTrue([rev.revId hasPrefix:@"2-"], @"rev id does not start 2-");
    }
    
    XCTAssertEqual([self.datastore.database lastSequence], 
                   filterDocIds.count * 2, 
                   @"Incorrect sequence number");
    XCTAssertEqual(self.datastore.documentCount, 
                   filterDocIds.count,
                   @"Incorrect number of documents updated");
}

#pragma mark Attachments

- (void)testReplicateSeveralRemoteDocumentsWithAttachments
{
    
    // { document ID: number of attachments to create }
    NSDictionary *docs = @{@"attachments1": @(1),
                           @"attachments3": @(3),
                           @"attachments4": @(4)};
    NSMutableArray *docIds = [NSMutableArray array];
    for (NSString* docId in [docs keyEnumerator]) {
        
        [docIds addObject:docId];
        NSString *revId = [self createRemoteDocumentWithId:docId
                                                      body:@{@"hello": @"world"}
                                               databaseURL:self.primaryRemoteDatabaseURL];
        
        NSInteger nAttachments = [docs[docId] integerValue];
        for (NSInteger i = 1; i <= nAttachments; i++) {
            NSString *name = [NSString stringWithFormat:@"txtDoc%li", (long)i];
            NSData *txtData = [@"0123456789" dataUsingEncoding:NSUTF8StringEncoding];
            revId = [self addAttachmentToRemoteDocumentWithId:docId
                                                        revId:revId
                                               attachmentName:name
                                                  contentType:@"text/plain"
                                                         data:txtData
                                                  databaseURL:self.primaryRemoteDatabaseURL];
        }
    }
    
    //
    // Replicate
    //
    
    [self replicateFrom:self.primaryRemoteDatabaseURL
                     to:self.datastore
                 docIds:docIds];
    
    //
    // Checks
    //
    
    CDTDocumentRevision *rev;
    
    rev = [self.datastore getDocumentWithId:@"attachments1"
                                      error:nil];
    XCTAssertTrue([self isNumberOfAttachmentsForRevision:rev equalTo:(NSUInteger)1],
                  @"Incorrect number of attachments");
    
    rev = [self.datastore getDocumentWithId:@"attachments3"
                                      error:nil];
    XCTAssertTrue([self isNumberOfAttachmentsForRevision:rev equalTo:(NSUInteger)3],
                  @"Incorrect number of attachments");
    
    rev = [self.datastore getDocumentWithId:@"attachments4"
                                      error:nil];
    XCTAssertTrue([self isNumberOfAttachmentsForRevision:rev equalTo:(NSUInteger)4],
                  @"Incorrect number of attachments");
    
    XCTAssertTrue([self compareAttachmentsForCurrentRevisions:self.datastore 
                                                 withDatabase:self.primaryRemoteDatabaseURL],
                  @"Local and remote database attachment comparison failed");
}



- (void)testReplicateManyRemoteAttachments
{
    NSUInteger nAttachments = 100;
    
    // Contains {attachmentName: attachmentContent} for later checking
    NSMutableDictionary *originalAttachments = [NSMutableDictionary dictionary];
    
    
    //
    // Upload attachments to remote document
    //
    
    NSString *docId = @"document1";
    
    NSString *revId = [self createRemoteDocumentWithId:docId
                                                  body:@{@"hello": @"world"}
                                           databaseURL:self.primaryRemoteDatabaseURL];
    
    for (NSInteger i = 1; i <= nAttachments; i++) {
        NSString *name = [NSString stringWithFormat:@"txtDoc%li", (long)i];
        NSString *content = [NSString stringWithFormat:@"doc%li", (long)i];
        NSData *txtData = [content dataUsingEncoding:NSUTF8StringEncoding];
        revId = [self addAttachmentToRemoteDocumentWithId:docId
                                                    revId:revId
                                           attachmentName:name
                                              contentType:@"text/plain"
                                                     data:txtData
                                              databaseURL:self.primaryRemoteDatabaseURL];
        originalAttachments[name] = txtData;
    }
    
    //
    // Replicate
    //
    
    [self replicateFrom:self.primaryRemoteDatabaseURL
                     to:self.datastore
                 docIds:@[docId]];
    
    //
    // Checks
    //
    
    CDTDocumentRevision *rev;
    rev = [self.datastore getDocumentWithId:docId
                                      error:nil];
    XCTAssertTrue([self isNumberOfAttachmentsForRevision:rev equalTo:nAttachments],
                  @"Incorrect number of attachments");
    
    for (NSString *attachmentName in [originalAttachments keyEnumerator]) {
        
        CDTAttachment *a = [[rev attachments] objectForKey:attachmentName];
        
        XCTAssertNotNil(a, @"No attachment named %@", attachmentName);
        
        NSData *data = [a dataFromAttachmentContent];
        NSData *originalData = originalAttachments[attachmentName];
        
        XCTAssertEqualObjects(data, originalData, @"attachment content didn't match");
    }
}


#pragma mark Helpers 

- (void)createRemoteDocs:(NSInteger)count
{
    [self createRemoteDocs:count suffixFrom:1];
}

-(void) createRemoteDocs:(NSInteger)count suffixFrom:(NSInteger)start
{
    NSMutableArray *docs = [NSMutableArray array];
    NSUInteger currentIndex;
    for (long i = 0; i < count; i++) {
        currentIndex = start+i;
        NSString *docId = [NSString stringWithFormat:@"doc-%li", currentIndex];
        NSDictionary *dict = @{@"_id": docId, 
                               @"hello": @"world", 
                               @"docnum":[NSNumber numberWithLong:currentIndex]};
        [docs addObject:dict];
    }
    
    NSDictionary *bulk_json = @{@"docs": docs};
    
    NSURL *bulk_url = [self.primaryRemoteDatabaseURL URLByAppendingPathComponent:@"_bulk_docs"];
    
    NSDictionary* headers = @{@"accept": @"application/json",
                              @"content-type": @"application/json"};
    UNIHTTPJsonResponse* response = [[UNIRest postEntity:^(UNIBodyRequest* request) {
        [request setUrl:[bulk_url absoluteString]];
        [request setHeaders:headers];
        [request setBody:[NSJSONSerialization dataWithJSONObject:bulk_json
                                                         options:0
                                                           error:nil]];
    }] asJson];
    //    NSLog(@"%@", response.body.array);
    XCTAssertTrue([response.body.array count] == count, @"Remote db has wrong number of docs");
}

-(NSString*) createRemoteDocWithId:(NSString *)docId body:(NSDictionary*)body
{
    NSURL *docURL = [self.primaryRemoteDatabaseURL URLByAppendingPathComponent:docId];
    
    NSDictionary* headers = @{@"accept": @"application/json",
                              @"content-type": @"application/json"};
    UNIHTTPJsonResponse* response = [[UNIRest putEntity:^(UNIBodyRequest* request) {
        [request setUrl:[docURL absoluteString]];
        [request setHeaders:headers];
        [request setBody:[NSJSONSerialization dataWithJSONObject:body
                                                         options:0
                                                           error:nil]];
    }] asJson];
    XCTAssertTrue([response.body.object objectForKey:@"ok"] != nil, @"Create document failed");
    return [response.body.object objectForKey:@"rev"];
}

- (BOOL)isNumberOfAttachmentsForRevision:(CDTDocumentRevision*)rev
                                 equalTo:(NSUInteger)expected
{
    NSArray *attachments = [self.datastore attachmentsForRev:rev
                                                       error:nil];
    return [attachments count] == expected;
}

@end
