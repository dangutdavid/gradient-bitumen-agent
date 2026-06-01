@isTest
private class AgentIntentRouterTest {
  @isTest
  static void classifiesInsightObjectAndCreate() {
    // Read-only record question -> ACCOUNT_INSIGHT (even though it contains "for <name>").
    System.assertEquals(
      AgentIntentRouter.INTENT_ACCOUNT_INSIGHT,
      AgentIntentRouter.classify('list all orders for Test Olam'),
      'list orders for X must classify as insight, not create'
    );
    System.assertEquals(
      AgentIntentRouter.INTENT_ACCOUNT_INSIGHT,
      AgentIntentRouter.classify('show me the orders related to this account')
    );

    // Object/required-field question -> OBJECT_INFO.
    System.assertEquals(
      AgentIntentRouter.INTENT_OBJECT_INFO,
      AgentIntentRouter.classify('what does a loading advice need?')
    );
    System.assertEquals(
      AgentIntentRouter.INTENT_OBJECT_INFO,
      AgentIntentRouter.classify('describe the order object')
    );

    // Create instruction -> CREATE (not hijacked by "for <name>" or "loading advice").
    System.assertEquals(
      AgentIntentRouter.INTENT_CREATE,
      AgentIntentRouter.classify(
        'commercial loading advice for Acme Ltd — 30 MT of Bitumen 60/70 at NGN 450,000/MT, deliver to Kano'
      )
    );
    System.assertEquals(
      AgentIntentRouter.INTENT_CREATE,
      AgentIntentRouter.classify('')
    );
  }

  @isTest
  static void needPhraseWithoutWhatDoesIsObjectInfo() {
    // hits the second OBJECT_INFO branch (need + loading advice, no "what does"/"describe")
    System.assertEquals(
      AgentIntentRouter.INTENT_OBJECT_INFO,
      AgentIntentRouter.classify('do I need anything else for a loading advice')
    );
  }

  @isTest
  static void unknownClassifierFallsBackToRuleBased() {
    AgentIntentRouter.classifierOverride = 'NoSuchClassifier_xyz';
    System.assertEquals(
      AgentIntentRouter.INTENT_CREATE,
      AgentIntentRouter.classify('hello')
    );
  }
}
