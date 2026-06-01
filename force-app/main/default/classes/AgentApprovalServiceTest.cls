@isTest
private class AgentApprovalServiceTest {

    @isTest
    static void submitWithLinesSucceedsUpdatesStatusAndAttachesPdf() {
        AgentChainTestFactory.approvalRouting();
        Account a = AgentChainTestFactory.account();
        Product2 p = AgentChainTestFactory.product();
        Loading_Advice__c la = AgentChainTestFactory.loadingAdvice(a.Id, p.Id, true);

        Test.startTest();
        AgentActionResult r = AgentApprovalService.submit(la.Id);
        Test.stopTest();

        System.assertEquals(true, r.success, r.message);
        System.assertEquals(AgentActionResult.STATUS_OK, r.status);

        Loading_Advice__c after = [
            SELECT Status_DKL__c, Approval_Status_DKL__c, SubmittedOn_DKL__c, Submittedby_DKL__c
            FROM Loading_Advice__c WHERE Id = :la.Id
        ];
        System.assertEquals('Draft', after.Status_DKL__c);
        System.assertEquals('Pending 1st Approver', after.Approval_Status_DKL__c);
        System.assertNotEquals(null, after.SubmittedOn_DKL__c, 'SubmittedOn stamped');
        System.assertEquals(UserInfo.getUserId(), after.Submittedby_DKL__c, 'Submittedby stamped');

        Integer pdfs = [SELECT COUNT() FROM ContentVersion WHERE FirstPublishLocationId = :la.Id];
        System.assert(pdfs >= 1, 'internal PDF attached to the LA');
    }

    @isTest
    static void submitWithNoLinesErrorsAndLeavesStatusUnchanged() {
        AgentChainTestFactory.approvalRouting();
        Account a = AgentChainTestFactory.account();
        Product2 p = AgentChainTestFactory.product();
        Loading_Advice__c la = AgentChainTestFactory.loadingAdvice(a.Id, p.Id, false); // no line

        Test.startTest();
        AgentActionResult r = AgentApprovalService.submit(la.Id);
        Test.stopTest();

        System.assertEquals(AgentActionResult.STATUS_ERROR, r.status);
        System.assert(r.message.contains('no lines'), r.message);

        Loading_Advice__c after = [SELECT Approval_Status_DKL__c FROM Loading_Advice__c WHERE Id = :la.Id];
        System.assertEquals(null, after.Approval_Status_DKL__c, 'status untouched when empty');
    }

    @isTest
    static void nullIdIsNeedsInput() {
        AgentActionResult r = AgentApprovalService.submit(null);
        System.assertEquals(AgentActionResult.STATUS_NEEDS_INPUT, r.status);
    }

    @isTest
    static void invocableWrapperDelegates() {
        AgentChainTestFactory.approvalRouting();
        Account a = AgentChainTestFactory.account();
        Product2 p = AgentChainTestFactory.product();
        Loading_Advice__c la = AgentChainTestFactory.loadingAdvice(a.Id, p.Id, true);

        Agent_SubmitLAForApproval.Request w = new Agent_SubmitLAForApproval.Request();
        w.loadingAdviceId = la.Id;
        Test.startTest();
        AgentActionResult r = Agent_SubmitLAForApproval.submit(new List<Agent_SubmitLAForApproval.Request>{ w })[0];
        Test.stopTest();
        System.assertEquals(AgentActionResult.STATUS_OK, r.status, r.message);
    }
}
