/*
 *  Author: Jan Lehnardt <jan@apache.org>
 *  This is Apache 2.0 licensed free software
 */
#import "CouchDBXApplicationController.h"
#import "Sparkle/Sparkle.h"
#import "SUUpdaterDelegate.h"

@implementation CouchDBXApplicationController

-(BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app
{
  return YES;
}

-(void)applicationWillTerminate:(NSNotification *)notification
{
	[self ensureFullCommit];
}

- (void)windowWillClose:(NSNotification *)aNotification 
{
    [self stop];
}

-(void)applicationWillFinishLaunching:(NSNotification *)notification
{
	SUUpdater *updater = [SUUpdater sharedUpdater];
	SUUpdaterDelegate *updaterDelegate = [[SUUpdaterDelegate alloc] init];
	[updater setDelegate: updaterDelegate];
}

-(void)ensureFullCommit
{
	// find couch.uri file
	NSMutableString *urifile = [[NSMutableString alloc] init];
	[urifile appendString: [task currentDirectoryPath]]; // couchdbx-core
	[urifile appendString: @"/var/lib/couchdb/couch.uri"];

	// get couch uri
	NSString *uri = [NSString stringWithContentsOfFile:urifile encoding:NSUTF8StringEncoding error:NULL];

	// TODO: maybe parse out \n

	// get database dir
	NSString *databaseDir = [self applicationSupportFolder];

	// get ensure_full_commit.sh
	NSMutableString *ensure_full_commit_script = [[NSMutableString alloc] init];
	[ensure_full_commit_script appendString: [[NSBundle mainBundle] resourcePath]];
	[ensure_full_commit_script appendString: @"/ensure_full_commit.sh"];

	// exec ensure_full_commit.sh database_dir couch.uri
	NSArray *args = [[NSArray alloc] initWithObjects:databaseDir, uri, nil];
	NSTask *commitTask = [[NSTask alloc] init];
	[commitTask setArguments: args];
	[commitTask launch];
	[commitTask waitUntilExit];

	// yay!
}

-(void)awakeFromNib
{
    [browse setEnabled:NO];
	
	NSLayoutManager *lm;
	lm = [outputView layoutManager];
	[lm setDelegate:self];
	
	[webView setUIDelegate:self];
	
	[self launchCouchDB];
}

-(IBAction)start:(id)sender
{
    if([task isRunning]) {
      [self stop];
      return;
    } 
    
    [self launchCouchDB];
}

-(void)stop
{
    NSFileHandle *writer;
    writer = [in fileHandleForWriting];
    [writer writeData:[@"q().\n" dataUsingEncoding:NSASCIIStringEncoding]];
    [writer closeFile];
  
    [browse setEnabled:NO];
    [start setImage:[NSImage imageNamed:@"start.png"]];
    [start setLabel:@"start"];
}


/* found at http://www.cocoadev.com/index.pl?ApplicationSupportFolder */
- (NSString *)applicationSupportFolder {
    NSString *applicationSupportFolder = nil;
    FSRef foundRef;
    OSErr err = FSFindFolder(kUserDomain, kApplicationSupportFolderType, kDontCreateFolder, &foundRef);
    if (err == noErr) {
        unsigned char path[PATH_MAX];
        OSStatus validPath = FSRefMakePath(&foundRef, path, sizeof(path));
        if (validPath == noErr)
        {
            applicationSupportFolder = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:path length:(NSUInteger)strlen((char*)path)];
        }
    }
	applicationSupportFolder = [applicationSupportFolder stringByAppendingPathComponent:@"CouchbaseServer"];
    return applicationSupportFolder;
}

-(void)maybeSetDataDirs
{
	// determine data dir
	NSString *dataDir = [self applicationSupportFolder];
	// create if it doesn't exist
	if(![[NSFileManager defaultManager] fileExistsAtPath:dataDir]) {
		[[NSFileManager defaultManager] createDirectoryAtPath:dataDir withIntermediateDirectories:YES attributes:nil error:NULL];
	}

	// if data dirs are not set in local.ini
	NSMutableString *iniFile = [[NSMutableString alloc] init];
	[iniFile appendString:[[NSBundle mainBundle] resourcePath]];
	[iniFile appendString:@"/couchdbx-core/etc/couchdb/local.ini"];
    NSLog(@"Loading stuff from %@", iniFile);
	NSString *ini = [NSString stringWithContentsOfFile:iniFile encoding:NSUTF8StringEncoding error:NULL];
    assert(ini);
	NSRange found = [ini rangeOfString:dataDir];
	if(found.length == 0) {
		//   set them
		NSMutableString *newIni = [[NSMutableString alloc] init];
        assert(newIni);
		[newIni appendString: ini];
		[newIni appendString:@"[couchdb]\ndatabase_dir = "];
		[newIni appendString:dataDir];
		[newIni appendString:@"\nview_index_dir = "];
		[newIni appendString:dataDir];
		[newIni appendString:@"\n\n"];
		[newIni writeToFile:iniFile atomically:YES encoding:NSUTF8StringEncoding error:NULL];
		[newIni release];
	}
	[iniFile release];
	// done
}

