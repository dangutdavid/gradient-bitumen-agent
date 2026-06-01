@isTest
private class Agent_DescribeObjectTest {

    private static AgentActionResult run(String apiName) {
        Agent_DescribeObject.Request req = new Agent_DescribeObject.Request();
        req.objectApiName = apiName;
        return Agent_DescribeObject.describe(new List<Agent_DescribeObject.Request>{ req })[0];
    }

    @isTest
    static void describesStandardObject() {
        AgentActionResult r = run('Account');
        System.assertEquals(true, r.success);
        Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(r.summaryJson);
        System.assertEquals('Account', data.get('objectApiName'));
        System.assert((Integer) data.get('fieldCount') > 0, 'should have fields');
        System.assert(r.summaryJson.contains('"apiName":"Name"'), 'Name field present');
    }

    @isTest
    static void describesLoadingAdviceWithRelationshipAndPicklist() {
        AgentActionResult r = run('Loading_Advice__c');
        System.assertEquals(true, r.success);
        // master-detail lookup target captured
        System.assert(r.summaryJson.contains('referenceTo'), 'lookup metadata captured');
        System.assert(r.summaryJson.contains('Order_DKL__c'), 'Order master-detail field present');
        // a picklist field with values
        System.assert(r.summaryJson.contains('picklistValues'), 'picklist metadata captured');
    }

    @isTest
    static void unknownObjectFails() {
        AgentActionResult r = run('Totally_Not_Real__x');
        System.assertEquals(false, r.success);
        System.assert(r.message.contains('not found'));
    }

    @isTest
    static void blankApiNameFails() {
        AgentActionResult r = run('');
        System.assertEquals(false, r.success);
    }
}
