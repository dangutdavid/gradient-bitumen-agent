@isTest
private class Agent_ResolveAccountTest {
  @TestSetup
  static void setup() {
    // The agent only resolves Gradient_Account records, so the resolvable fixtures must be that type.
    Id grad = AgentChainTestFactory.gradientAccountRtId();
    insert new List<Account>{
      new Account(Name = 'Globex Trading', RecordTypeId = grad),
      new Account(Name = 'Wayne Enterprises', RecordTypeId = grad),
      new Account(Name = 'Initech', RecordTypeId = grad),
      new Account(Name = 'Initech', RecordTypeId = grad),
      new Account(Name = 'Big Co Alpha', RecordTypeId = grad),
      new Account(Name = 'Big Co Beta', RecordTypeId = grad)
    };
  }

  private static AgentActionResult run(String term) {
    Agent_ResolveAccount.Request req = new Agent_ResolveAccount.Request();
    req.searchTerm = term;
    return Agent_ResolveAccount.resolve(
      new List<Agent_ResolveAccount.Request>{ req }
    )[0];
  }

  @isTest
  static void exactSingleMatch() {
    Test.startTest();
    AgentActionResult r = run('Globex Trading');
    Test.stopTest();
    System.assertEquals(true, r.success, 'exact single match should succeed');
    System.assertEquals(AgentActionResult.STATUS_OK, r.status);
    System.assert(r.recordId != null, 'resolved record Id set');
    System.assert(
      r.summaryJson.contains('Globex Trading'),
      'payload has the account'
    );
  }

  @isTest
  static void fuzzySingleMatch() {
    AgentActionResult r = run('Wayne');
    System.assertEquals(true, r.success, 'single partial match should succeed');
    System.assertEquals(AgentActionResult.STATUS_OK, r.status);
    System.assert(
      r.message.contains('partial match'),
      'should flag partial match'
    );
  }

  @isTest
  static void multipleExactMatchesAskForInput() {
    AgentActionResult r = run('Initech');
    System.assertEquals(
      false,
      r.success,
      'duplicate exact names should not resolve'
    );
    System.assertEquals(AgentActionResult.STATUS_NEEDS_INPUT, r.status);
    System.assert(
      r.summaryJson != null,
      'candidates returned for disambiguation'
    );
  }

  @isTest
  static void ambiguousPartialMatchesAskForInput() {
    AgentActionResult r = run('Big Co');
    System.assertEquals(
      false,
      r.success,
      'multiple partial matches should not resolve'
    );
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

  // ---- Gradient-only constraint (client decision #2, option 1) ----

  @isTest
  static void gradientAccountResolves() {
    // (a) a Gradient account resolves normally
    insert new Account(
      Name = 'Acme Gradient Co',
      RecordTypeId = AgentChainTestFactory.gradientAccountRtId()
    );
    AgentActionResult r = run('Acme Gradient Co');
    System.assertEquals(true, r.success, r.message);
    System.assertEquals(AgentActionResult.STATUS_OK, r.status);
  }

  @isTest
  static void nonGradientAccountExcluded() {
    // (b) a non-Gradient account with a matching name is excluded -> NOT FOUND (not an error)
    insert new Account(
      Name = 'Greenville Only Co',
      RecordTypeId = AgentChainTestFactory.greenvilleAccountRtId()
    );
    AgentActionResult r = run('Greenville Only Co');
    System.assertEquals(false, r.success, 'non-Gradient must not resolve');
    System.assertEquals(
      AgentActionResult.STATUS_NEEDS_INPUT,
      r.status,
      'not-found path, not ERROR'
    );
    System.assert(r.recordId == null, 'no silent wrong-account resolve');
    System.assert(r.message.contains('No account found'), r.message);
  }

  @isTest
  static void candidateListExcludesNonGradient() {
    // (c) the disambiguation candidate list only ever lists Gradient accounts
    Id grad = AgentChainTestFactory.gradientAccountRtId();
    insert new List<Account>{
      new Account(Name = 'GradMatch One', RecordTypeId = grad),
      new Account(Name = 'GradMatch Two', RecordTypeId = grad),
      new Account(
        Name = 'GradMatch Greenville',
        RecordTypeId = AgentChainTestFactory.greenvilleAccountRtId()
      )
    };
    AgentActionResult r = run('GradMatch');
    System.assertEquals(AgentActionResult.STATUS_NEEDS_INPUT, r.status);
    System.assert(
      r.summaryJson.contains('GradMatch One') &&
      r.summaryJson.contains('GradMatch Two'),
      'Gradient candidates listed: ' + r.summaryJson
    );
    System.assert(
      !r.summaryJson.contains('GradMatch Greenville'),
      'non-Gradient must NOT appear as a candidate: ' + r.summaryJson
    );
  }
}
