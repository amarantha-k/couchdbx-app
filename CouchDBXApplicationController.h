/*
    Author: Jan Lehnardt <jan@apache.org>
    This is Apache 2.0 licensed free software
*/
#import <Cocoa/Cocoa.h>

@interface CouchDBXApplicationController : NSObject{
    NSStatusItem *statusBar;
    IBOutlet NSMenu *statusMenu;
    NSTask *task;
    NSPipe *in, *out;
}

-(IBAction)start:(id)sender;
-(IBAction)browse:(id)sender;

-(void)launchCouchDB;
-(void)stop;
-(void)openFuton;
-(void)taskTerminated:(NSNotification *)note;
-(void)cleanup;
-(void)ensureFullCommit;
-(NSString *)applicationSupportFolder;

@end
