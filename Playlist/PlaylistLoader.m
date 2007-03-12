//
//  PlaylistLoader.m
//  Cog
//
//  Created by Vincent Spader on 3/05/07.
//  Copyright 2007 Vincent Spader All rights reserved.
//

#import "PlaylistLoader.h"
#import "PlaylistController.h"
#import "PlaylistEntry.h"

#import "CogAudio/AudioPlayer.h"

@implementation PlaylistLoader

//load/save playlist auto-determines type to be either pls or m3u.
- (BOOL)load:(NSString *)filename
{
	NSString *ext = [filename pathExtension];
	if ([ext isEqualToString:@"m3u"])
	{
		return [self loadM3u:filename];
	}
	else if ([ext isEqualToString:@"pls"])
	{
		return [self loadPls:filename];
	}
	else
	{
		return [self loadPls:filename] || [self loadM3u:filename];
	}
}

- (BOOL)save
{
	return [self save:currentFile asType:currentType];
}

- (BOOL)save:(NSString *)filename
{
	NSString *ext = [filename pathExtension];
	if ([ext isEqualToString:@"pls"])
	{
		return [self save:filename asType:kPlaylistPls];
	}
	else
	{
		return [self save:filename asType:kPlaylistM3u];
	}
}	

- (BOOL)save:(NSString *)filename asType:(PlaylistType)type
{
	if (type == kPlaylistM3u)
	{
		return [self saveM3u:filename];
	}
	else if (type == kPlaylistPls)
	{
		return [self savePls:filename];
	}

	return NO;
}

- (NSString *)relativePathFrom:(NSString *)filename toURL:(NSURL *)entryURL
{
	NSString *basePath = [[[filename stringByStandardizingPath] stringByDeletingLastPathComponent] stringByAppendingString:@"/"];

	if ([entryURL isFileURL]) {
		//We want relative paths.
		NSMutableString *entryPath = [[[[entryURL path] stringByStandardizingPath] mutableCopy] autorelease];

		[entryPath replaceOccurrencesOfString:basePath withString:@"" options:(NSAnchoredSearch | NSLiteralSearch | NSCaseInsensitiveSearch) range:NSMakeRange(0, [entryPath length])];

		return entryPath;		
	}
	else {
		//Write [entryURL absoluteString] to file
		return [entryURL absoluteString];
	}
}

- (NSURL *)urlForPath:(NSString *)path relativeTo:(NSString *)baseFilename
{
	if ([path hasPrefix:@"/"]) {
		return [NSURL fileURLWithPath:path];
	}
	
	NSEnumerator *e = [[AudioPlayer schemes] objectEnumerator];
	NSString *scheme;
	while (scheme = [e nextObject])
	{
		if ([path hasPrefix:[scheme stringByAppendingString:@"://"]])
		{
			return [NSURL URLWithString:path];
		}
	}
	
	NSString *basePath = [[[baseFilename stringByStandardizingPath] stringByDeletingLastPathComponent] stringByAppendingString:@"/"];
	
	return [NSURL fileURLWithPath:[basePath stringByAppendingString:path]];
}


- (BOOL)loadM3u:(NSString *)filename
{
	NSLog(@"Loading playlist: %@", filename);
	

    NSError *error = nil;
    NSString *contents = [NSString stringWithContentsOfFile:filename encoding:NSUTF8StringEncoding error:&error];
    if (error || !contents) {
		NSLog(@"Could not open file...%@ %@", contents, error);
        return NO;
    }

    NSString *entry;
    NSEnumerator *e = [[contents componentsSeparatedByString:@"\n"] objectEnumerator];
	NSMutableArray *entries = [NSMutableArray array];

    while (entry = [[e nextObject] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]])
    {
		if ([entry hasPrefix:@"#"] || [entry isEqualToString:@""]) //Ignore extra info
			continue;

		//Need to add basePath, and convert to URL
		[entries addObject:[self urlForPath:entry relativeTo:filename]];		
	}

	[self addURLs:entries sort:NO];
	
	return YES;
}

