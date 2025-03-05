@isTest
private class VendorCaseControllerTest {
    @TestSetup
    static void setup() {
        // Create test data
        Account acc = new Account(
            Name = 'Test Business Inc.',
            BillingStreet = '123 Test St',
            BillingCity = 'Test City',
            BillingState = 'CA',
            BillingPostalCode = '94105',
            BillingCountry = 'USA'
        );
        insert acc;

        Case testCase = new Case(
            Status = 'New',
            AccountId = acc.Id,
            Origin = 'Web',
            Subject = 'Test Case'
        );
        insert testCase;

        Product2 prod = new Product2(
            Name = 'Test Product',
            ProductCode = 'TEST123',
            IsActive = true
        );
        insert prod;

        Id stdPricebookId = Test.getStandardPricebookId();
        PricebookEntry pbe = new PricebookEntry(
            Product2Id = prod.Id,
            Pricebook2Id = stdPricebookId,
            UnitPrice = 100.0,
            IsActive = true
        );
        insert pbe;

        Case_Item__c item = new Case_Item__c(
            Case__c = testCase.Id,
            Product__c = prod.Id,
            Quantity__c = 2
        );
        insert item;
    }

    @isTest
    static void testGetCases() {
        List<Case> cases = VendorCaseController.getCases();

        System.assertNotEquals(0, cases.size(), 'Cases should be returned');
    }

    @isTest
    static void testGetCaseItems() {
        Case testCase = [
            SELECT Id
            FROM Case
            WHERE Subject = 'Test Case'
            LIMIT 1
        ];

        List<Case_Item__c> items = VendorCaseController.getCaseItems(
            testCase.Id
        );

        System.assertEquals(
            1,
            items.size(),
            'One Case_Item__c should be returned'
        );
        System.assertEquals(
            'Test Product',
            items[0].Product__r.Name,
            'Product Name should match'
        );
        System.assertEquals(2, items[0].Quantity__c, 'Quantity should match');
    }

    @isTest
    static void testCreateCaseItem() {
        Case testCase = [
            SELECT Id
            FROM Case
            WHERE Subject = 'Test Case'
            LIMIT 1
        ];
        Product2 prod = [
            SELECT Id
            FROM Product2
            WHERE ProductCode = 'TEST123'
            LIMIT 1
        ];

        String newItemId = VendorCaseController.createCaseItem(
            testCase.Id,
            prod.Id,
            3
        );

        Case_Item__c newItem = [
            SELECT Id, Case__c, Product__c, Quantity__c
            FROM Case_Item__c
            WHERE Id = :newItemId
        ];
        System.assertNotEquals(
            null,
            newItemId,
            'New Case_Item__c ID should be returned'
        );
        System.assertEquals(
            testCase.Id,
            newItem.Case__c,
            'Case ID should match'
        );
        System.assertEquals(
            prod.Id,
            newItem.Product__c,
            'Product ID should match'
        );
        System.assertEquals(3, newItem.Quantity__c, 'Quantity should match');
    }

    @isTest
    static void testUpdateCaseItem() {
        Case_Item__c item = [
            SELECT Id, Product__c, Quantity__c
            FROM Case_Item__c
            LIMIT 1
        ];
        Product2 newProd = new Product2(
            Name = 'New Product',
            ProductCode = 'NEW123',
            IsActive = true
        );
        insert newProd;
        Id stdPricebookId = Test.getStandardPricebookId();
        PricebookEntry newPbe = new PricebookEntry(
            Product2Id = newProd.Id,
            Pricebook2Id = stdPricebookId,
            UnitPrice = 200.0,
            IsActive = true
        );
        insert newPbe;

        VendorCaseController.updateCaseItem(item.Id, newProd.Id, 5);

        Case_Item__c updatedItem = [
            SELECT Product__c, Quantity__c
            FROM Case_Item__c
            WHERE Id = :item.Id
        ];
        System.assertEquals(
            newProd.Id,
            updatedItem.Product__c,
            'Product ID should be updated'
        );
        System.assertEquals(
            5,
            updatedItem.Quantity__c,
            'Quantity should be updated'
        );
    }

    @isTest
    static void testDeleteCaseItem() {
        Case_Item__c item = [SELECT Id FROM Case_Item__c LIMIT 1];

        VendorCaseController.deleteCaseItem(item.Id);

        List<Case_Item__c> deletedItems = [
            SELECT Id
            FROM Case_Item__c
            WHERE Id = :item.Id
        ];
        System.assertEquals(
            0,
            deletedItems.size(),
            'Case_Item__c should be deleted'
        );
    }
}
