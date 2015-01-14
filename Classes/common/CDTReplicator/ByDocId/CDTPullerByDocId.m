//
//  CDTPullerByDocId.m
//  
//
//  Created by Michael Rhodes on 14/01/2015.
//
//

#import "CDTPullerByDocId.h"

#import "CDTDatastore.h"
#import "CDTLogging.h"

#import "TDMultipartDownloader.h"
#import "TDMisc.h"
#import "TD_Database.h"
#import "TD_Database+Insertion.h"
#import "TDAuthorizer.h"
#import "TDJSON.h"

#import "ExceptionUtils.h"
#import "MYBlockUtils.h"

// Maximum number of revision IDs to pass in an "?atts_since=" query param (from TDPuller.m)
#define kMaxNumberOfAttsSince 50u

@interface CDTPullerByDocId ()

/** Set with doc Ids. Using a set ensures we don't do a doc twice. */
@property (nonatomic,strong) NSSet *docIdsToPull;

@property (nonatomic,strong) NSURL *source;

@property (nonatomic,strong) CDTDatastore *target;

@property (nonatomic,strong) TDBasicAuthorizer *authorizer;

@property (nonatomic,strong) NSDictionary *requestHeaders;

@property (nonatomic) NSUInteger changesProcessed;

@property (nonatomic) NSUInteger revisionsFailed;

@property (nonatomic,strong) NSError *error;

@property (nonatomic) NSUInteger asyncTaskCount;

@property (nonatomic) BOOL active;

@property (nonatomic, strong) NSThread *replicatorThread;

@property (nonatomic,strong) NSString *sessionID;

@end

@implementation CDTPullerByDocId



- (instancetype)initWithSource:(NSURL*)source
                       target:(CDTDatastore*)target
                 docIdsToPull:(NSArray*)docIdsToPull
{
    self = [super init];
    if (self) {
        _source = source;
        _target = target;
        _active = NO;
        _stopRunLoop = NO;
        
        _docIdsToPull = [NSSet setWithArray:docIdsToPull];
    }
    return self;
}

- (BOOL)start {
    if(_replicatorThread){
        return YES;  // already started
    }
    
    self.sessionID = @"not unique yet";
    
    _replicatorThread = [[NSThread alloc] initWithTarget: self
                                                selector: @selector(runReplicatorThread)
                                                  object: nil];
    CDTLogInfo(CDTREPLICATION_LOG_CONTEXT, @"Starting TDReplicator thread %@ ...", _replicatorThread);
    [_replicatorThread start];
    
    __weak CDTPullerByDocId *weakSelf = self;
    [self queue:^{
        __strong CDTPullerByDocId *strongSelf = weakSelf;
        [strongSelf startReplicatorTasks];
    }];
    
    return YES;
}

- (void)queue:(void(^)())block {
    Assert(_replicatorThread, @"-queue: called after -stop");
    MYOnThread(_replicatorThread, block);
}


/**
 * Start a thread for each replicator
 * Taken from TDServer.m.
 */
- (void) runReplicatorThread {
    @autoreleasepool {
        CDTLogInfo(CDTREPLICATION_LOG_CONTEXT, @"TDReplicator thread starting...");
        
        [[NSThread currentThread]
         setName:[NSString stringWithFormat:@"CDTPullerByDocId: %@", self.sessionID]];
        
#ifndef GNUSTEP
        // Add a no-op source so the runloop won't stop on its own:
        CFRunLoopSourceContext context = {}; // all zeros
        CFRunLoopSourceRef source = CFRunLoopSourceCreate(NULL, 0, &context);
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, kCFRunLoopDefaultMode);
        CFRelease(source);
#endif
        
        // Now run:
        while (!_stopRunLoop && [[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode
                                                         beforeDate: [NSDate dateWithTimeIntervalSinceNow:0.1]])
            ;
        
        CDTLogInfo(CDTREPLICATION_LOG_CONTEXT, @"TDReplicator thread exiting");
    }
}

