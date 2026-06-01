@isTest
private class Agent_CommitSalesChainTest {

    private static AgentActionResult commitJson(AgentChainRequest req) {
        Agent_CommitSalesChain.Request w = new Agent_CommitSalesChain.Request();
        w.requestJson = JSON.serialize(req);
        return Agent_CommitSalesChain.commitChain(new List<Agent_CommitSalesChain.Request>{ w })[0];
    }

    private static Integer chainCount(Id accountId) {
        return [SELECT COUNT() FROM Opportunity WHERE AccountId = :accountId]
             + [SELECT COUNT() FROM Order WHERE AccountId = :accountId]
             + [SELECT COUNT() FROM Loading_Advice__c WHERE Account_DKL__c = :accountId]
             + [SELECT COUNT() FROM Loading_Advice_Line__c WHERE Customer_DKL__c = :accountId];
    }

    @isTest
    static void happyPathCreatesAllFourThreadedAndLinked() {
        Account a = AgentChainTestFactory.account();
        Product2 p = AgentChainTestFactory.product();
        AgentChainRequest req = AgentChainTestFactory.validRequest('Commercial', a.Id, p.Id);

        Test.startTest();
        // End-to-end: preview to get the confirmation token, then commit with it (the real flow).
        Agent_PreviewSalesChain.Request pw = new Agent_PreviewSalesChain.Request();
        pw.requestJson = JSON.serialize(req);
        AgentActionResult prev = Agent_PreviewSalesChain.preview(new List<Agent_PreviewSalesChain.Request>{ pw })[0];
        System.assertEquals(AgentActionResult.STATUS_NEEDS_CONFIRM, prev.status, prev.message);
        Map<String, Object> previewSummary = (Map<String, Object>) JSON.deserializeUntyped(prev.summaryJson);
        req.confirmationToken = (String) previewSummary.get('confirmationToken');

        AgentActionResult r = commitJson(req); // exercises the invocable wrapper + JSON coercion
        Test.stopTest();

        System.assertEquals(true, r.success, r.message);
        System.assertEquals(AgentActionResult.STATUS_OK, r.status);

        // All four exist, parents threaded correctly.
        Opportunity opp = [SELECT Id FROM Opportunity WHERE AccountId = :a.Id LIMIT 1];
        Order ord = [SELECT Id, OpportunityId, AccountId FROM Order WHERE AccountId = :a.Id LIMIT 1];
        Loading_Advice__c la = [
            SELECT Id, Order_DKL__c, Account_DKL__c, Opportunity_DKL__c, RecordType.DeveloperName,
                   Status_DKL__c, Approval_Status_DKL__c
            FROM Loading_Advice__c WHERE Account_DKL__c = :a.Id LIMIT 1
        ];
        Loading_Advice_Line__c line = [
            SELECT Id, LoadingAdvice_DKL__c FROM Loading_Advice_Line__c WHERE Customer_DKL__c = :a.Id LIMIT 1
        ];

        System.assertEquals(opp.Id, ord.OpportunityId, 'Order links to the Opp');
        System.assertEquals(ord.Id, la.Order_DKL__c, 'LA master is the Order');
        System.assertEquals(opp.Id, la.Opportunity_DKL__c, 'LA opp lookup threaded');
        System.assertEquals(la.Id, line.LoadingAdvice_DKL__c, 'Line master is the LA');
        System.assertEquals('Commercial_DKL', la.RecordType.DeveloperName);
        System.assertEquals('Draft', la.Status_DKL__c, 'Status defaulted to Draft');

        // Commit creates the chain only; submit is a separate transaction (getContentAsPDF
        // can't render with these inserts uncommitted). So not yet submitted here.
        System.assertEquals(null, la.Approval_Status_DKL__c, 'not submitted by commit');
        System.assertEquals(String.valueOf(la.Id), r.recordId);
        Map<String, Object> created = (Map<String, Object>) JSON.deserializeUntyped(r.summaryJson);
        System.assert(created.containsKey('opportunity') && created.containsKey('line'), 'all links present');
        System.assertEquals(false, created.get('submitted'), 'commit does not submit');
        System.assertEquals(true, created.get('readyToSubmit'), 'ready for the submit step');
    }

    @isTest
    static void stockTransferSetsItsRecordType() {
        Account a = AgentChainTestFactory.account();
        Product2 p = AgentChainTestFactory.product();
        AgentChainRequest req = AgentChainTestFactory.withToken(
            AgentChainTestFactory.validRequest('Stock Transfer', a.Id, p.Id));

        AgentActionResult r = AgentChainService.commitChain(req);

        System.assertEquals(AgentActionResult.STATUS_OK, r.status, r.message);
        Loading_Advice__c la = [SELECT RecordType.DeveloperName FROM Loading_Advice__c WHERE Account_DKL__c = :a.Id LIMIT 1];
        System.assertEquals('StockTransfer_DKL', la.RecordType.DeveloperName);
    }

