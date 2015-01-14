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
    
    CDTPullerByDocId *p1 = [[CDTPullerByDocId alloc] initWithSource:self.primaryRemoteDatabaseURL
                                                             target:self.datastore
                                                       docIdsToPull:filterDocIds];
    
    dispatch_semaphore_t latch1 = dispatch_semaphore_create(0);
    p1.completionBlock = ^{
        dispatch_semaphore_signal(latch1);
    };
    [p1 start];
    
    long value1 = dispatch_semaphore_wait(latch1, dispatch_walltime(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
    NSLog(@"(T) Test thread did wait on latch (timeout=%@)", value1 == 0 ? @"NO" : @"YES");
    
    
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
    
    CDTPullerByDocId *p2 = [[CDTPullerByDocId alloc] initWithSource:self.primaryRemoteDatabaseURL
                                                             target:self.datastore
                                                       docIdsToPull:filterDocIds];
    
    dispatch_semaphore_t latch2 = dispatch_semaphore_create(0);
    p2.completionBlock = ^{
        dispatch_semaphore_signal(latch2);
    };
    [p2 start];
    
    long value2 = dispatch_semaphore_wait(latch2, dispatch_walltime(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
    NSLog(@"(T) Test thread did wait on latch (timeout=%@)", value2 == 0 ? @"NO" : @"YES");
    
    for (CDTDocumentRevision *rev in [self.datastore getAllDocuments]) {
        XCTAssertTrue([rev.revId hasPrefix:@"2-"], @"rev id does not start 2-");
    }
    
    XCTAssertEqual([self.datastore.database lastSequence], 8ll, @"Incorrect sequence number");
    XCTAssertEqual(self.datastore.documentCount, 4ul,
                   @"Incorrect number of documents updated");
}


#pragma mark helpers 

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

@end
