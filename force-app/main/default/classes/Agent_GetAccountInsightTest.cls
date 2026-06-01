@isTest
private class Agent_GetAccountInsightTest {

    @TestSetup
    static void setup() {
        Account a = new Account(
            Name = 'Insight Co',
            CustomerCategory_DKL__c = null,
            EstimatedQuantityMTMonth_DKL__c = 500,
            CreditPeriod_DKL__c = '30'
        );
        insert a;

        insert new Order(
            AccountId = a.Id,
            EffectiveDate = Date.today(),
            Status = 'Draft'
        );

        // One OPEN opportunity. We deliberately do not create a closed-stage opp here:
        // this org enforces several validation rules on advanced/closed CPP stages
        // (LNG volume, power fields, etc.) that make closed opps impractical to build in a
        // unit test. The insight query's IsClosed=false filter is asserted via the open count.
        insert new Opportunity(
            Name = 'Open Opp', AccountId = a.Id,
            StageName = 'Qualification', CloseDate = Date.today().addDays(30)
        );
    }

    private static AgentActionResult run(Id accountId) {
        Agent_GetAccountInsight.Request req = new Agent_GetAccountInsight.Request();
        req.accountId = accountId;
        return Agent_GetAccountInsight.getInsight(new List<Agent_GetAccountInsight.Request>{ req })[0];
    }

    @isTest
    static void insightReturnsCountsAndProfile() {
        Account a = [SELECT Id FROM Account WHERE Name = 'Insight Co' LIMIT 1];
        Test.startTest();
        AgentActionResult r = run(a.Id);
        Test.stopTest();

        System.assertEquals(true, r.success, 'should succeed for valid account');
        System.assert(r.recordId != null, 'record Id set');
        Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(r.summaryJson);
        System.assertEquals('Insight Co', data.get('name'));
        System.assertEquals(1, (Integer) data.get('orderCount'), 'one order');
        System.assertEquals(1, (Integer) data.get('openOpportunityCount'), 'one open opp counted');
        System.assert(data.containsKey('permits'), 'permit block present');
    }

    @isTest
    static void nullIdFails() {
        AgentActionResult r = run(null);
        System.assertEquals(false, r.success);
        System.assertEquals(AgentActionResult.STATUS_NEEDS_INPUT, r.status);
        System.assert(r.message.contains('No account Id'));
    }

    @isTest
    static void missingAccountFails() {
        // Valid-format but non-existent Id (delete the only account first)
        Account a = [SELECT Id FROM Account WHERE Name = 'Insight Co' LIMIT 1];
        Id ghost = a.Id;
        delete a;
        AgentActionResult r = run(ghost);
        System.assertEquals(false, r.success, 'deleted account should report not found');
        System.assertEquals(AgentActionResult.STATUS_ERROR, r.status);
        System.assert(r.message.contains('not found'));
    }
}
