#import "MFSRootViewController.h"
#import "CoreServices.h"

@interface SKUIItemStateCenter : NSObject

+ (id)defaultCenter;
- (id)_newPurchasesWithItems:(id)items;
- (void)_performPurchases:(id)purchases hasBundlePurchase:(_Bool)purchase withClientContext:(id)context completionBlock:(id /* block */)block;
- (void)_performSoftwarePurchases:(id)purchases withClientContext:(id)context completionBlock:(id /* block */)block;

@end

@interface SKUIItem : NSObject
- (id)initWithLookupDictionary:(id)dictionary;
@end

@interface SKUIItemOffer : NSObject
- (id)initWithLookupDictionary:(id)dictionary;
@end

@interface SKUIClientContext : NSObject
+ (id)defaultContext;
@end

@implementation MFSRootViewController

- (void)loadView
{
	[super loadView];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadSpecifiers) name:UIApplicationWillEnterForegroundNotification object:nil];
}

- (NSMutableArray*)specifiers
{
	if(!_specifiers)
	{
		_specifiers = [NSMutableArray new];

		PSSpecifier* downloadGroupSpecifier = [PSSpecifier emptyGroupSpecifier];
		downloadGroupSpecifier.name = @"下载";
		[_specifiers addObject:downloadGroupSpecifier];

		PSSpecifier* downloadSpecifier = [PSSpecifier preferenceSpecifierNamed:@"下载" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
		downloadSpecifier.identifier = @"download";
		[downloadSpecifier setProperty:@YES forKey:@"enabled"];
		downloadSpecifier.buttonAction = @selector(downloadApp);
		[_specifiers addObject:downloadSpecifier];

		NSString* aboutText = [self getAboutText];
		[downloadGroupSpecifier setProperty:aboutText forKey:@"footerText"];

		PSSpecifier* installedGroupSpecifier = [PSSpecifier emptyGroupSpecifier];
		installedGroupSpecifier.name = @"已安装程序";
		[_specifiers addObject:installedGroupSpecifier];

		NSMutableArray *appSpecifiers = [NSMutableArray new];
		[[LSApplicationWorkspace defaultWorkspace] enumerateApplicationsOfType:0 block:^(LSApplicationProxy* appProxy) {
			PSSpecifier* appSpecifier = [PSSpecifier preferenceSpecifierNamed:appProxy.localizedName target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
			[appSpecifier setProperty:appProxy.bundleURL forKey:@"bundleURL"];
			[appSpecifier setProperty:@YES forKey:@"enabled"];
			appSpecifier.buttonAction = @selector(downloadAppShortcut:);
			[appSpecifiers addObject:appSpecifier];
		}];
		[appSpecifiers sortUsingComparator:^NSComparisonResult(PSSpecifier* a, PSSpecifier* b) {
			return [a.name compare:b.name];
		}];
		[_specifiers addObjectsFromArray:appSpecifiers];
	}
	[(UINavigationItem *)self.navigationItem setTitle:@"MuffinStore"];
	return _specifiers;
}

- (void)downloadAppShortcut:(PSSpecifier*)specifier
{
	NSURL* bundleURL = [specifier propertyForKey:@"bundleURL"];
	NSDictionary* infoPlist = [NSDictionary dictionaryWithContentsOfFile:[bundleURL.path stringByAppendingPathComponent:@"Info.plist"]];
	NSString* bundleId = infoPlist[@"CFBundleIdentifier"];
	// NSLog(@"Bundle ID: %@", bundleId);
	NSURL* url = [NSURL URLWithString:[NSString stringWithFormat:@"https://itunes.apple.com/lookup?bundleId=%@&limit=1&media=software", bundleId]];
	NSURLRequest* request = [NSURLRequest requestWithURL:url];
	NSURLSessionDataTask* task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData* data, NSURLResponse* response, NSError* error) {
		if(error)
		{
			dispatch_async(dispatch_get_main_queue(), ^{
				[self showAlert:@"错误" message:error.localizedDescription];
			});
			return;
		}
		// NSLog(@"Response: %@", [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
		NSError* jsonError = nil;
		NSDictionary* json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
		if(jsonError)
		{
			dispatch_async(dispatch_get_main_queue(), ^{
				[self showAlert:@"JSON 错误" message:jsonError.localizedDescription];
			});
			return;
		}
		NSArray* results = json[@"results"];
		if(results.count == 0)
		{
			dispatch_async(dispatch_get_main_queue(), ^{
				[self showAlert:@"错误" message:@"无结果"];
			});
			return;
		}
		NSDictionary* app = results[0];
		[self getAllAppVersionIdsAndPrompt:[app[@"trackId"] longLongValue]];
	}];
	[task resume];
}

