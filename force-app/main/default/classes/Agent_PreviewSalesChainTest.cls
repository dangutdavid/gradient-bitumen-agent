@isTest
private class Agent_PreviewSalesChainTest {

    private static AgentActionResult previewJson(AgentChainRequest req) {
        Agent_PreviewSalesChain.Request w = new Agent_PreviewSalesChain.Request();
        w.requestJson = JSON.serialize(req);
        return Agent_PreviewSalesChain.preview(new List<Agent_PreviewSalesChain.Request>{ w })[0];
    }

    @isTest
    static void completeRequestNeedsConfirmWithToken() {
        Account a = AgentChainTestFactory.account();
        Product2 p = AgentChainTestFactory.product();
        AgentChainRequest req = AgentChainTestFactory.validRequest('Commercial', a.Id, p.Id);

        Test.startTest();
        AgentActionResult r = previewJson(req);
        Test.stopTest();

        System.assertEquals(false, r.success, 'preview never "succeeds" — it asks to confirm');
        System.assertEquals(AgentActionResult.STATUS_NEEDS_CONFIRM, r.status);
        System.assert(r.missingFields.isEmpty(), 'nothing should be missing');
        Map<String, Object> summary = (Map<String, Object>) JSON.deserializeUntyped(r.summaryJson);
        System.assert(summary.containsKey('confirmationToken'), 'token present for confirm');
        System.assertEquals('Commercial_DKL', summary.get('recordTypeDeveloperName'));
    }

    @isTest
    static void missingFieldsConsolidatedNeedsInput() {
        Account a = AgentChainTestFactory.account();
        Product2 p = AgentChainTestFactory.product();
        AgentChainRequest req = AgentChainTestFactory.validRequest('Commercial', a.Id, p.Id);
        // Drop one field from two different records -> expect a consolidated list.
        req.lineFields.remove('PricePerMT_DKL__c');
        req.oppFields.remove('CloseDate');

        AgentActionResult r = previewJson(req);

        System.assertEquals(AgentActionResult.STATUS_NEEDS_INPUT, r.status);
        String joined = String.join(r.missingFields, ' | ');
        System.assert(joined.contains('Price (N/MT)'), 'price gap reported: ' + joined);
        System.assert(joined.contains('Close Date'), 'close date gap reported: ' + joined);
        System.assert(r.missingFields.size() >= 2, 'consolidated across records');
    }

    @isTest
    static void invalidTypeOfLoadAsksForIt() {
        Account a = AgentChainTestFactory.account();
        Product2 p = AgentChainTestFactory.product();
        AgentChainRequest req = AgentChainTestFactory.validRequest('Nonsense', a.Id, p.Id);

        AgentActionResult r = previewJson(req);

        System.assertEquals(AgentActionResult.STATUS_NEEDS_INPUT, r.status);
        System.assert(String.join(r.missingFields, ' | ').contains('Type of Load'));
    }

    @isTest
    static void accountMissingIsReported() {
        Product2 p = AgentChainTestFactory.product();
        AgentChainRequest req = AgentChainTestFactory.validRequest('Commercial', null, p.Id);
        AgentActionResult r = previewJson(req);
        System.assertEquals(AgentActionResult.STATUS_NEEDS_INPUT, r.status);
        System.assert(r.missingFields.contains('Account'), 'account gap reported');
    }

    @isTest
    static void nullRequestIsError() {
        System.assertEquals(AgentActionResult.STATUS_ERROR, AgentChainService.preview(null).status);
    }

    @isTest
    static void unparseableJsonReturnsError() {
        Agent_PreviewSalesChain.Request w = new Agent_PreviewSalesChain.Request();
        w.requestJson = '{not valid json';
        AgentActionResult r = Agent_PreviewSalesChain.preview(new List<Agent_PreviewSalesChain.Request>{ w })[0];
        System.assertEquals(AgentActionResult.STATUS_ERROR, r.status);
    }
}
