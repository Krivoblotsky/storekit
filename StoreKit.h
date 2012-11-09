//
//  StoreKit.h
//  StoreProject
//
//  Created by Serg Krivoblotsky on 1/6/12.
//  Copyright (c) 2012 Onix-Systems, LLC. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <StoreKit/StoreKit.h>

//iTunes Codes
enum {
    KSErrorCodeAllOK = 0,
    KSErrorCodeBadJSON = 21000,
    KSErrorCodeRecieptMalformed = 21002,
    KSErrorCodeRecieptNotAuthenificated = 21003,
    KSErrorCodeSharedSecredMissed = 21004,
    KSErrorCodeServerUnaavaliable = 21005,
    KSErrorCodeSubscriptionIsExpired = 21006,
    KSErrorCodeSanboxReciept = 21007,
    KSErrorCodeProductionReciept = 21008,
    KSErrorCodeNeedToRestoreTransactions = 999
    };
typedef NSInteger KSErrorCode;

@protocol StoreKitDelegate;
@class SBJSON;
@class ASIHTTPRequest;
@interface StoreKit : NSObject <SKProductsRequestDelegate, SKPaymentTransactionObserver> {
    @private
    NSUserDefaults *defaults;
    SKPaymentQueue *paymentQue;
    SBJSON *parser;
    @public
    NSMutableArray *avaliablePurchases;
    NSMutableArray *completedTransactions;
    BOOL sandbox;
    BOOL showActivityIndicator;
}
@property (getter = isShowingActivityIndicator) BOOL showActivityIndicator;
@property (nonatomic, readonly, getter = isSandbox) BOOL sandbox;
@property (nonatomic, retain) NSString *sharedSecret;
@property (nonatomic, assign) SKPaymentQueue *paymentQue;
@property (nonatomic, readonly) NSMutableArray *avaliablePurchases;
@property (nonatomic, readonly) NSMutableArray *completedTransactions;
@property (nonatomic, assign) id <StoreKitDelegate> delegate;

//Request abaliable products
- (void)requestAvaliableProducts:(NSString *)param, ...;
- (void)removeObjerver:(id <SKPaymentTransactionObserver>)observer;

//Requst comleted transactions
- (void)restoreComletedTransactions;

//Purchase product
- (void)purchaseProductWithIdentidier:(NSString *)identifier;
- (void)purchaseProduct:(SKProduct *)product;

//Check subscription
- (void)checkSubscriptionForProduct:(NSString *)productIdentidier;

//Verify reciept
- (BOOL)verifyRecieptForTransaction:(SKPaymentTransaction *)transaction;
- (BOOL)veriftRecieptDataSubscription:(NSString *)recieptData isSandBox:(BOOL)sandbox;

//Transactions actions
- (void)transactionSuccessed:(SKPaymentTransaction *)transaction;
- (void)transactionFailed:(SKPaymentTransaction *)transaction;
- (void)transactionRestored:(SKPaymentTransaction *)transaction;

//Get SKProduct
- (SKProduct *)productWithIdentifier:(NSString *)identifier;

//Last transaction
- (SKPaymentTransaction *)lastTransactionForIdentidier:(NSString *)identifier;
- (NSString *)lastTransactionRecieptForIdentidier:(NSString *)identifier;

//Encode reciept
- (NSString *)encode:(const uint8_t *)input length:(NSInteger)length;

//Activity indicator
- (void)setNetworkActivityIndicatorVisible:(BOOL)visible;

//Caching
- (void)cacheCompletedTransactions:(NSArray *)transactions;
- (void)cacheObject:(id)object forKey:(NSString *)key;

//Restoring
- (NSMutableArray *)restoreCompletedTransactionsFromCache;

//Last success
- (NSString *)lastSuccessRecieptForIdentidier:(NSString *)identifier;
@end

@protocol StoreKitDelegate <NSObject>
@optional
//Products info
- (void)storeKit:(StoreKit *)kit didRecieveProductsInfo:(NSArray *)products;

//Avaliable Transactions
- (void)storeKit:(StoreKit *)kit didRecieveCompletedTransactions:(NSArray *)transactions;
- (void)storeKit:(StoreKit *)kit didFailedComletedTransactionsWithError:(NSError *)error;

- (void)storeKit:(StoreKit *)kit didFailTransaction:(SKPaymentTransaction *)transaction withError:(NSError *)error;
- (void)storeKit:(StoreKit *)kit didTransactionSuccessed:(NSDictionary *)transcationInfo;
- (void)storeKit:(StoreKit *)kit didTransactionRestored:(NSDictionary *)transcationInfo;

//Subscription check
- (void)storeKit:(StoreKit *)kit didCheckedForSubrirptionWithError:(KSErrorCode)code recieptInfo:(NSDictionary *)recieptInfo;
- (void)storeKit:(StoreKit *)kit didCheckedForSubrirptionWithServerError:(NSError *)error;
@end
