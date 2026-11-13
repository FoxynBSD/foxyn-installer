#import <AppKit/AppKit.h>

@interface InstallerController : NSObject <NSApplicationDelegate>
{
  NSWindow *window;
  NSTextField *status;
  NSButton *refresh;
}
- (void)refreshStatus:(id)sender;
@end

@implementation InstallerController
- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
  NSRect frame = NSMakeRect(0, 0, 620, 300);
  window = [[NSWindow alloc] initWithContentRect:frame
      styleMask:NSTitledWindowMask | NSClosableWindowMask
      backing:NSBackingStoreBuffered defer:NO];
  [window setTitle:@"FoxynBSD Installer"];
  [window center];

  NSTextField *title = [[NSTextField alloc] initWithFrame:NSMakeRect(24, 240, 572, 32)];
  [title setEditable:NO]; [title setBordered:NO]; [title setDrawsBackground:NO];
  [title setFont:[NSFont boldSystemFontOfSize:20]];
  [title setStringValue:@"FoxynBSD Installer"];
  [[window contentView] addSubview:title];
  [title release];

  status = [[NSTextField alloc] initWithFrame:NSMakeRect(24, 96, 572, 130)];
  [status setEditable:NO]; [status setSelectable:YES];
  [status setBordered:NO]; [status setDrawsBackground:NO];
  [status setStringValue:@"Checking installer availability…"];
  [[window contentView] addSubview:status];

  refresh = [[NSButton alloc] initWithFrame:NSMakeRect(24, 25, 160, 40)];
  [refresh setTitle:@"Check again"]; [refresh setTarget:self];
  [refresh setAction:@selector(refreshStatus:)];
  [[window contentView] addSubview:refresh];

  NSButton *quit = [[NSButton alloc] initWithFrame:NSMakeRect(436, 25, 160, 40)];
  [quit setTitle:@"Quit"]; [quit setTarget:NSApp]; [quit setAction:@selector(terminate:)];
  [[window contentView] addSubview:quit];
  [quit release];
  [window makeKeyAndOrderFront:nil];
  [NSApp activateIgnoringOtherApps:YES];
  [self refreshStatus:nil];
}

- (void)refreshStatus:(id)sender
{
  NSString *path = [[[NSProcessInfo processInfo] environment] objectForKey:@"FOXYN_INSTALLER_BACKEND"];
  if (![path isAbsolutePath] || ![[NSFileManager defaultManager] isExecutableFileAtPath:path]) {
    [status setStringValue:@"The installer backend is unavailable.\n\nInstallation cannot start."];
    return;
  }
  NSPipe *input = [NSPipe pipe];
  NSPipe *output = [NSPipe pipe];
  NSTask *task = [[NSTask alloc] init];
  [task setLaunchPath:path];
  [task setStandardInput:input];
  [task setStandardOutput:output];
  [task setStandardError:[NSFileHandle fileHandleWithNullDevice]];
  @try {
    [task launch];
    NSData *request = [@"{\"version\":1,\"id\":1,\"operation\":\"check-hardware\"}\n" dataUsingEncoding:NSUTF8StringEncoding];
    [[input fileHandleForWriting] writeData:request];
    [[input fileHandleForWriting] closeFile];
    NSData *response = [[output fileHandleForReading] readDataToEndOfFile];
    [task waitUntilExit];
    NSError *error = nil;
    id json = [NSJSONSerialization JSONObjectWithData:response options:0 error:&error];
    id result = [json isKindOfClass:[NSDictionary class]] ? [json objectForKey:@"result"] : nil;
    id findings = [result isKindOfClass:[NSDictionary class]] ? [result objectForKey:@"findings"] : nil;
    if ([task terminationStatus] != 0 || ![findings isKindOfClass:[NSArray class]]) {
      [status setStringValue:@"The installer backend returned an invalid response.\n\nInstallation cannot start."];
    } else {
      NSMutableString *message = [NSMutableString stringWithString:@"Installation is not available yet.\n\n"];
      for (id finding in findings) {
        id text = [finding isKindOfClass:[NSDictionary class]] ? [finding objectForKey:@"message"] : nil;
        if ([text isKindOfClass:[NSString class]]) [message appendFormat:@"• %@\n", text];
      }
      [status setStringValue:message];
    }
  } @catch (NSException *exception) {
    [status setStringValue:@"The installer backend could not be started.\n\nInstallation cannot start."];
  }
  [task release];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app { return YES; }
- (void)dealloc { [refresh release]; [status release]; [window release]; [super dealloc]; }
@end

int main(int argc, const char **argv)
{
  NSAutoreleasePool *pool = [NSAutoreleasePool new];
  [NSApplication sharedApplication];
  InstallerController *controller = [InstallerController new];
  [NSApp setDelegate:controller];
  [NSApp run];
  [controller release];
  [pool drain];
  return 0;
}
