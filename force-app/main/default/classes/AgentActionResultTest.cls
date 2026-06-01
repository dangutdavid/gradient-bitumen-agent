@isTest
private class AgentActionResultTest {

    @isTest
    static void okSerializesSummary() {
        AgentActionResult r = AgentActionResult.ok('done', new Map<String, Object>{ 'k' => 'v' });
        System.assertEquals(true, r.success, 'ok() should be success');
        System.assertEquals(AgentActionResult.STATUS_OK, r.status);
        System.assertEquals('done', r.message);
        System.assert(r.summaryJson != null && r.summaryJson.contains('"k":"v"'), 'summary should serialize');
    }

    @isTest
    static void okWithNullSummaryLeavesJsonNull() {
        AgentActionResult r = AgentActionResult.ok('no payload', null);
        System.assertEquals(true, r.success);
        System.assertEquals(null, r.summaryJson, 'null summary leaves summaryJson null');
    }

    @isTest
    static void needsInputCarriesMissingFields() {
        AgentActionResult r = AgentActionResult.needsInput('need stuff', new List<String>{ 'a', 'b' });
        System.assertEquals(false, r.success);
        System.assertEquals(AgentActionResult.STATUS_NEEDS_INPUT, r.status);
        System.assertEquals(2, r.missingFields.size());
    }

    @isTest
    static void needsConfirmSerializesSummary() {
        AgentActionResult r = AgentActionResult.needsConfirm('confirm?', new Map<String, Object>{ 'x' => 1 });
        System.assertEquals(false, r.success);
        System.assertEquals(AgentActionResult.STATUS_NEEDS_CONFIRM, r.status);
        System.assert(r.summaryJson.contains('"x":1'));
    }

    @isTest
    static void errorIsErrorStatus() {
        AgentActionResult r = AgentActionResult.error('boom');
        System.assertEquals(false, r.success);
        System.assertEquals(AgentActionResult.STATUS_ERROR, r.status);
        System.assertEquals('boom', r.message);
    }

    @isTest
    static void withRecordSetsIdAndUrl() {
        Account a = new Account(Name = 'Url Co');
        insert a;
        AgentActionResult r = AgentActionResult.ok('ok', null).withRecord(a.Id);
        System.assertEquals(String.valueOf(a.Id), r.recordId);
        System.assert(r.recordUrl != null && r.recordUrl.endsWith(a.Id), 'url ends with the record Id');
    }

    @isTest
    static void withRecordNullIsNoOp() {
        AgentActionResult r = AgentActionResult.ok('ok', null).withRecord(null);
        System.assertEquals(null, r.recordId);
        System.assertEquals(null, r.recordUrl);
    }

    @isTest
    static void defaultConstructorIsSuccessOk() {
        AgentActionResult r = new AgentActionResult();
        System.assertEquals(true, r.success);
        System.assertEquals(AgentActionResult.STATUS_OK, r.status);
        System.assertEquals(0, r.missingFields.size());
    }
}
