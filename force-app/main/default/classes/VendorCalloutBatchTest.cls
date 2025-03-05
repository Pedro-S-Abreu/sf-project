@isTest
private class VendorCalloutBatchTest {
    private class VendorCalloutMock implements HttpCalloutMock {
        private Integer statusCode;

        public VendorCalloutMock(Integer statusCode) {
            this.statusCode = statusCode;
        }

        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            if (statusCode == 200) {
                res.setBody('{"Order_Id": "TEST123"}');
            } else {
                res.setBody('{"error": "Callout failed"}');
            }
            res.setStatusCode(statusCode);
            return res;
        }
    }

    @TestSetup
    static void setup() {
        Id businessAccountRTId;
        try {
            businessAccountRTId = [
                SELECT Id
                FROM RecordType
                WHERE
                    SobjectType = 'Account'
                    AND DeveloperName = 'Business_Account'
                LIMIT 1
            ]
            ?.Id;
        } catch (Exception e) {
            businessAccountRTId = null;
        }

        Account acc = new Account(
            Name = 'Test Business Inc.',
            BillingStreet = '123 Test St',
            BillingCity = 'Test City',
            BillingState = 'CA',
            BillingPostalCode = '94105',
            BillingCountry = 'USA',
            RecordTypeId = businessAccountRTId
        );
        insert acc;

        Contact con = new Contact(
            FirstName = 'John',
            LastName = 'Doe',
            Phone = '123-456-7890',
            AccountId = acc.Id
        );
        insert con;

        Case testCase = new Case(
            Status = 'Submit to Vendor',
            AccountId = acc.Id,
            ContactId = con.Id,
            Origin = 'Web'
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
    static void testBatchSuccess() {
        List<Case> testCases = [
            SELECT Id, AccountId, ContactId
            FROM Case
            WHERE Status = 'Submit to Vendor'
            LIMIT 1
        ];
        Test.setMock(HttpCalloutMock.class, new VendorCalloutMock(200));

        Test.startTest();
        VendorCalloutBatch batch = new VendorCalloutBatch(testCases);
        Id batchId = Database.executeBatch(batch, 1);
        Test.stopTest();

        List<Order> orders = [
            SELECT Id, Status, OrderReferenceNumber, Pricebook2Id
            FROM Order
        ];
        System.assertEquals(1, orders.size(), 'One Order should be created');
        System.assertEquals(
            'Activated',
            orders[0].Status,
            'Order should be activated'
        );
        System.assertEquals(
            'TEST123',
            orders[0].OrderReferenceNumber,
            'OrderReferenceNumber should match response'
        );
        System.assertNotEquals(
            null,
            orders[0].Pricebook2Id,
            'Order should have Pricebook2Id'
        );

        List<OrderItem> orderItems = [
            SELECT Id, OrderId, Quantity, UnitPrice
            FROM OrderItem
        ];
        System.assertEquals(
            1,
            orderItems.size(),
            'One OrderItem should be created'
        );
        System.assertEquals(
            2,
            orderItems[0].Quantity,
            'Quantity should match Case_Item__c'
        );
        System.assertEquals(
            100.0,
            orderItems[0].UnitPrice,
            'UnitPrice should match PricebookEntry'
        );

        List<Vendor_Callout_Log__c> logs = [
            SELECT Id, Case__c, Is_Successful__c, Order__c
            FROM Vendor_Callout_Log__c
        ];
        System.assertEquals(1, logs.size(), 'One log should be created');
        System.assertEquals(
            true,
            logs[0].Is_Successful__c,
            'Log should indicate success'
        );
        System.assertEquals(
            orders[0].Id,
            logs[0].Order__c,
            'Log should link to Order'
        );
    }

    @isTest
    static void testBatchFailure() {
        List<Case> testCases = [
            SELECT Id
            FROM Case
            WHERE Status = 'Submit to Vendor'
            LIMIT 1
        ];
        Test.setMock(HttpCalloutMock.class, new VendorCalloutMock(400));

        Test.startTest();
        VendorCalloutBatch batch = new VendorCalloutBatch(testCases);
        Id batchId = Database.executeBatch(batch, 1);
        Test.stopTest();

        List<Order> orders = [SELECT Id FROM Order];
        System.assertEquals(
            0,
            orders.size(),
            'No Orders should be created on failure'
        );

        List<Vendor_Callout_Log__c> logs = [
            SELECT Id, Case__c, Is_Successful__c
            FROM Vendor_Callout_Log__c
        ];
        System.assertEquals(1, logs.size(), 'One log should be created');
        System.assertEquals(
            false,
            logs[0].Is_Successful__c,
            'Log should indicate failure'
        );
        System.assertEquals(
            testCases[0].Id,
            logs[0].Case__c,
            'Log should link to Case'
        );
    }

    @isTest
    static void testBatchEmptyCaseItems() {
        Case emptyCase = new Case(Status = 'Submit to Vendor', Origin = 'Web');
        insert emptyCase;
        List<Case> testCases = new List<Case>{ emptyCase };
        Test.setMock(HttpCalloutMock.class, new VendorCalloutMock(200));

        Test.startTest();
        VendorCalloutBatch batch = new VendorCalloutBatch(testCases);
        Id batchId = Database.executeBatch(batch, 1);
        Test.stopTest();

        List<Order> orders = [SELECT Id FROM Order];
        System.assertEquals(
            0,
            orders.size(),
            'No Orders should be created without Case Items'
        );

        List<Vendor_Callout_Log__c> logs = [
            SELECT Id
            FROM Vendor_Callout_Log__c
        ];
        System.assertEquals(
            0,
            logs.size(),
            'No logs should be created without Case Items'
        );
    }
}
