//
//  StoreKit.m
//  StoreProject
//
//  Created by Serg Krivoblotsky on 1/6/12.
//  Copyright (c) 2012 Onix-Systems, LLC. All rights reserved.
//

#import "StoreKit.h"
#import "ASIFormDataRequest.h"
#import "JSON.h"

@implementation StoreKit
@synthesize delegate;
@synthesize paymentQue;
@synthesize avaliablePurchases;
@synthesize completedTransactions;
@synthesize sharedSecret;
@synthesize showActivityIndicator;

//Dictionary keys
static NSString *kProductKey = @"product";
static NSString *kProductPriceKey = @"productPrice";
static NSString *kLocalizedTitleKey = @"productLocalizedTitle";
static NSString *kProductIdentifierKey = @"productIdentifier";

static NSString *kTransactionKey = @"transaction";
static NSString *kTransactionDateKey = @"transactionDate";
static NSString *kTransactionPaymentProductKey = @"transactionPaymentProductIdentifier";
static NSString *kTransactionRecieptData = @"transactionRecieptData";

//Server url
static NSString *kVerifyRecieptURL = @"https://buy.itunes.apple.com/verifyReceipt";
static NSString *kVerifySandboxURL = @"https://sandbox.itunes.apple.com/verifyReceipt";

//Defaults key
static NSString *kLocalTransactionsKey = @"KS_StoreKit_LocalTransactions_Key";

//Last good reciept
static NSString *kLastGoodRecieptKeyFormat = @"KS_Store_lastGood_key_format_%@";

@synthesize sandbox;

- (id)init {
    self = [super init];
    if (self) {
        defaults = [NSUserDefaults standardUserDefaults];
        
        self.paymentQue = [SKPaymentQueue defaultQueue];
        [self.paymentQue addTransactionObserver:self];
        
        avaliablePurchases = [NSMutableArray new];
        completedTransactions = [self restoreCompletedTransactionsFromCache];
                
        parser = [SBJSON new];
    }
    return self;
}

- (void)removeObjerver:(id <SKPaymentTransactionObserver>)observer {
    [self.paymentQue removeTransactionObserver:observer];
}

#pragma mark - Request Products from store
- (void)requestAvaliableProducts:(NSString *)param, ... {
    [self setNetworkActivityIndicatorVisible:YES];    
    
    NSString *currentParam = nil;
    NSMutableArray *params = [NSMutableArray new];
    va_list aList;
    
    if (param != nil) {
        va_start (aList, param);
        currentParam = param;
        do {
            if (![params containsObject:currentParam]) {
                [params addObject:currentParam];
            }
        } while ((currentParam = va_arg(aList, id)));
        
        va_end (aList);
    }
    
    NSSet *productsSet = [NSSet setWithArray:params];
    [params release];
        
    //Run request
    SKProductsRequest *request= [[SKProductsRequest alloc] initWithProductIdentifiers: productsSet];
	request.delegate = self;
	[request start];
}

#pragma mark - Request Completed Transaction
- (void)restoreComletedTransactions {
    [self setNetworkActivityIndicatorVisible:YES];
    [paymentQue restoreCompletedTransactions];
}

#pragma mark - Purchase product
- (void)purchaseProductWithIdentidier:(NSString *)identifier {
    SKProduct *product = [self productWithIdentifier:identifier];
    if (product) {
        [self purchaseProduct:product];
    } else {
        NSLog(@"No such SKProduct. Please run SKProducts request before this.");
    }
}

- (void)purchaseProduct:(SKProduct *)product {
    SKPayment *payment = [SKPayment paymentWithProduct:product];
    [paymentQue addPayment:payment];
    
    [self setNetworkActivityIndicatorVisible:YES];
}

#pragma mark - Check subscribtion
- (void)checkSubscriptionForProduct:(NSString *)productIdentidier {    
    NSString *transactionReciept = [self lastSuccessRecieptForIdentidier:productIdentidier];
    
    if (transactionReciept != nil) {
        [self veriftRecieptDataSubscription:transactionReciept isSandBox:self.isSandbox];    
    } else {
        [self restoreComletedTransactions];
        NSLog(@"There wasn't any success transaction with ID: %@\nRestoring...", productIdentidier);
    }
}