- (BOOL)saveM3u:(NSString *)filename
{
	NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:filename];
	if (!fileHandle) {
		return NO;
	}
	[fileHandle truncateFileAtOffset:0];
	
	NSLog(@"Saving: %@", filename);

	PlaylistEntry *pe;
	NSEnumerator *e = [[playlistController content] objectEnumerator];

	while (pe = [e nextObject])
	{
		NSString *path = [self relativePathFrom:filename toURL:[pe url]];
		[fileHandle writeData:[[path stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding]];
	}

	[fileHandle closeFile];

	[self setCurrentFile:filename];
	[self setCurrentType:kPlaylistM3u];

	return YES;
}

- (BOOL)loadPls:(NSString *)filename
{
	NSError *error;
	NSString *contents = [NSString stringWithContentsOfFile:filename encoding:NSUTF8StringEncoding error:&error];
	if (error || !contents) {
		return NO;
	}

	NSString *entry;
	NSEnumerator *e = [[contents componentsSeparatedByString:@"\n"] objectEnumerator];
	NSMutableArray *entries = [NSMutableArray array];

    while (entry = [[e nextObject] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]])
	{
		NSScanner *scanner = [[NSScanner alloc] initWithString:entry];
		NSString *lhs = nil;
		NSString *rhs = nil;
		
		if (![scanner scanUpToString:@"=" intoString:&lhs]	|| // get LHS
			![scanner scanString:@"=" intoString:nil]		|| // skip the =
			![scanner scanUpToString:@"" intoString:&rhs]	|| // get RHS
			![lhs isEqualToString:@"File"]) // We only want file entries
		{
			[scanner release];
			continue;
		}
		
		//need to add basepath if its a file, and convert to URL
		[entries addObject:[self urlForPath:rhs relativeTo:filename]];
		
		[scanner release];
	}

	[self addURLs:entries sort:NO];
	
	return YES;
}

- (BOOL)savePls:(NSString *)filename
{
	NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:filename];
	if (!fileHandle) {
		return NO;
	}
	[fileHandle truncateFileAtOffset:0];

	[fileHandle writeData:[[NSString stringWithFormat:@"[playlist]\nnumberOfEntries=%i\n\n",[[playlistController content] count]] dataUsingEncoding:NSUTF8StringEncoding]];

	NSEnumerator *e = [[playlistController content] objectEnumerator];
	PlaylistEntry *pe;
	int i = 1;
	while (pe = [e nextObject])
	{
		NSString *path = [self relativePathFrom:filename toURL:[pe url]];
		NSString *entry = [NSString stringWithFormat:@"File%i=%@\n",i,path];

		[fileHandle writeData:[entry dataUsingEncoding:NSUTF8StringEncoding]];
		i++;
	}

	[fileHandle writeData:[@"\nVERSION=2" dataUsingEncoding:NSUTF8StringEncoding]];
	[fileHandle closeFile];

	[self setCurrentFile:filename];
	[self setCurrentType:kPlaylistM3u];

	return YES;
}

- (NSArray *)fileURLsAtPath:(NSString *)path
{
	NSFileManager *manager = [NSFileManager defaultManager];
	
	NSMutableArray *urls = [NSMutableArray array];
		
	NSString *subpath;
	NSArray *subpaths = [manager subpathsAtPath:path];
	NSEnumerator *e = [subpaths objectEnumerator];

	while(subpath = [e nextObject])
	{
		NSString *absoluteSubpath = [NSString pathWithComponents:[NSArray arrayWithObjects:path,subpath,nil]];
		
		BOOL isDir;
		if ( [manager fileExistsAtPath:absoluteSubpath isDirectory:&isDir] && isDir == NO)
		{
			[urls addObject:[NSURL fileURLWithPath:absoluteSubpath]];
		}
	}
	
	return urls;
}

