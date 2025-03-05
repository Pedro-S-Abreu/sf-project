public with sharing class VendorCaseController {
    @AuraEnabled(cacheable=true)
    public static List<Case> getCases() {
        return [
            SELECT Id, CaseNumber, Subject
            FROM Case
            WHERE Status != 'Submit to Vendor'
            LIMIT 50
        ];
    }

    @AuraEnabled(cacheable=true)
    public static List<Case_Item__c> getCaseItems(String caseId) {
        return [
            SELECT Id, Product__r.Id, Product__r.Name, Quantity__c
            FROM Case_Item__c
            WHERE Case__c = :caseId
        ];
    }

    @AuraEnabled(cacheable=true)
    public static PricebookEntry getDefaultPricebookEntry() {
        return [
            SELECT Id, Product2Id, ProductCode, Product2.Name
            FROM PricebookEntry
            WHERE Pricebook2.IsStandard = TRUE
            LIMIT 1
        ];
    }

    @AuraEnabled
    public static String createCaseItem(
        String caseId,
        String productId,
        Integer quantity
    ) {
        Case_Item__c newItem = new Case_Item__c(
            Case__c = caseId,
            Product__c = productId,
            Quantity__c = quantity
        );
        insert newItem;
        return newItem.Id;
    }

    @AuraEnabled
    public static void updateCaseItem(
        String itemId,
        String productId,
        Integer quantity
    ) {
        Case_Item__c item = new Case_Item__c(
            Id = itemId,
            Product__c = productId,
            Quantity__c = quantity
        );
        update item;
    }

    @AuraEnabled
    public static void deleteCaseItem(String itemId) {
        Case_Item__c item = new Case_Item__c(Id = itemId);
        delete item;
    }
}
