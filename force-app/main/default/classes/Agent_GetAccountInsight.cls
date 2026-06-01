/**
 * Phase 1 agent action: summarise an Account for the sales agent.
 * Returns key commercial attributes, permit status, and counts of related
 * Orders and open Opportunities. Read-only.
 */
public with sharing class Agent_GetAccountInsight {

    public class Request {
        @InvocableVariable(label='Account Id' required=true)
        public Id accountId;
    }

    @InvocableMethod(label='Get Account Insight' description='Summarise an Account: commercial profile, permits, and related record counts.')
    public static List<AgentActionResult> getInsight(List<Request> requests) {
        List<AgentActionResult> results = new List<AgentActionResult>();
        for (Request req : requests) {
            results.add(insightFor(req == null ? null : req.accountId));
        }
        return results;
    }

    private static AgentActionResult insightFor(Id accountId) {
        if (accountId == null) {
            return AgentActionResult.needsInput('No account Id provided.', new List<String>{ 'accountId' });
        }

        List<Account> accts = [
            SELECT Id, Name, CustomerCategory_DKL__c, EstimatedQuantityMTMonth_DKL__c,
                   CreditPeriod_DKL__c, HaulagePermitOrMOU_DKL__c, OffTakePermitValidity_DKL__c,
                   StoragePermitOrMOU_DKL__c, PermitExpiryStatus_DKL__c
            FROM Account
            WHERE Id = :accountId
            LIMIT 1
        ];
        if (accts.isEmpty()) {
            return AgentActionResult.error('Account ' + accountId + ' not found.');
        }
        Account a = accts[0];

        Integer orderCount = [SELECT COUNT() FROM Order WHERE AccountId = :accountId];
        Integer openOppCount = [SELECT COUNT() FROM Opportunity WHERE AccountId = :accountId AND IsClosed = false];

        Map<String, Object> data = new Map<String, Object>{
            'accountId' => a.Id,
            'name' => a.Name,
            'customerCategory' => a.CustomerCategory_DKL__c,
            'estimatedQtyMTPerMonth' => a.EstimatedQuantityMTMonth_DKL__c,
            'creditPeriod' => a.CreditPeriod_DKL__c,
            'permits' => new Map<String, Object>{
                'haulagePermitOrMOU' => a.HaulagePermitOrMOU_DKL__c,
                'offTakePermitValid' => a.OffTakePermitValidity_DKL__c,
                'storagePermitOrMOU' => a.StoragePermitOrMOU_DKL__c,
                'expiryStatus' => a.PermitExpiryStatus_DKL__c
            },
            'orderCount' => orderCount,
            'openOpportunityCount' => openOppCount
        };
        return AgentActionResult.ok('Insight for "' + a.Name + '".', data).withRecord(a.Id);
    }
}
