#import <AppKit/AppKit.h>
#include <poll.h>
#include <signal.h>
#include <time.h>
#include <unistd.h>
#include <errno.h>

@interface InstallerController : NSObject <NSApplicationDelegate>
{
  NSWindow *window;
  NSTextField *status;
  NSButton *refresh;
}
- (void)refreshStatus:(id)sender;
- (void)checkBackend:(NSString *)path;
- (void)showResult:(NSString *)message;
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
  [refresh setNextKeyView:quit];
  [quit setNextKeyView:refresh];
  [window setInitialFirstResponder:refresh];
  [quit release];
  [window makeKeyAndOrderFront:nil];
  [window makeFirstResponder:refresh];
  [NSApp activateIgnoringOtherApps:YES];
  [self refreshStatus:nil];
}

static double monotonicSeconds(void)
{
  struct timespec now;
  if (clock_gettime(CLOCK_MONOTONIC, &now) != 0) return 0;
  return now.tv_sec + now.tv_nsec / 1000000000.0;
}

- (void)refreshStatus:(id)sender
{
  NSString *path = [[[NSProcessInfo processInfo] environment] objectForKey:@"FOXYN_INSTALLER_BACKEND"];
  if (![path isAbsolutePath] || ![[NSFileManager defaultManager] isExecutableFileAtPath:path]) {
    [status setStringValue:@"The installer backend is unavailable.\n\nInstallation cannot start."];
    return;
  }
  [refresh setEnabled:NO];
  [status setStringValue:@"Checking installer availability…"];
  [NSThread detachNewThreadSelector:@selector(checkBackend:) toTarget:self withObject:path];
}

- (void)showResult:(NSString *)message
{
  [status setStringValue:message];
  [refresh setEnabled:YES];
}

- (void)checkBackend:(NSString *)path
{
  NSAutoreleasePool *pool = [NSAutoreleasePool new];
  NSString *message = @"The installer backend returned an invalid response.\n\nInstallation cannot start.";
  NSPipe *input = [NSPipe pipe];
  NSPipe *output = [NSPipe pipe];
  NSTask *task = [[NSTask alloc] init];
  BOOL launched = NO;
  BOOL timedOut = NO;
  BOOL tooLarge = NO;
  @try {
    [task setLaunchPath:path];
    [task setStandardInput:input];
    [task setStandardOutput:output];
    [task setStandardError:[NSFileHandle fileHandleWithNullDevice]];
    [task launch];
    launched = YES;
    NSData *request = [@"{\"version\":1,\"id\":1,\"operation\":\"check-hardware\"}\n" dataUsingEncoding:NSUTF8StringEncoding];
    [[input fileHandleForWriting] writeData:request];
    [[input fileHandleForWriting] closeFile];
    NSMutableData *response = [NSMutableData data];
    int fd = [[output fileHandleForReading] fileDescriptor];
    BOOL eof = NO;
    double deadline = monotonicSeconds() + 5.0;
    while (!eof || [task isRunning]) {
      if (monotonicSeconds() >= deadline) { timedOut = YES; break; }
      if (eof) { usleep(20000); continue; }
      struct pollfd descriptor = { fd, POLLIN | POLLHUP, 0 };
      int ready = poll(&descriptor, 1, 100);
      if (ready < 0) { if (errno == EINTR) continue; break; }
      if (ready == 0) continue;
      if (descriptor.revents & (POLLIN | POLLHUP)) {
        char buffer[4096];
        ssize_t length = read(fd, buffer, sizeof(buffer));
        if (length == 0) eof = YES;
        else if (length < 0) { if (errno != EINTR) break; }
        else if ([response length] + (NSUInteger)length > 65536) { tooLarge = YES; break; }
        else [response appendBytes:buffer length:(NSUInteger)length];
      } else if (descriptor.revents & (POLLERR | POLLNVAL)) break;
    }
    if (timedOut) message = @"The installer backend did not respond in time.\n\nInstallation cannot start.";
    else if (tooLarge) message = @"The installer backend response was too large.\n\nInstallation cannot start.";
    else if (eof && ![task isRunning] && [task terminationStatus] == 0) {
      NSError *error = nil;
      id json = [NSJSONSerialization JSONObjectWithData:response options:0 error:&error];
      id result = [json isKindOfClass:[NSDictionary class]] ? [json objectForKey:@"result"] : nil;
      id findings = [result isKindOfClass:[NSDictionary class]] ? [result objectForKey:@"findings"] : nil;
      if ([findings isKindOfClass:[NSArray class]]) {
        NSMutableString *text = [NSMutableString stringWithString:@"Installation is not available yet.\n\n"];
        for (id finding in findings) {
          id reason = [finding isKindOfClass:[NSDictionary class]] ? [finding objectForKey:@"message"] : nil;
          if ([reason isKindOfClass:[NSString class]]) [text appendFormat:@"• %@\n", reason];
        }
        message = text;
      }
    }
  } @catch (NSException *exception) {
    message = @"The installer backend could not be started or read.\n\nInstallation cannot start.";
  } @finally {
    if (launched && [task isRunning]) kill([task processIdentifier], SIGKILL);
    if (launched) [task waitUntilExit];
  }
  [self performSelectorOnMainThread:@selector(showResult:) withObject:message waitUntilDone:NO];
  [task release];
  [pool drain];
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