#pragma mark - Verify Reciept
- (BOOL)verifyRecieptForTransaction:(SKPaymentTransaction *)transaction {
    
    NSData *recieptData = transaction.transactionReceipt;
    NSString *recieptString = [self encode:recieptData.bytes length:recieptData.length];
    
    return [self veriftRecieptDataSubscription:recieptString isSandBox:self.isSandbox];
}

- (BOOL)veriftRecieptDataSubscription:(NSString *)recieptData isSandBox:(BOOL)aSandbox {
    if (self.sharedSecret == nil) {
        NSLog(@"Please provide shared secret to check subscription");
        return NO;
    }
    
    NSURL *serverURL = nil;
    
    if (aSandbox) {
        serverURL = [NSURL URLWithString:kVerifySandboxURL];
    } else {
        serverURL = [NSURL URLWithString:kVerifyRecieptURL];
    }
    
    NSMutableDictionary *requestInfo = [NSMutableDictionary new];
    [requestInfo setObject:recieptData forKey:@"receipt-data"];
    [requestInfo setObject:self.sharedSecret forKey:@"password"];
    NSString *jsonString = [requestInfo JSONRepresentation];
    NSData *jsonData = [jsonString dataUsingEncoding:NSASCIIStringEncoding];
    [requestInfo release];
    
    
    ASIFormDataRequest *request = [ASIFormDataRequest requestWithURL:serverURL];
    [request setPostBody:(NSMutableData *)jsonData];
    [request setDelegate:self];
    [request setDidFinishSelector:@selector(checkForSubscriptionRequestFinished:)];
    [request setDidFailSelector:@selector(checkForSubscriptionRequestFailed:)];
    [request startAsynchronous];
    return YES;
}

- (void)verifyTransaction:(SKPaymentTransaction *)transaction isSandBox:(BOOL)aSandbox {    
    NSURL *serverURL = nil;
    if (aSandbox) {
        serverURL = [NSURL URLWithString:kVerifySandboxURL];
    } else {
        serverURL = [NSURL URLWithString:kVerifyRecieptURL];
    }
        
    NSData *recieptData = transaction.transactionReceipt;
    NSString *recieptString = [self encode:recieptData.bytes length:recieptData.length];

    NSMutableDictionary *requestInfo = [NSMutableDictionary new];
    [requestInfo setObject:recieptString forKey:@"receipt-data"];
    
    if (self.sharedSecret != nil) {
        [requestInfo setObject:self.sharedSecret forKey:@"password"];    
    }
    
    NSString *jsonString = [requestInfo JSONRepresentation];
    NSData *jsonData = [jsonString dataUsingEncoding:NSASCIIStringEncoding];
        
    [requestInfo release];
    
    NSMutableDictionary *requestUserInfo = [NSMutableDictionary new];
    [requestUserInfo setObject:transaction forKey:kTransactionKey];
    
    //Run request
    ASIFormDataRequest *request = [ASIFormDataRequest requestWithURL:serverURL];
    [request setPostBody:(NSMutableData *)jsonData];
    [request setUserInfo:requestUserInfo];
    [request setDelegate:self];
    [request setDidFinishSelector:@selector(verifyTransactionRequestFinished:)];
    [request setDidFailSelector:@selector(verifyTransactionRequestFailed:)];
    [request startAsynchronous];
    
    [requestUserInfo release];
}

#pragma mark - SKProductsRequest delegate
- (void)productsRequest:(SKProductsRequest *)request didReceiveResponse:(SKProductsResponse *)response {
    NSArray *products = response.products;
    NSMutableArray *resultProducts = [[[NSMutableArray alloc] init] autorelease];
    
    //Composing result
    for (SKProduct *product in products) {
        NSMutableDictionary *productInfo = [NSMutableDictionary new];
        [productInfo setObject:product forKey:kProductKey];
        [productInfo setObject:product.price forKey:kProductPriceKey];
        [productInfo setObject:product.localizedTitle forKey:kLocalizedTitleKey];
        [productInfo setObject:product.productIdentifier forKey:kProductIdentifierKey];
        [resultProducts addObject:productInfo];
        [productInfo release];
    }
    
    //Cache products
    NSArray *productsCopy = [resultProducts retain];
    [avaliablePurchases setArray:productsCopy];
    [productsCopy release];
        
    if ([self.delegate respondsToSelector:@selector(storeKit:didRecieveProductsInfo:)]) {
        [self.delegate storeKit:self didRecieveProductsInfo:resultProducts];
    }
    [self setNetworkActivityIndicatorVisible:NO];
}