-(void)launchCouchDB
{
	[self maybeSetDataDirs];
    [browse setEnabled:YES];
    [start setImage:[NSImage imageNamed:@"stop.png"]];
    [start setLabel:@"stop"];


	in = [[NSPipe alloc] init];
	out = [[NSPipe alloc] init];
	task = [[NSTask alloc] init];

	NSMutableString *launchPath = [[NSMutableString alloc] init];
	[launchPath appendString:[[NSBundle mainBundle] resourcePath]];
	[launchPath appendString:@"/couchdbx-core"];
	[task setCurrentDirectoryPath:launchPath];

	[launchPath appendString:@"/bin/couchdb"];
    NSLog(@"Launching '%@'", launchPath);
	[task setLaunchPath:launchPath];
	NSArray *args = [[NSArray alloc] initWithObjects:@"-i", nil];
	[task setArguments:args];
	[task setStandardInput:in];
	[task setStandardOutput:out];

	NSFileHandle *fh = [out fileHandleForReading];
	NSNotificationCenter *nc;
	nc = [NSNotificationCenter defaultCenter];

	[nc addObserver:self
					selector:@selector(dataReady:)
							name:NSFileHandleReadCompletionNotification
						 object:fh];
	
	[nc addObserver:self
					selector:@selector(taskTerminated:)
							name:NSTaskDidTerminateNotification
						object:task];

  	[task launch];
  	[outputView setString:@"Starting CouchDB...\n"];
  	[fh readInBackgroundAndNotify];
	sleep(1);
	[self openFuton];
}

-(void)taskTerminated:(NSNotification *)note
{
    [self cleanup];
}

-(void)cleanup
{
    [task release];
    task = nil;
    
    [in release];
    in = nil;
		[out release];
		out = nil;

    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

-(void)openFuton
{
	NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
	NSString *homePage = [info objectForKey:@"HomePage"];
	[webView setTextSizeMultiplier:1.3];
	[[webView mainFrame] loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:homePage]]];
}

-(IBAction)browse:(id)sender
{
	[self openFuton];
    //[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://127.0.0.1:5984/_utils/"]];
}

- (void)appendData:(NSData *)d
{
    NSString *s = [[NSString alloc] initWithData: d
                                        encoding: NSUTF8StringEncoding];
    NSTextStorage *ts = [outputView textStorage];
    [ts replaceCharactersInRange:NSMakeRange([ts length], 0) withString:s];
    [s release];
}

- (void)dataReady:(NSNotification *)n
{
    NSData *d;
    d = [[n userInfo] valueForKey:NSFileHandleNotificationDataItem];
    if ([d length]) {
      [self appendData:d];
    }
    if (task)
      [[out fileHandleForReading] readInBackgroundAndNotify];
}

- (void)layoutManager:(NSLayoutManager *)aLayoutManager didCompleteLayoutForTextContainer:(NSTextContainer *)aTextContainer atEnd:(BOOL)flag
{
	if (flag) {
		NSTextStorage *ts = [outputView textStorage];
		[outputView scrollRangeToVisible:NSMakeRange([ts length], 0)];
	}
}

- (void)webView:(WebView *)sender runOpenPanelForFileButtonWithResultListener:(id < WebOpenPanelResultListener >)resultListener
{
	[self openChooseFileDialogWithListener: resultListener
			allowMultipleFiles: FALSE];
}
- (void)webView:(WebView *)sender runOpenPanelForFileButtonWithResultListener:(id < WebOpenPanelResultListener >)resultListener allowMultipleFiles:(BOOL)allowMultipleFiles
{
	[self openChooseFileDialogWithListener: resultListener
			allowMultipleFiles: allowMultipleFiles];
}

#if __MAC_OS_X_VERSION_MAX_ALLOWED >= 1060 
	#define MULTIPLE_SELECTION_POSSIBLE TRUE
#else
	#define MULTIPLE_SELECTION_POSSIBLE FALSE
#endif
- (void)openChooseFileDialogWithListener: (id < WebOpenPanelResultListener >)resultListener allowMultipleFiles: (BOOL)multipleSelection
{
	NSOpenPanel* openDlg = [NSOpenPanel openPanel];
	[openDlg setCanChooseFiles:YES];
	[openDlg setCanChooseDirectories:NO];
	[openDlg setAllowsMultipleSelection: (multipleSelection && MULTIPLE_SELECTION_POSSIBLE)];
	NSInteger result = [openDlg runModal];
	if (result == NSFileHandlingPanelOKButton) {
		NSArray* files = [openDlg URLs];
#if MULTIPLE_SELECTION_POSSIBLE
		NSInteger filesNumber = [files count];
		if (filesNumber == 1) {
#endif
			NSURL* fileURL = [files objectAtIndex:0];
			NSString* path = [fileURL path];
			[resultListener chooseFilename:path ];
#if MULTIPLE_SELECTION_POSSIBLE			
		} else {
			NSMutableArray* fileNames = [NSMutableArray arrayWithCapacity:filesNumber];
			for (NSURL* fileURL in files) {
				NSString* path = [fileURL path];
				[fileNames addObject:path];
			}
			[resultListener chooseFilenames: fileNames];
		} 
#endif		
	} else {
		[resultListener cancel];
	}
}

- (void)webView:(WebView *)sender runJavaScriptAlertPanelWithMessage:(NSString *)message initiatedByFrame:(WebFrame *)frame
{
	NSRunInformationalAlertPanel(nil, message, nil, nil, nil);
}

@end
