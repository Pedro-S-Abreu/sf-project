public class VendorCalloutBatch implements Database.Batchable<sObject>, Database.AllowsCallouts {
    private List<Case> cases;

    public VendorCalloutBatch(List<Case> cases) {
        this.cases = cases;
    }

    public Iterable<sObject> start(Database.BatchableContext bc) {
        return cases;
    }

    public void execute(Database.BatchableContext bc, List<Case> scope) {
        Vendor_API_Settings__mdt settings;
        try {
            settings = [
                SELECT Endpoint_URL__c, Bearer_Token__c
                FROM Vendor_API_Settings__mdt
                WHERE DeveloperName = 'VendorCallout'
                LIMIT 1
            ];
            system.debug('here01' + settings);
        } catch (Exception e) {
            system.debug('here02');
            System.debug(
                'Unable to find "VendorCallout" Vendor_API_Settings__mdt record: ' +
                e.getMessage()
            );
            return;
        }
        String endpointUrl = settings.Endpoint_URL__c;
        String bearerToken = settings.Bearer_Token__c;
        Pricebook2 standardPricebook;
        if (!Test.isRunningTest()) {
            standardPricebook = [
                SELECT Id
                FROM Pricebook2
                WHERE IsStandard = TRUE
                LIMIT 1
            ];
        } else {
            standardPricebook = new Pricebook2(
                Id = Test.getStandardPricebookId()
            );
        }

        Map<Id, List<Case_Item__c>> caseItemsMap = new Map<Id, List<Case_Item__c>>();
        for (Case_Item__c item : [
            SELECT Id, Case__c, Product__c, Quantity__c, Product__r.ProductCode
            FROM Case_Item__c
            WHERE Case__c IN :scope
        ]) {
            if (!caseItemsMap.containsKey(item.Case__c)) {
                caseItemsMap.put(item.Case__c, new List<Case_Item__c>());
            }
            caseItemsMap.get(item.Case__c).add(item);
        }

        List<Order> ordersToInsert = new List<Order>();
        List<OrderItem> orderItemsToInsert = new List<OrderItem>();
        List<Vendor_Callout_Log__c> logsToInsert = new List<Vendor_Callout_Log__c>();

        for (Case c : scope) {
            List<Case_Item__c> items = caseItemsMap.get(c.Id) != null
                ? caseItemsMap.get(c.Id)
                : new List<Case_Item__c>();
            if (items.isEmpty()) {
                System.debug('No items for Case: ' + c.Id);
                continue;
            }

            VendorRequestBody requestBody = new VendorRequestBody(c, items);
            String jsonBody = JSON.serialize(requestBody);

            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpointUrl + '/submit-order');
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setHeader('Authorization', 'Bearer ' + bearerToken);
            req.setBody(jsonBody);

            Http http = new Http();
            HttpResponse res;
            try {
                res = http.send(req);

                Vendor_Callout_Log__c log = new Vendor_Callout_Log__c(
                    Case__c = c.Id,
                    Request__c = jsonBody,
                    Response__c = res.getBody(),
                    Is_Successful__c = (res.getStatusCode() == 200),
                    Callout_DateTime__c = DateTime.now()
                );

                if (res.getStatusCode() == 200) {
                    Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(
                        res.getBody()
                    );
                    String orderId = (String) responseMap.get('Order_Id');

                    Order ord = new Order(
                        AccountId = c.AccountId,
                        EffectiveDate = Date.today(),
                        Status = 'Draft',
                        Pricebook2Id = standardPricebook.Id,
                        OrderReferenceNumber = orderId
                    );
                    ordersToInsert.add(ord);
                    log.Order__c = ord.Id;
                } else {
                    System.debug(
                        'Callout failed for Case ' +
                            c.Id +
                            ': ' +
                            res.getStatus()
                    );
                }
                system.debug('here1');
                logsToInsert.add(log);
            } catch (Exception e) {
                System.debug(
                    'Callout error for Case ' + c.Id + ': ' + e.getMessage()
                );
                system.debug('here2');
                logsToInsert.add(
                    new Vendor_Callout_Log__c(
                        Case__c = c.Id,
                        Request__c = jsonBody,
                        Response__c = e.getMessage(),
                        Is_Successful__c = false,
                        Callout_DateTime__c = DateTime.now()
                    )
                );
            }
        }

        if (!ordersToInsert.isEmpty()) {
            try {
                insert ordersToInsert;

                Map<Id, PricebookEntry> productIdToEntry = new Map<Id, PricebookEntry>();
                for (PricebookEntry pbe : [
                    SELECT Id, Product2Id, UnitPrice
                    FROM PricebookEntry
                    WHERE
                        Pricebook2Id = :standardPricebook.Id
                        AND Product2Id IN :getProductIds(caseItemsMap)
                ]) {
                    productIdToEntry.put(pbe.Product2Id, pbe);
                }

                for (Integer i = 0; i < ordersToInsert.size(); i++) {
                    Order ord = ordersToInsert[i];
                    Case c = scope[i];
                    for (Case_Item__c item : caseItemsMap.get(c.Id)) {
                        PricebookEntry pbe = productIdToEntry.get(
                            item.Product__c
                        );
                        if (pbe != null) {
                            orderItemsToInsert.add(
                                new OrderItem(
                                    OrderId = ord.Id,
                                    Product2Id = item.Product__c,
                                    PricebookEntryId = pbe.Id,
                                    Quantity = item.Quantity__c,
                                    UnitPrice = pbe.UnitPrice
                                )
                            );
                        } else {
                            System.debug(
                                'No PricebookEntry found for Product: ' +
                                item.Product__c
                            );
                        }
                    }
                    for (Vendor_Callout_Log__c log : logsToInsert) {
                        if (log.Case__c == c.Id && log.Order__c == null) {
                            log.Order__c = ord.Id;
                        }
                    }
                }

                if (!orderItemsToInsert.isEmpty()) {
                    insert orderItemsToInsert;
                    System.debug('Order Items inserted: ' + orderItemsToInsert);

                    for (Order ord : ordersToInsert) {
                        ord.Status = 'Activated';
                    }
                    update ordersToInsert;
                    System.debug('Orders activated: ' + ordersToInsert);
                }
            } catch (Exception e) {
                System.debug('Commit error: ' + e.getMessage());
                System.debug('Exception Type: ' + e.getTypeName());
                System.debug('Stack Trace: ' + e.getStackTraceString());
                System.debug(
                    'Line Number: ' + e.getStackTraceString().split(':')[0]
                );
            }
        }

        if (!logsToInsert.isEmpty()) {
            insert logsToInsert;
        }
    }

    private Set<Id> getProductIds(Map<Id, List<Case_Item__c>> itemsMap) {
        Set<Id> productIds = new Set<Id>();
        for (List<Case_Item__c> items : itemsMap.values()) {
            for (Case_Item__c item : items) {
                if (item.Product__c != null) {
                    productIds.add(item.Product__c);
                }
            }
        }
        return productIds;
    }

    public void finish(Database.BatchableContext bc) {
        System.debug('Vendor callout batch completed');
    }

    public class VendorRequestBody {
        public Address Address;
        public List<Item> Items;

        public VendorRequestBody(Case c, List<Case_Item__c> caseItems) {
            Case queriedCase = [
                SELECT
                    Id,
                    Contact.FirstName,
                    Contact.LastName,
                    Contact.Phone,
                    Account.BillingStreet,
                    Account.BillingCity,
                    Account.BillingState,
                    Account.BillingPostalCode,
                    Account.BillingCountry,
                    Account.Name
                FROM Case
                WHERE Id = :c.Id
                LIMIT 1
            ];

            this.Address = new Address();

            if (queriedCase.Contact != null) {
                this.Address.FirstName = queriedCase.Contact.FirstName;
                this.Address.LastName = queriedCase.Contact.LastName;
                this.Address.Phone = queriedCase.Contact.Phone;
            }

            if (queriedCase.Account != null) {
                this.Address.Street = queriedCase.Account.BillingStreet;
                this.Address.City = queriedCase.Account.BillingCity;
                this.Address.State = queriedCase.Account.BillingState;
                this.Address.PostalCode = queriedCase.Account.BillingPostalCode;
                this.Address.Country = queriedCase.Account.BillingCountry;
                this.Address.CompanyName = queriedCase.Account.Name;
            }

            this.Items = new List<Item>();
            for (Case_Item__c item : caseItems) {
                this.Items.add(
                    new Item(
                        item.Product__r.ProductCode,
                        (Integer) item.Quantity__c
                    )
                );
            }
        }
    }

    public class Address {
        public String City;
        public String CompanyName;
        public String Country;
        public String FirstName;
        public String LastName;
        public String Phone;
        public String PostalCode;
        public String State;
        public String Street;
    }

    public class Item {
        public String ProductCode;
        public Integer Quantity;

        public Item(String productCode, Integer quantity) {
            this.ProductCode = productCode;
            this.Quantity = quantity;
        }
    }
}