/** Assumes it's running on the replicator's thread, because all the networking code uses
 the current thread's runloop. */
-(BOOL)startReplicatorTasks
{
    // From TDReplicator
    // If client didn't set an authorizer, use basic auth if credential is available:
    if (!_authorizer) {
        _authorizer = [[TDBasicAuthorizer alloc] initWithURL:self.source];
        if (_authorizer) {
            CDTLogWarn(CDTREPLICATION_LOG_CONTEXT, @"%@: Found credential, using %@", self, _authorizer);
        }
    }
    // END from TDReplicator
    
    // Add UA to request headers
    NSMutableDictionary* headers = $mdict({ @"User-Agent", [TDRemoteRequest userAgentHeader] });
    [headers addEntriesFromDictionary:_requestHeaders];
    self.requestHeaders = headers;
    
    // Sync for now
    for (NSString *docId in self.docIdsToPull) {
        [self pullRemoteRevision:docId ignoreMissingDocs:YES immediatelyInsert:YES];
    }
    return YES;
}

/*  Fetches the contents of a revision from the remote db, including its parent revision ID.
    The contents are stored into rev.properties.
    Adapted from TDPuller.m 
 */
- (void) pullRemoteRevision:(NSString*)docId
          ignoreMissingDocs:(BOOL)ignoreMissingDocs
          immediatelyInsert:(BOOL)immediatelyInsert
{
    [self asyncTaskStarted];
//    ++_httpConnectionCount;
    
    TD_Database *_db = self.target.database;
    
    // Construct a query. We want the revision history, and the bodies of attachments that have
    // been added since the latest revisions we have locally.
    // See: http://wiki.apache.org/couchdb/HTTP_Document_API#GET
    // See: http://wiki.apache.org/couchdb/HTTP_Document_API#Getting_Attachments_With_a_Document
    NSString* path = $sprintf(@"%@?revs=true&attachments=true", TDEscapeID(docId));
    
    TD_Revision *rev = [_db getDocumentWithID:docId revisionID:nil];
    
    // Use atts_since so we don't pull attachments that we should already have
    NSArray* knownRevs = [_db getPossibleAncestorRevisionIDs: rev limit: kMaxNumberOfAttsSince];
    if (knownRevs.count > 0) {
        path = [path stringByAppendingFormat:@"&atts_since=%@", joinQuotedEscaped(knownRevs)];
    }
    CDTLogVerbose(CDTREPLICATION_LOG_CONTEXT, @"%@: GET %@", self, path);
    
    // Under ARC, using variable dl directly in the block given as an argument to initWithURL:...
    // results in compiler error (could be undefined variable)
    __weak CDTPullerByDocId* weakSelf = self;
    TDMultipartDownloader* dl;
    dl = [[TDMultipartDownloader alloc] initWithURL: TDAppendToURL(self.source, path)
                                           database: _db
                                     requestHeaders: self.requestHeaders
                                       onCompletion:
          ^(TDMultipartDownloader* dl, NSError *error) {
              __strong CDTPullerByDocId *strongSelf = weakSelf;
              
              // OK, now we've got the response revision:
              if (error) {
                  // if ignoreMissingDocs is true, we know that some requests might 404
                  if (!(ignoreMissingDocs && error.code == 404)) {
                      strongSelf.error = error;
                      [strongSelf revisionFailed];
                  }
                  strongSelf.changesProcessed++;
              } else {
                  TD_Revision* gotRev = [TD_Revision revisionWithProperties: dl.document];
                  gotRev.sequence = rev.sequence;
                  [strongSelf insertDownloads:@[gotRev]];  // increments changesProcessed
              }
              
              // Note that we've finished this task:
//              [strongSelf removeRemoteRequest:dl];
              [strongSelf asyncTasksFinished:1];
//              --_httpConnectionCount;
          }
          ];
//    [self addRemoteRequest: dl];
    dl.authorizer = _authorizer;
    [dl start];
}