- (NSString*)getAboutText
{
	return @"MuffinStore v1.1\n由 Mineek 构建；🇨🇳刀刀汉化！\nhttps://github.com/mineek/MuffinStore";
}

- (void)showAlert:(NSString*)title message:(NSString*)message
{
	dispatch_async(dispatch_get_main_queue(), ^{
		UIAlertController* alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
		UIAlertAction* okAction = [UIAlertAction actionWithTitle:@"好的" style:UIAlertActionStyleDefault handler:nil];
		[alert addAction:okAction];
		[self presentViewController:alert animated:YES completion:nil];
	});
}

- (void)getAllAppVersionIdsFromServer:(long long)appId
{
	//NSURL* url = [NSURL URLWithString:[NSString stringWithFormat:@"http://192.168.1.180/olderVersions/%lld", appId]];
	NSString* serverURL = @"https://apis.bilin.eu.org/history/";
	NSURL* url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%lld", serverURL, appId]];
	NSURLRequest* request = [NSURLRequest requestWithURL:url];
	NSURLSessionDataTask* task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData* data, NSURLResponse* response, NSError* error) {
		if(error)
		{
			dispatch_async(dispatch_get_main_queue(), ^{
				[self showAlert:@"错误" message:error.localizedDescription];
			});
			return;
		}
		NSError* jsonError = nil;
		NSDictionary* json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
		if(jsonError)
		{
			dispatch_async(dispatch_get_main_queue(), ^{
				[self showAlert:@"JSON 错误" message:jsonError.debugDescription];
			});
			return;
		}
		NSArray* versionIds = json[@"data"];
		if(versionIds.count == 0)
		{
			dispatch_async(dispatch_get_main_queue(), ^{
				[self showAlert:@"错误" message:@"没有版本ID，可能是内部错误？"];
			});
			return;
		}
		dispatch_async(dispatch_get_main_queue(), ^{
			UIAlertController* versionAlert = [UIAlertController alertControllerWithTitle:@"版本ID" message:@"选择要下载的程序版本ID" preferredStyle:UIAlertControllerStyleActionSheet];
			for(NSDictionary* versionId in versionIds)
			{
				UIAlertAction* versionAction = [UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@", versionId[@"bundle_version"]] style:UIAlertActionStyleDefault handler:^(UIAlertAction* action) {
					[self downloadAppWithAppId:appId versionId:[versionId[@"external_identifier"] longLongValue]];
				}];
				[versionAlert addAction:versionAction];
			}
			UIAlertAction* cancelAction = [UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil];
			[versionAlert addAction:cancelAction];

			// iPad fix
			if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
				versionAlert.popoverPresentationController.sourceView = self.view;
				versionAlert.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 0, 0);
			}

			[self presentViewController:versionAlert animated:YES completion:nil];
		});
	}];
	[task resume];
}

- (void)promptForVersionId:(long long)appId
{
	dispatch_async(dispatch_get_main_queue(), ^{
	UIAlertController* versionAlert = [UIAlertController alertControllerWithTitle:@"版本ID" message:@"输入要下载的程序版本ID" preferredStyle:UIAlertControllerStyleAlert];
	[versionAlert addTextFieldWithConfigurationHandler:^(UITextField* textField) {
		textField.placeholder = @"版本ID";
	}];
	UIAlertAction* downloadAction = [UIAlertAction actionWithTitle:@"下载" style:UIAlertActionStyleDefault handler:^(UIAlertAction* action) {
		long long versionId = [versionAlert.textFields.firstObject.text longLongValue];
		[self downloadAppWithAppId:appId versionId:versionId];
	}];
	[versionAlert addAction:downloadAction];
	UIAlertAction* cancelAction = [UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil];
	[versionAlert addAction:cancelAction];
	[self presentViewController:versionAlert animated:YES completion:nil];
	});
}

