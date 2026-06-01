@isTest
private class AgentConversationControllerTest {

    @TestSetup
    static void setup() {
        insert new Account(Name = 'Ledya Foundry Ltd');
        insert new Product2(Name = 'Bitumen 60/70', Family = 'Bitumen 60/70', IsActive = true);
        AgentChainTestFactory.approvalRouting();
    }

    private static AgentConversationController.TurnResult turn(String text, String stateJson) {
        return AgentConversationController.advance(text, stateJson, null);
    }

    @isTest
    static void fullMultiTurnCreateAndSubmit() {
        Test.startTest();
        // Turn 1 — incomplete prompt: resolves account, parses line fields, asks for gaps.
        AgentConversationController.TurnResult t1 = turn(
            'Create a commercial loading advice for Ledya Foundry Ltd — 30 MT of Bitumen 60/70 at NGN 450,000/MT, deliver to Kano',
            null);
        System.assertEquals('NEEDS_INPUT', t1.status, t1.message);
        String gaps = String.join(t1.missingFields, ' | ');
        System.assert(gaps.contains('Close Date'), gaps);
        System.assert(gaps.contains('Start Date'), gaps);
        System.assert(gaps.contains('Customer Type'), gaps);

        // Turn 2 — fill all the gaps in one reply -> ready to confirm.
        AgentConversationController.TurnResult t2 = turn(
            'close 30/06/2026, order starts today, customer type credit', t1.stateJson);
        System.assertEquals('NEEDS_CONFIRM', t2.status, t2.message);
        System.assert(t2.summaryJson.contains('confirmationToken'), 'token present');

        // Turn 3 — confirm: commit (transaction 1), then auto-continue to submit.
        AgentConversationController.TurnResult t3 = turn('yes', t2.stateJson);
        System.assertEquals('OK', t3.status, t3.message);
        System.assertEquals(true, t3.autoContinue, 'LWC should auto-continue into submit');
        System.assertNotEquals(null, t3.recordId, 'Loading Advice created');

        // Turn 4 — submit (transaction 2): combined confirmation.
        AgentConversationController.TurnResult t4 = turn('', t3.stateJson);
        Test.stopTest();

        System.assertEquals('OK', t4.status, t4.message);
        Map<String, Object> created = (Map<String, Object>) JSON.deserializeUntyped(t4.summaryJson);
        System.assertEquals(true, created.get('submitted'), 'submitted in step 2');

        Loading_Advice__c la = [
            SELECT RecordType.DeveloperName, Status_DKL__c, Approval_Status_DKL__c,
                   Order_DKL__r.Opportunity.Name
            FROM Loading_Advice__c WHERE Id = :t4.recordId
        ];
        System.assertEquals('Commercial_DKL', la.RecordType.DeveloperName);
        System.assertEquals('Pending 1st Approver', la.Approval_Status_DKL__c);
        // Report-friendly Opp name: account + product + date.
        String oppName = la.Order_DKL__r.Opportunity.Name;
        System.assert(oppName.contains('Ledya Foundry Ltd'), oppName);
        System.assert(oppName.contains('Bitumen 60/70'), oppName);
        // The whole chain exists.
        Account a = [SELECT Id FROM Account WHERE Name = 'Ledya Foundry Ltd' LIMIT 1];
        System.assertEquals(1, [SELECT COUNT() FROM Opportunity WHERE AccountId = :a.Id]);
        System.assertEquals(1, [SELECT COUNT() FROM Order WHERE AccountId = :a.Id]);
        System.assertEquals(1, [SELECT COUNT() FROM Loading_Advice_Line__c WHERE Customer_DKL__c = :a.Id]);
    }

    @isTest
    static void unresolvedAccountAsksForIt() {
        AgentConversationController.TurnResult t = turn(
            'commercial LA for Nonexistent Company Zzz — 5 MT', null);
        System.assertEquals('NEEDS_INPUT', t.status);
        System.assert(t.missingFields.contains('Account'), 'asks for the account');
    }

    @isTest
    static void confirmNoCancels() {
        AgentConversationController.TurnResult t1 = turn(
            'commercial loading advice for Ledya Foundry Ltd — 30 MT of Bitumen 60/70 at NGN 450,000/MT, deliver to Kano',
            null);
        AgentConversationController.TurnResult t2 = turn(
            'close 30/06/2026, order starts today, customer type credit', t1.stateJson);
        System.assertEquals('NEEDS_CONFIRM', t2.status);

        AgentConversationController.TurnResult t3 = turn('no', t2.stateJson);
        System.assertEquals('OK', t3.status);
        System.assert(t3.message.contains('Cancelled'), t3.message);
        // nothing created
        Account a = [SELECT Id FROM Account WHERE Name = 'Ledya Foundry Ltd' LIMIT 1];
        System.assertEquals(0, [SELECT COUNT() FROM Loading_Advice__c WHERE Account_DKL__c = :a.Id]);
    }

    @isTest
    static void confirmUnclearReasksYesNo() {
        AgentConversationController.TurnResult t1 = turn(
            'commercial loading advice for Ledya Foundry Ltd — 30 MT of Bitumen 60/70 at NGN 450,000/MT, deliver to Kano',
            null);
        AgentConversationController.TurnResult t2 = turn(
            'close 30/06/2026, order starts today, customer type credit', t1.stateJson);
        AgentConversationController.TurnResult t3 = turn('maybe later', t2.stateJson);
        System.assertEquals('NEEDS_CONFIRM', t3.status);
        System.assert(t3.message.toLowerCase().contains('yes'), t3.message);
    }
}