/* Adapted from TDPuller.m */
static NSString* joinQuotedEscaped(NSArray* strings)
{
    if (strings.count == 0) return @"[]";
    NSString* json = [TDJSON stringWithJSONObject:strings options:0 error:NULL];
    return TDEscapeURLParam(json);
}

/* Adapted from TDPuller.m */
- (void)asyncTaskStarted
{
    if (_asyncTaskCount++ == 0) [self updateActive];
}

/* Adapted from TDPuller.m */
- (void)asyncTasksFinished:(NSUInteger)numTasks
{
    _asyncTaskCount -= numTasks;
    Assert(_asyncTaskCount >= 0);
    if (_asyncTaskCount == 0) {
        [self updateActive];
    }
}

/* Adapted from TDPuller.m */
- (void)updateActive
{
    BOOL active = _asyncTaskCount > 0;
    if (active != _active) {
        self.active = active;
//        [self postProgressChanged];
        if (!_active) {
            if (self.completionBlock) {
                self.completionBlock();
            }
            _stopRunLoop = YES;
            _replicatorThread = nil;
        }
    }
}



// This will be called when _downloadsToInsert fills up:
/* Adapted from TDPuller.m */
- (void)insertDownloads:(NSArray*)downloads
{
    CDTLogVerbose(CDTREPLICATION_LOG_CONTEXT, @"%@ inserting %u revisions...", self,
                  (unsigned)downloads.count);
    CFAbsoluteTime time = CFAbsoluteTimeGetCurrent();
    
    TD_Database *_db = self.target.database;
    
    //    [_db beginTransaction];
    //    BOOL success = NO;
    @try {
        downloads = [downloads sortedArrayUsingSelector:@selector(compareSequences:)];
        for (TD_Revision* rev in downloads) {
            @autoreleasepool
            {
                NSArray* history = [TD_Database parseCouchDBRevisionHistory:rev.properties];
                if (!history && rev.generation > 1) {
                    CDTLogWarn(CDTREPLICATION_LOG_CONTEXT,
                               @"%@: Missing revision history in response for %@", self, rev);
                    self.error = TDStatusToNSError(kTDStatusUpstreamError, nil);
                    [self revisionFailed];
                    continue;
                }
                CDTLogVerbose(CDTREPLICATION_LOG_CONTEXT, @"%@ inserting %@ %@", self, rev.docID,
                              [history my_compactDescription]);
                
                // Insert the revision:
                int status = [_db forceInsert:rev revisionHistory:history source:self.source];
                if (TDStatusIsError(status)) {
                    if (status == kTDStatusForbidden)
                        CDTLogInfo(CDTREPLICATION_LOG_CONTEXT, @"%@: Remote rev failed validation: %@",
                                   self, rev);
                    else {
                        CDTLogWarn(CDTREPLICATION_LOG_CONTEXT, @"%@ failed to write %@: status=%d", self,
                                   rev, status);
                        [self revisionFailed];
                        self.error = TDStatusToNSError(status, nil);
                        continue;
                    }
                }
            }
        }
        
        CDTLogVerbose(CDTREPLICATION_LOG_CONTEXT, @"%@ finished inserting %u revisions", self,
                      (unsigned)downloads.count);
        
        //        success = YES;
    }
    @catch (NSException* x) { MYReportException(x, @"%@: Exception inserting revisions", self); }
    //    @finally {
    //        [_db endTransaction: success];
    //    }
    
    time = CFAbsoluteTimeGetCurrent() - time;
    CDTLogInfo(CDTREPLICATION_LOG_CONTEXT, @"%@ inserted %u revs in %.3f sec (%.1f/sec)", self,
               (unsigned)downloads.count, time, downloads.count / time);
    
    self.changesProcessed += downloads.count;
//    [self asyncTasksFinished:downloads.count];
}

- (void)revisionFailed
{
    // Remember that some revisions failed to transfer, so we can later retry.
    ++_revisionsFailed;
}

@end