#pragma mark - SKPaymentTransactionDelegates
- (void)paymentQueue:(SKPaymentQueue *)queue updatedTransactions:(NSArray *)transactions {    
    [self setNetworkActivityIndicatorVisible:NO];
    for (SKPaymentTransaction *transaction in transactions) {
		switch (transaction.transactionState) {
			case SKPaymentTransactionStatePurchased: {
                [self transactionSuccessed:transaction];
            }
                break;
				
            case SKPaymentTransactionStateFailed: {
                [self transactionFailed:transaction];
            }
                break;
				
            case SKPaymentTransactionStateRestored: {
                [self transactionRestored:transaction];
            }
                break;
            default: {
                
            }
                break;
		}			
	}
}

- (void)paymentQueue:(SKPaymentQueue *)queue restoreCompletedTransactionsFailedWithError:(NSError *)error {
    if ([self.delegate respondsToSelector:@selector(storeKit:didFailedComletedTransactionsWithError:)]) {
        [self.delegate storeKit:self didFailedComletedTransactionsWithError:error];
    }
    [self setNetworkActivityIndicatorVisible:NO];
}


- (void)paymentQueueRestoreCompletedTransactionsFinished:(SKPaymentQueue *)queue {
    NSMutableArray *resultTransactions = [[[NSMutableArray alloc] init] autorelease];
    NSMutableArray *resultStores = [[[NSMutableArray alloc] init] autorelease];
    
    //Composing result
    for (SKPaymentTransaction *transaction in queue.transactions) {
        NSMutableDictionary *transactionsStoreInfo = [NSMutableDictionary new];
        NSMutableDictionary *transactionsInfo = [NSMutableDictionary new];
        
        //Set result
        [transactionsInfo setObject:transaction forKey:kTransactionKey];
        [transactionsInfo setObject:transaction.transactionDate forKey:kTransactionDateKey];
        [transactionsInfo setObject:transaction.payment.productIdentifier forKey:kTransactionPaymentProductKey];
        [transactionsInfo setObject:[self encode:transaction.transactionReceipt.bytes length:transaction.transactionReceipt.length] forKey:kTransactionRecieptData];
        [resultTransactions addObject:transactionsInfo];
        [transactionsInfo release];
        
        //Set store result
        [transactionsStoreInfo setObject:transaction.transactionDate forKey:kTransactionDateKey];
        [transactionsStoreInfo setObject:transaction.payment.productIdentifier forKey:kTransactionPaymentProductKey];
        [transactionsStoreInfo setObject:[self encode:transaction.transactionReceipt.bytes length:transaction.transactionReceipt.length] forKey:kTransactionRecieptData];
        [resultStores addObject:transactionsStoreInfo];
        [transactionsStoreInfo release];
    }    
    
    //Sort result
    NSSortDescriptor *sortDescriptor = [NSSortDescriptor sortDescriptorWithKey:kTransactionDateKey ascending:YES];
    NSArray *sortedTransactions = [resultTransactions sortedArrayUsingDescriptors:[NSArray arrayWithObject:sortDescriptor]];
    
    //Sort store result
    NSArray *sortedStoreTransactions = [resultStores sortedArrayUsingDescriptors:[NSArray arrayWithObject:sortDescriptor]];
    
    NSArray *array = [sortedTransactions retain];
    [completedTransactions setArray:array];
    [array release];
    
    //Cache local transactions
    [self cacheCompletedTransactions:sortedStoreTransactions];

    if ([self.delegate respondsToSelector:@selector(storeKit:didRecieveCompletedTransactions:)]) {
        [self.delegate storeKit:self didRecieveCompletedTransactions:sortedTransactions];
    }
    [self setNetworkActivityIndicatorVisible:NO];
}

#pragma mark - Transactions Actions
- (void)transactionSuccessed:(SKPaymentTransaction *)transaction {        
    [self verifyTransaction:transaction isSandBox:self.isSandbox];
    [paymentQue finishTransaction:transaction];
}

- (void)transactionRestored:(SKPaymentTransaction *)transaction {    
    [self verifyTransaction:transaction isSandBox:self.isSandbox];
    [paymentQue finishTransaction:transaction];
}

- (void)transactionFailed:(SKPaymentTransaction *)transaction {
    NSLog(@"!!!: %@", self.delegate);
    if ([self.delegate respondsToSelector:@selector(storeKit:didFailTransaction:withError:)]) {
        [self.delegate storeKit:self didFailTransaction:transaction withError:transaction.error];
    }
    
    [paymentQue finishTransaction:transaction];
}

