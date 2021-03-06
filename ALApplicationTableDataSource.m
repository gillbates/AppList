#import "ALApplicationTableDataSource.h"

#import "ALApplicationList.h"

#import <UIKit/UIKit2.h>
#import <CoreGraphics/CoreGraphics.h>

const NSString *ALSectionDescriptorTitleKey = @"title";
const NSString *ALSectionDescriptorFooterTitleKey = @"footer-title";
const NSString *ALSectionDescriptorPredicateKey = @"predicate";
const NSString *ALSectionDescriptorCellClassNameKey = @"cell-class-name";
const NSString *ALSectionDescriptorIconSizeKey = @"icon-size";
const NSString *ALSectionDescriptorItemsKey = @"items";
const NSString *ALSectionDescriptorSuppressHiddenAppsKey = @"suppress-hidden-apps";

const NSString *ALItemDescriptorTextKey = @"text";
const NSString *ALItemDescriptorDetailTextKey = @"detail-text";
const NSString *ALItemDescriptorImageKey = @"image";

static NSInteger DictionaryTextComparator(id a, id b, void *context)
{
	return [[(NSDictionary *)context objectForKey:a] localizedCaseInsensitiveCompare:[(NSDictionary *)context objectForKey:b]];
}

@implementation ALApplicationTableDataSource

static NSArray *hiddenDisplayIdentifiers;

+ (void)initialize
{
	if ((self == [ALApplicationTableDataSource class])) {
		hiddenDisplayIdentifiers = [[NSArray alloc] initWithObjects:
		                            @"com.apple.AdSheet",
		                            @"com.apple.AdSheetPhone",
		                            @"com.apple.AdSheetPad",
		                            @"com.apple.DataActivation",
		                            @"com.apple.DemoApp",
		                            @"com.apple.fieldtest",
		                            @"com.apple.iosdiagnostics",
		                            @"com.apple.iphoneos.iPodOut",
		                            @"com.apple.TrustMe",
		                            @"com.apple.WebSheet",
		                            nil];
	}
}

+ (NSArray *)standardSectionDescriptors
{
	NSNumber *iconSize = [NSNumber numberWithUnsignedInteger:ALApplicationIconSizeSmall];
	return [NSArray arrayWithObjects:
		[NSDictionary dictionaryWithObjectsAndKeys:
			@"System Applications", ALSectionDescriptorTitleKey,
			@"isSystemApplication = TRUE", ALSectionDescriptorPredicateKey,
			@"UITableViewCell", ALSectionDescriptorCellClassNameKey,
			iconSize, ALSectionDescriptorIconSizeKey,
		nil],
		[NSDictionary dictionaryWithObjectsAndKeys:
			@"User Applications", ALSectionDescriptorTitleKey,
			@"isSystemApplication = FALSE", ALSectionDescriptorPredicateKey,
			@"UITableViewCell", ALSectionDescriptorCellClassNameKey,
			iconSize, ALSectionDescriptorIconSizeKey,
		nil],
	nil];
}

+ (id)dataSource
{
	return [[[self alloc] init] autorelease];
}

- (id)init
{
	if ((self = [super init])) {
		appList = [[ALApplicationList sharedApplicationList] retain];
		_displayIdentifiers = [[NSMutableArray alloc] init];
		_displayNames = [[NSMutableArray alloc] init];
	}
	return self;
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[_tableView release];
	[_displayIdentifiers release];
	[_displayNames release];
	[appList release];
	[super dealloc];
}

@synthesize sectionDescriptors = _sectionDescriptors;
@synthesize tableView = _tableView;

- (void)setSectionDescriptors:(NSArray *)sectionDescriptors
{
	[_displayIdentifiers removeAllObjects];
	[_displayNames removeAllObjects];
	for (NSDictionary *descriptor in sectionDescriptors) {
		NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
		NSArray *items = [descriptor objectForKey:@"items"];
		if (items) {
			[_displayIdentifiers addObject:items];
			[_displayNames addObject:[NSNull null]];
		} else {
			NSString *predicateText = [descriptor objectForKey:ALSectionDescriptorPredicateKey];
			NSDictionary *applications;
			if (predicateText)
				applications = [appList applicationsFilteredUsingPredicate:[NSPredicate predicateWithFormat:predicateText]];
			else
				applications = [appList applications];
			NSMutableArray *displayIdentifiers = [[applications allKeys] mutableCopy];
			if ([[descriptor objectForKey:ALSectionDescriptorSuppressHiddenAppsKey] boolValue]) {
				for (NSString *displayIdentifier in hiddenDisplayIdentifiers)
					[displayIdentifiers removeObject:displayIdentifier];
			}
			[displayIdentifiers sortUsingFunction:DictionaryTextComparator context:applications];
			[_displayIdentifiers addObject:displayIdentifiers];
			[displayIdentifiers release];
			NSMutableArray *displayNames = [[NSMutableArray alloc] init];
			for (NSString *displayId in displayIdentifiers)
				[displayNames addObject:[applications objectForKey:displayId]];
			[_displayNames addObject:displayNames];
			[displayNames release];
		}
		[pool release];
	}
	[_sectionDescriptors release];
	_sectionDescriptors = [sectionDescriptors copy];
}

- (NSString *)displayIdentifierForIndexPath:(NSIndexPath *)indexPath
{
	return [[_displayIdentifiers objectAtIndex:[indexPath section]] objectAtIndex:[indexPath row]];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
	return [_sectionDescriptors count];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
	return [[_sectionDescriptors objectAtIndex:section] objectForKey:ALSectionDescriptorTitleKey];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
	return [[_sectionDescriptors objectAtIndex:section] objectForKey:ALSectionDescriptorFooterTitleKey];
}

- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section
{
	return [[_displayIdentifiers objectAtIndex:section] count];
}

- (void)loadIconsFromBackground
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	OSSpinLockLock(&spinLock);
	while ([_iconsToLoad count]) {
		NSDictionary *userInfo = [[_iconsToLoad objectAtIndex:0] retain];
		[_iconsToLoad removeObjectAtIndex:0];
		OSSpinLockUnlock(&spinLock);
		CGImageRelease([appList copyIconOfSize:[[userInfo objectForKey:ALIconSizeKey] integerValue] forDisplayIdentifier:[userInfo objectForKey:ALDisplayIdentifierKey]]);
		[userInfo release];
		[pool drain];
		pool = [[NSAutoreleasePool alloc] init];
		OSSpinLockLock(&spinLock);
	}
	[_iconsToLoad release];
	_iconsToLoad = nil;
	OSSpinLockUnlock(&spinLock);
	[pool drain];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	NSUInteger section = [indexPath section];
	NSUInteger row = [indexPath row];
	NSDictionary *sectionDescriptor = [_sectionDescriptors objectAtIndex:section];
	NSString *cellClassName = [sectionDescriptor objectForKey:ALSectionDescriptorCellClassNameKey] ?: @"UITableViewCell";
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellClassName];
	if (!cell) {
		cell = [[[NSClassFromString(cellClassName) alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellClassName] autorelease];
	}
	id displayNames = [_displayNames objectAtIndex:section];
	if (displayNames == [NSNull null]) {
		NSDictionary *itemDescriptor = [[_displayIdentifiers objectAtIndex:section] objectAtIndex:row];
		cell.textLabel.text = [itemDescriptor objectForKey:ALItemDescriptorTextKey];
		cell.detailTextLabel.text = [itemDescriptor objectForKey:ALItemDescriptorDetailTextKey];
		NSString *imagePath = [itemDescriptor objectForKey:ALItemDescriptorImageKey];
		UIImage *image = nil;
		if (imagePath) {
			CGFloat scale;
			if ([UIScreen instancesRespondToSelector:@selector(scale)] && ((scale = [[UIScreen mainScreen] scale]) != 1.0f))
				image = [UIImage imageWithContentsOfFile:[NSString stringWithFormat:@"%@@%gx.%@", [imagePath stringByDeletingPathExtension], scale, [imagePath pathExtension]]];
			if (!image)
				image = [UIImage imageWithContentsOfFile:imagePath];
		}
		cell.imageView.image = image;
	} else {
		cell.textLabel.text = [displayNames objectAtIndex:row];
		CGFloat iconSize = [[sectionDescriptor objectForKey:ALSectionDescriptorIconSizeKey] floatValue];
		if (iconSize > 0) {
			NSString *displayIdentifier = [[_displayIdentifiers objectAtIndex:section] objectAtIndex:row];
			if (_tableView == nil || [appList hasCachedIconOfSize:iconSize forDisplayIdentifier:displayIdentifier]) {
				cell.imageView.image = [appList iconOfSize:iconSize forDisplayIdentifier:displayIdentifier];
				cell.indentationWidth = 10.0f;
				cell.indentationLevel = 0;
			} else {
				cell.indentationWidth = iconSize + 7.0f;
				cell.indentationLevel = 1;
				cell.imageView.image = nil;
				NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
				                          [NSNumber numberWithInteger:iconSize], ALIconSizeKey,
				                          displayIdentifier, ALDisplayIdentifierKey,
				                          nil];
				OSSpinLockLock(&spinLock);
				if (_iconsToLoad)
					[_iconsToLoad addObject:userInfo];
				else {
					[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(iconLoadedFromNotification:) name:ALIconLoadedNotification object:nil];
					_iconsToLoad = [[NSMutableArray alloc] initWithObjects:userInfo, nil];
					[self performSelectorInBackground:@selector(loadIconsFromBackground) withObject:nil];
				}
				OSSpinLockUnlock(&spinLock);
			}
		} else {
			cell.imageView.image = nil;
		}
	}
	return cell;
}

- (void)iconLoadedFromNotification:(NSNotification *)notification
{
	NSDictionary *userInfo = notification.userInfo;
	NSString *displayIdentifier = [userInfo objectForKey:ALDisplayIdentifierKey];
	NSInteger section = [_displayIdentifiers count];
	while (section) {
		section--;
		NSUInteger row = [[_displayIdentifiers objectAtIndex:section] indexOfObject:displayIdentifier];
		if (row != NSNotFound) {
			NSIndexPath *indexPath = [NSIndexPath indexPathForRow:row inSection:section];
			if ([_tableView.indexPathsForVisibleRows containsObject:indexPath]) {
				UITableViewCell *cell = [_tableView cellForRowAtIndexPath:indexPath];
				NSInteger iconSize = [[userInfo objectForKey:ALIconSizeKey] integerValue];
				cell.indentationLevel = 0;
				cell.indentationWidth = 10.0f;
				cell.imageView.image = [appList iconOfSize:iconSize forDisplayIdentifier:displayIdentifier];
				[cell setNeedsLayout];
			}
		}
	}
	if (!_iconsToLoad)
		[[NSNotificationCenter defaultCenter] removeObserver:self name:ALIconLoadedNotification object:nil];
}

@end