- (void)getAllAppVersionIdsAndPrompt:(long long)appId
{
	dispatch_async(dispatch_get_main_queue(), ^{
	UIAlertController* promptAlert = [UIAlertController alertControllerWithTitle:@"版本ID" message:@"是否要手动输入版本ID或向服务器请求版本ID列表？" preferredStyle:UIAlertControllerStyleAlert];
	UIAlertAction* manualAction = [UIAlertAction actionWithTitle:@"手动" style:UIAlertActionStyleDefault handler:^(UIAlertAction* action) {
		[self promptForVersionId:appId];
	}];
	[promptAlert addAction:manualAction];
	UIAlertAction* serverAction = [UIAlertAction actionWithTitle:@"服务器" style:UIAlertActionStyleDefault handler:^(UIAlertAction* action) {
		[self getAllAppVersionIdsFromServer:appId];
	}];
	[promptAlert addAction:serverAction];
	UIAlertAction* cancelAction = [UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil];
	[promptAlert addAction:cancelAction];
	[self presentViewController:promptAlert animated:YES completion:nil];
	});
}

- (void)downloadAppWithAppId:(long long)appId versionId:(long long)versionId
{
	NSString* adamId = [NSString stringWithFormat:@"%lld", appId];
	NSString* pricingParameters = @"pricingParameter";
	NSString* appExtVrsId = [NSString stringWithFormat:@"%lld", versionId];
	NSString* installed = @"0";
	NSString* offerString = nil;
	if (versionId == 0)
	{
		offerString = [NSString stringWithFormat:@"productType=C&price=0&salableAdamId=%@&pricingParameters=%@&clientBuyId=1&installed=%@&trolled=1", adamId, pricingParameters, installed];
	}
	else
	{
		offerString = [NSString stringWithFormat:@"productType=C&price=0&salableAdamId=%@&pricingParameters=%@&appExtVrsId=%@&clientBuyId=1&installed=%@&trolled=1", adamId, pricingParameters, appExtVrsId, installed];
	}
	NSDictionary* offerDict = @{@"buyParams": offerString};
	NSDictionary* itemDict = @{@"_itemOffer": adamId};
	SKUIItemOffer* offer = [[SKUIItemOffer alloc] initWithLookupDictionary:offerDict];
	SKUIItem* item = [[SKUIItem alloc] initWithLookupDictionary:itemDict];
	[item setValue:offer forKey:@"_itemOffer"];
	[item setValue:@"iosSoftware" forKey:@"_itemKindString"];
	//[item setValue:@(versionId) forKey:@"_versionIdentifier"];
	if(versionId != 0)
	{
		[item setValue:@(versionId) forKey:@"_versionIdentifier"];
	}
	SKUIItemStateCenter* center = [SKUIItemStateCenter defaultCenter];
	NSArray* items = @[item];
	dispatch_async(dispatch_get_main_queue(), ^{
		[center _performPurchases:[center _newPurchasesWithItems:items] hasBundlePurchase:0 withClientContext:[SKUIClientContext defaultContext] completionBlock:^(id arg1){}];
	});
}

- (void)downloadAppWithLink:(NSString*)link
{
	NSString* targetAppIdParsed = nil;
	if([link containsString:@"id"])
	{
		NSArray* components = [link componentsSeparatedByString:@"id"];
		if(components.count < 2)
		{
			[self showAlert:@"错误" message:@"链接无效"];
			return;
		}
		NSArray* idComponents = [components[1] componentsSeparatedByString:@"?"];
		targetAppIdParsed = idComponents[0];
	}
	else
	{
		[self showAlert:@"错误" message:@"链接无效"];
		return;
	}
	dispatch_async(dispatch_get_main_queue(), ^{
		[self getAllAppVersionIdsAndPrompt:[targetAppIdParsed longLongValue]];
	});
}

- (void)downloadApp
{
	UIAlertController* linkAlert = [UIAlertController alertControllerWithTitle:@"程序链接" message:@"输入要下载的应用程序链接" preferredStyle:UIAlertControllerStyleAlert];
	[linkAlert addTextFieldWithConfigurationHandler:^(UITextField* textField) {
		textField.placeholder = @"程序链接";
	}];
	UIAlertAction* downloadAction = [UIAlertAction actionWithTitle:@"下载" style:UIAlertActionStyleDefault handler:^(UIAlertAction* action) {
		[self downloadAppWithLink:linkAlert.textFields.firstObject.text];
	}];
	[linkAlert addAction:downloadAction];
	UIAlertAction* cancelAction = [UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil];
	[linkAlert addAction:cancelAction];
	[self presentViewController:linkAlert animated:YES completion:nil];
}

@end

