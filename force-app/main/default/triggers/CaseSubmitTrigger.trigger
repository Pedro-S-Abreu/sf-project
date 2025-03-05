trigger CaseSubmitTrigger on Case(after update) {
    List<Case> casesForCallout = new List<Case>();
    Set<Id> caseIds = new Set<Id>();
    for (Case updatedCase : Trigger.new) {
        Case oldCase = Trigger.oldMap.get(updatedCase.Id);
        if (
            updatedCase.Status == 'Submit to Vendor' &&
            oldCase.Status != 'Submit to Vendor'
        ) {
            casesForCallout.add(updatedCase);
            caseIds.add(updatedCase.Id);
        }
    }
    if (!casesForCallout.isEmpty()) {
        Database.executeBatch(new VendorCalloutBatch(casesForCallout), 50);
    }
}
