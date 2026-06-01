@isTest
private class Agent_ResolveAccountTest {

    @TestSetup
    static void setup() {
        insert new List<Account>{
            new Account(Name = 'Globex Trading'),
            new Account(Name = 'Wayne Enterprises'),
            new Account(Name = 'Initech'),
            new Account(Name = 'Initech'),
            new Account(Name = 'Big Co Alpha'),
            new Account(Name = 'Big Co Beta')
        };
    }

    private static AgentActionResult run(String term) {
        Agent_ResolveAccount.Request req = new Agent_ResolveAccount.Request();
        req.searchTerm = term;
        return Agent_ResolveAccount.resolve(new List<Agent_ResolveAccount.Request>{ req })[0];
    }

    @isTest
    static void exactSingleMatch() {
        Test.startTest();
        AgentActionResult r = run('Globex Trading');
        Test.stopTest();
        System.assertEquals(true, r.success, 'exact single match should succeed');
        System.assertEquals(AgentActionResult.STATUS_OK, r.status);
        System.assert(r.recordId != null, 'resolved record Id set');
        System.assert(r.summaryJson.contains('Globex Trading'), 'payload has the account');
    }

    @isTest
    static void fuzzySingleMatch() {
        AgentActionResult r = run('Wayne');
        System.assertEquals(true, r.success, 'single partial match should succeed');
        System.assertEquals(AgentActionResult.STATUS_OK, r.status);
        System.assert(r.message.contains('partial match'), 'should flag partial match');
    }

    @isTest
    static void multipleExactMatchesAskForInput() {
        AgentActionResult r = run('Initech');
        System.assertEquals(false, r.success, 'duplicate exact names should not resolve');
        System.assertEquals(AgentActionResult.STATUS_NEEDS_INPUT, r.status);
        System.assert(r.summaryJson != null, 'candidates returned for disambiguation');
    }

    @isTest
    static void ambiguousPartialMatchesAskForInput() {
        AgentActionResult r = run('Big Co');
        System.assertEquals(false, r.success, 'multiple partial matches should not resolve');
        System.assertEquals(AgentActionResult.STATUS_NEEDS_INPUT, r.status);
        System.assert(r.summaryJson != null, 'candidate list provided');
    }

    @isTest
    static void noMatchAsksForInput() {
        AgentActionResult r = run('Nonexistent Company Zzz');
        System.assertEquals(false, r.success);
        System.assertEquals(AgentActionResult.STATUS_NEEDS_INPUT, r.status);
        System.assert(r.message.contains('No account'), 'reports no match');
    }

    @isTest
    static void blankTermAsksForInput() {
        AgentActionResult r = run('   ');
        System.assertEquals(false, r.success, 'blank term should fail');
        System.assertEquals(AgentActionResult.STATUS_NEEDS_INPUT, r.status);
        System.assertEquals('account', r.missingFields[0]);
    }
}