#pragma mark - Cache comleted transactions
- (void)cacheCompletedTransactions:(NSArray *)transactions {
    [self cacheObject:transactions forKey:kLocalTransactionsKey];
}

- (void)cacheObject:(id)object forKey:(NSString *)key {
    [defaults setObject:object forKey:key];
    [defaults synchronize]; 
}

- (NSMutableArray *)restoreCompletedTransactionsFromCache {
    if ([defaults objectForKey:kLocalTransactionsKey] != nil) {
        NSArray *localTransactions = [defaults objectForKey:kLocalTransactionsKey];
        return [[NSMutableArray alloc] initWithArray:localTransactions];
    } 
    return [NSMutableArray new];
}

#pragma mark - Environment
- (BOOL)isSandbox {
    return YES;
#ifdef DEBUG
    sandbox = YES;
#else
    sandbox = NO;
#endif
    return sandbox;
}

#pragma mark - Verify Reciept Response Delegates
- (void)verifyTransactionRequestFinished:(ASIHTTPRequest *)request {
    NSString *responseString = [request responseString];
    
    SKPaymentTransaction *transaction = [[request userInfo] objectForKey:kTransactionKey];
    
    NSError *error = nil;
    NSDictionary *responseInfo = [parser objectWithString:responseString error:&error];
        
    //Refer inApp documemtation for ErrorCodes parsing
    KSErrorCode statusCode = [[responseInfo objectForKey:@"status"] intValue];
    
    //Transaction is valid
    if (statusCode == KSErrorCodeAllOK) {
        
        //This was subscription. Need to store latest reciept
        if ([responseInfo objectForKey:@"latest_receipt"] != nil) {
            
            NSString *lastGoodReciept = [responseInfo objectForKey:@"latest_receipt"];
            NSString *productId = transaction.payment.productIdentifier;
            NSString *key = [NSString stringWithFormat:kLastGoodRecieptKeyFormat, productId];
            
            NSLog(@"%@\n%@", lastGoodReciept, key);
            [self cacheObject:lastGoodReciept forKey:key];
        }
                
        if ([self.delegate respondsToSelector:@selector(storeKit:didTransactionSuccessed:)]) {
            NSMutableDictionary *transactionInfo = [[[NSMutableDictionary alloc] init] autorelease];
            [transactionInfo setObject:transaction forKey:kTransactionKey];
            [transactionInfo setObject:transaction.transactionDate forKey:kTransactionDateKey];
            [transactionInfo setObject:transaction.payment.productIdentifier forKey:kTransactionPaymentProductKey];
            [self.delegate storeKit:self didTransactionSuccessed:transactionInfo];
        }                
    } else {
        NSError *serverError = [NSError errorWithDomain:@"Verify Reciept Error Occured" code:statusCode userInfo:nil];
        if ([self.delegate respondsToSelector:@selector(storeKit:didFailTransaction:withError:)]) {
            [self.delegate storeKit:self didFailTransaction:transaction withError:serverError];
        }
    }
}

- (void)verifyTransactionRequestFailed:(ASIHTTPRequest *)request {
    SKPaymentTransaction *transaction = [[request userInfo] objectForKey:kTransactionKey];
    if ([self.delegate respondsToSelector:@selector(storeKit:didFailTransaction:withError:)]) {
        [self.delegate storeKit:self didFailTransaction:transaction withError:[request error]];
    }
}

#pragma mark - Check for subscription request finished
- (void)checkForSubscriptionRequestFinished:(ASIHTTPRequest *)request {
    NSString *responceString = [request responseString];
    NSDictionary *responseInfo = [parser objectWithString:responceString error:nil];
    
    if (responseInfo != nil) {
        KSErrorCode errorCode = [[responseInfo objectForKey:@"status"] intValue];
        
        NSDictionary *reciept = [responseInfo objectForKey:@"receipt"];
        NSString *productId = [reciept objectForKey:@"product_id"];
        
        //Cache latest reciept
        NSString *latestReciept = [responseInfo objectForKey:@"latest_receipt"];
        if (latestReciept != nil) {
            NSString *key = [NSString stringWithFormat:kLastGoodRecieptKeyFormat, productId];
            [self cacheObject:latestReciept forKey:key];
        }
        
        if ([self.delegate respondsToSelector:@selector(storeKit:didCheckedForSubrirptionWithError:recieptInfo:)]) {
            [self.delegate storeKit:self didCheckedForSubrirptionWithError:errorCode recieptInfo:responseInfo];
        }
    } else {
        if ([self.delegate respondsToSelector:@selector(storeKit:didCheckedForSubrirptionWithServerError:)]) {
            NSError *serverError = [NSError errorWithDomain:@"Server error occured" code:0 userInfo:nil];
            [self.delegate storeKit:self didCheckedForSubrirptionWithServerError:serverError];
        }        
    }
}