    @isTest
    static void missingFieldBlocksCommitAndCreatesNothing() {
        Account a = AgentChainTestFactory.account();
        Product2 p = AgentChainTestFactory.product();
        AgentChainRequest req = AgentChainTestFactory.validRequest('Commercial', a.Id, p.Id);
        req.lineFields.remove('PricePerMT_DKL__c'); // gap
        req.confirmationToken = AgentChainService.token(req);

        AgentActionResult r = AgentChainService.commitChain(req);

        System.assertEquals(AgentActionResult.STATUS_NEEDS_INPUT, r.status);
        System.assertEquals(0, chainCount(a.Id), 'nothing created when a field is missing');
    }

    @isTest
    static void commitWithoutTokenIsRejected() {
        Account a = AgentChainTestFactory.account();
        Product2 p = AgentChainTestFactory.product();
        AgentChainRequest req = AgentChainTestFactory.validRequest('Commercial', a.Id, p.Id);
        req.confirmationToken = null; // not confirmed

        AgentActionResult r = AgentChainService.commitChain(req);

        System.assertEquals(AgentActionResult.STATUS_ERROR, r.status);
        System.assertEquals(0, chainCount(a.Id), 'no token -> nothing created');
    }

    @isTest
    static void commitWithWrongTokenIsRejected() {
        Account a = AgentChainTestFactory.account();
        Product2 p = AgentChainTestFactory.product();
        AgentChainRequest req = AgentChainTestFactory.validRequest('Commercial', a.Id, p.Id);
        req.confirmationToken = 'deadbeef-not-the-real-token';

        AgentActionResult r = AgentChainService.commitChain(req);

        System.assertEquals(AgentActionResult.STATUS_ERROR, r.status);
        System.assertEquals(0, chainCount(a.Id), 'wrong token -> nothing created');
    }

    @isTest
    static void commitThenSubmitTwoStep() {
        // The orchestration flow: commit (txn 1) then submit (txn 2). In a test both run in
        // one transaction, but submit uses the dummy-PDF path so it behaves like production.
        AgentChainTestFactory.approvalRouting();
        Account a = AgentChainTestFactory.account();
        Product2 p = AgentChainTestFactory.product();
        AgentChainRequest req = AgentChainTestFactory.withToken(
            AgentChainTestFactory.validRequest('Commercial', a.Id, p.Id));

        Test.startTest();
        AgentActionResult commitRes = AgentChainService.commitChain(req);
        System.assertEquals(AgentActionResult.STATUS_OK, commitRes.status, commitRes.message);
        AgentActionResult submitRes = AgentApprovalService.submit((Id) commitRes.recordId);
        Test.stopTest();

        System.assertEquals(AgentActionResult.STATUS_OK, submitRes.status, submitRes.message);
        Loading_Advice__c la = [SELECT Approval_Status_DKL__c FROM Loading_Advice__c WHERE Id = :commitRes.recordId];
        System.assertEquals('Pending 1st Approver', la.Approval_Status_DKL__c, 'submitted after commit');
    }

    @isTest
    static void nullRequestIsError() {
        System.assertEquals(AgentActionResult.STATUS_ERROR, AgentChainService.commitChain(null).status);
    }

    @isTest
    static void unparseableJsonIsError() {
        Agent_CommitSalesChain.Request w = new Agent_CommitSalesChain.Request();
        w.requestJson = '{broken json';
        AgentActionResult r = Agent_CommitSalesChain.commitChain(new List<Agent_CommitSalesChain.Request>{ w })[0];
        System.assertEquals(AgentActionResult.STATUS_ERROR, r.status);
    }

    @isTest
    static void midChainFailureRollsBackEverything() {
        Account a = AgentChainTestFactory.account();
        Product2 p = AgentChainTestFactory.product();

        // A valid-format but non-existent Account Id => Line insert fails with
        // INVALID_CROSS_REFERENCE_KEY *after* Opp/Order/LA have been inserted.
        Account ghost = new Account(Name = 'Ghost');
        insert ghost;
        Id ghostId = ghost.Id;
        delete ghost;

        AgentChainRequest req = AgentChainTestFactory.validRequest('Commercial', a.Id, p.Id);
        req.lineFields.put('Customer_DKL__c', ghostId); // breaks the final insert
        req.confirmationToken = AgentChainService.token(req);

        Test.startTest();
        AgentActionResult r = AgentChainService.commitChain(req);
        Test.stopTest();

        System.assertEquals(AgentActionResult.STATUS_ERROR, r.status);
        System.assert(r.message.contains('Nothing was created'), r.message);
        // Whole chain rolled back: no Opp/Order/LA left behind either.
        System.assertEquals(0, [SELECT COUNT() FROM Opportunity WHERE AccountId = :a.Id]);
        System.assertEquals(0, [SELECT COUNT() FROM Order WHERE AccountId = :a.Id]);
        System.assertEquals(0, [SELECT COUNT() FROM Loading_Advice__c WHERE Account_DKL__c = :a.Id]);
    }
}