- (void)insertURLs:(NSArray *)urls atIndex:(int)index sort:(BOOL)sort
{
	NSMutableArray *allURLs = [[NSMutableArray alloc] init];
	NSMutableArray *validURLs = [[NSMutableArray alloc] init];
	NSArray *finalURLs;
	
	if (!urls)
		return;
	
	if (index < 0)
		index = 0;
	
	NSLog(@"URLS: %@", urls);
	NSEnumerator *urlEnumerator = [urls objectEnumerator];
	NSURL *url;
	while (url = [urlEnumerator nextObject])
	{
		if ([url isFileURL]) {
			BOOL isDir;
		    if ([[NSFileManager defaultManager] fileExistsAtPath:[url path] isDirectory:&isDir])
		    {
				if (isDir == YES)
				{
					//Get subpaths
					[allURLs addObjectsFromArray:[self fileURLsAtPath:[url path]]];
				}
				else
				{
					//File url
					[allURLs addObject:url];
				}
			}
		}
		else
		{
			//Non-file URL..
			[allURLs addObject:url];
		}
	}


	urlEnumerator = [allURLs objectEnumerator];
	while (url = [urlEnumerator nextObject])
	{
		if (![[AudioPlayer schemes] containsObject:[url scheme]])
			continue;

		//Need a better way to determine acceptable file types than basing it on extensions.
		if (![[self acceptableFileTypes] containsObject:[[[url path] pathExtension] lowercaseString]])
			continue;
			
		[validURLs addObject:url];
	}

	finalURLs = validURLs;
	if (sort == YES)
	{
		NSSortDescriptor *sortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"absoluteString" ascending:YES];

		finalURLs = [validURLs sortedArrayUsingDescriptors:[NSArray arrayWithObject:sortDescriptor]];

		[sortDescriptor release];
	}

	//Create actual entries
	int i;
	NSMutableArray *entries = [NSMutableArray array];
	for (i = 0; i < [finalURLs count]; i++)
	{
		PlaylistEntry *pe = [[PlaylistEntry alloc] init];
		NSURL *url = [finalURLs objectAtIndex:i];

		[pe	setURL:url];
		[pe setIndex:index+i];
		[pe setTitle:[[url path] lastPathComponent]];
		
		[entries addObject:pe];

		[pe release];
	}
	
	NSIndexSet *is = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(index, [entries count])];

	[playlistController insertObjects:entries atArrangedObjectIndexes:is];
	
	//Select the first entry in the group that was just added
	[playlistController setSelectionIndex:index];
	
	//Other thread for reading things...
	[NSThread detachNewThreadSelector:@selector(readEntriesInfoThread:) toTarget:self withObject:entries];
	
	[allURLs release];
	[validURLs release];

	return;
}

- (void)readEntriesInfoThread:(NSArray *)entries
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

	NSEnumerator *e = [entries objectEnumerator];
	PlaylistEntry *pe;
	while (pe = [e nextObject])
	{
		[pe readPropertiesThread];

		[pe readMetadataThread];

		//Hack so the display gets updated
		if (pe == [playlistController currentEntry])
			[playlistController performSelectorOnMainThread:@selector(setCurrentEntry:) withObject:[playlistController currentEntry] waitUntilDone:YES];
	}


	[playlistController performSelectorOnMainThread:@selector(updateTotalTime) withObject:nil waitUntilDone:NO];
	
	[pool release];
}

- (void)addURLs:(NSArray *)urls sort:(BOOL)sort
{
	[self insertURLs:urls atIndex:[[playlistController content] count] sort:sort];
}

- (NSArray *)acceptableFileTypes
{
	return [AudioPlayer fileTypes];
}

- (NSArray *)acceptablePlaylistTypes
{
	return [NSArray arrayWithObjects:@"m3u",@"pls",nil];
}

- (PlaylistType)currentType
{
	return currentType;
}

- (void)setCurrentType:(PlaylistType)type
{
	currentType = type;
}

- (NSString *)currentFile
{
	return currentFile;
}

- (void)setCurrentFile:(NSString *)file
{
	[file retain];
	[currentFile release];
	currentFile = file;
}

@end