- (void)checkForSubscriptionRequestFailed:(ASIHTTPRequest *)request {
    if ([self.delegate respondsToSelector:@selector(storeKit:didCheckedForSubrirptionWithServerError:)]) {
        [self.delegate storeKit:self didCheckedForSubrirptionWithServerError:request.error];
    }
}

#pragma mark - Common
- (SKProduct *)productWithIdentifier:(NSString *)identifier {
    NSString *predicateString = [NSString stringWithFormat:@"productIdentifier like '%@'", identifier];
    NSPredicate *predicate = [NSPredicate predicateWithFormat:predicateString];
    NSArray *filteredArray = [self.avaliablePurchases filteredArrayUsingPredicate:predicate];
    if ([filteredArray count]) {
        NSDictionary *productInfo = [filteredArray objectAtIndex:0];
        SKProduct *product = [productInfo objectForKey:kProductKey];
        return product;
    }
    return nil;
}

- (SKPaymentTransaction *)lastTransactionForIdentidier:(NSString *)identifier {
    NSString *predicateString = [NSString stringWithFormat:@"transactionPaymentProductIdentifier like '%@'", identifier];
    
    NSPredicate *predicate = [NSPredicate predicateWithFormat:predicateString];
    NSArray *filteredArray = [completedTransactions filteredArrayUsingPredicate:predicate];
    
    if ([filteredArray count]) {        
        NSDictionary *transactionInfo = [filteredArray lastObject];
        return [transactionInfo objectForKey:kTransactionKey];
    } 
    return nil;
}

- (NSString *)lastTransactionRecieptForIdentidier:(NSString *)identifier {
    NSString *predicateString = [NSString stringWithFormat:@"transactionPaymentProductIdentifier like '%@'", identifier];
    
    NSPredicate *predicate = [NSPredicate predicateWithFormat:predicateString];
    NSArray *filteredArray = [completedTransactions filteredArrayUsingPredicate:predicate];
    
    if ([filteredArray count]) {        
        NSDictionary *transactionInfo = [filteredArray lastObject];
        return [transactionInfo objectForKey:kTransactionRecieptData];
    } 
    return nil;
}

- (NSString *)lastSuccessRecieptForIdentidier:(NSString *)identifier {
    NSString *predicateString = [NSString stringWithFormat:kLastGoodRecieptKeyFormat, identifier];
    return [defaults objectForKey:predicateString];
}

- (NSString *)encode:(const uint8_t *)input length:(NSInteger)length {
    static char table[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=";
    
    NSMutableData *data = [NSMutableData dataWithLength:((length + 2) / 3) * 4];
    uint8_t *output = (uint8_t *)data.mutableBytes;
    
    for (NSInteger i = 0; i < length; i += 3) {
        NSInteger value = 0;
        for (NSInteger j = i; j < (i + 3); j++) {
            value <<= 8;
            
            if (j < length) {
                value |= (0xFF & input[j]);
            }
        }
        
        NSInteger index = (i / 3) * 4;
        output[index + 0] =                    table[(value >> 18) & 0x3F];
        output[index + 1] =                    table[(value >> 12) & 0x3F];
        output[index + 2] = (i + 1) < length ? table[(value >> 6)  & 0x3F] : '=';
        output[index + 3] = (i + 2) < length ? table[(value >> 0)  & 0x3F] : '=';
    }
    NSString *returnString = [[[NSString alloc] initWithData:data encoding:NSASCIIStringEncoding] autorelease];
    return returnString;
}

- (void)setNetworkActivityIndicatorVisible:(BOOL)visible {
    if (self.isShowingActivityIndicator) {
        [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:visible];    
    }
}

#pragma mark - Dealloc
- (void)dealloc {
    [parser release];
    [completedTransactions release];
    [avaliablePurchases release];
    [super dealloc];
}

@end
