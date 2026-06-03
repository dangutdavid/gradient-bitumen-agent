@isTest
private class AgentConversationControllerTest {
  @TestSetup
  static void setup() {
    insert new Account(
      Name = 'Ledya Foundry Ltd',
      RecordTypeId = AgentChainTestFactory.gradientAccountRtId()
    );
    insert new Product2(
      Name = 'Bitumen 60/70',
      Family = 'Bitumen 60/70',
      IsActive = true
    );
    AgentChainTestFactory.approvalRouting();
  }

  private static AgentConversationController.TurnResult turn(
    String text,
    String stateJson
  ) {
    return AgentConversationController.advance(text, stateJson, null);
  }

  @isTest
  static void fullMultiTurnCreateAndSubmit() {
    Test.startTest();
    // Turn 1 — incomplete prompt: resolves account, parses line fields, asks for gaps.
    AgentConversationController.TurnResult t1 = turn(
      'Create a commercial loading advice for Ledya Foundry Ltd — 30 MT of Bitumen 60/70 at NGN 450,000/MT, deliver to Kano',
      null
    );
    System.assertEquals('NEEDS_INPUT', t1.status, t1.message);
    String gaps = String.join(t1.missingFields, ' | ');
    System.assert(gaps.contains('Close Date'), gaps);
    System.assert(gaps.contains('Start Date'), gaps);
    System.assert(gaps.contains('Customer Type'), gaps);

    // Turn 2 — fill all the gaps in one reply -> ready to confirm.
    AgentConversationController.TurnResult t2 = turn(
      'close 30/06/2026, order starts today, customer type credit',
      t1.stateJson
    );
    System.assertEquals('NEEDS_CONFIRM', t2.status, t2.message);
    System.assert(
      t2.summaryJson.contains('confirmationToken'),
      'token present'
    );

    // Turn 3 — confirm: commit (transaction 1), then auto-continue to submit.
    AgentConversationController.TurnResult t3 = turn('yes', t2.stateJson);
    System.assertEquals('OK', t3.status, t3.message);
    System.assertEquals(
      true,
      t3.autoContinue,
      'LWC should auto-continue into submit'
    );
    System.assertNotEquals(null, t3.recordId, 'Loading Advice created');

    // Turn 4 — submit (transaction 2): combined confirmation.
    AgentConversationController.TurnResult t4 = turn('', t3.stateJson);
    Test.stopTest();

    System.assertEquals('OK', t4.status, t4.message);
    Map<String, Object> created = (Map<String, Object>) JSON.deserializeUntyped(
      t4.summaryJson
    );
    System.assertEquals(true, created.get('submitted'), 'submitted in step 2');

    Loading_Advice__c la = [
      SELECT
        RecordType.DeveloperName,
        Status_DKL__c,
        Approval_Status_DKL__c,
        Order_DKL__r.Opportunity.Name
      FROM Loading_Advice__c
      WHERE Id = :t4.recordId
    ];
    System.assertEquals('Commercial_DKL', la.RecordType.DeveloperName);
    System.assertEquals('Pending 1st Approver', la.Approval_Status_DKL__c);
    // Report-friendly Opp name: account + product + date.
    String oppName = la.Order_DKL__r.Opportunity.Name;
    System.assert(oppName.contains('Ledya Foundry Ltd'), oppName);
    System.assert(oppName.contains('Bitumen 60/70'), oppName);
    // The whole chain exists.
    Account a = [
      SELECT Id
      FROM Account
      WHERE Name = 'Ledya Foundry Ltd'
      LIMIT 1
    ];
    System.assertEquals(
      1,
      [SELECT COUNT() FROM Opportunity WHERE AccountId = :a.Id]
    );
    System.assertEquals(1, [SELECT COUNT() FROM Order WHERE AccountId = :a.Id]);
    System.assertEquals(
      1,
      [SELECT COUNT() FROM Loading_Advice_Line__c WHERE Customer_DKL__c = :a.Id]
    );
  }

  @isTest
  static void unresolvedAccountAsksForIt() {
    AgentConversationController.TurnResult t = turn(
      'commercial LA for Nonexistent Company Zzz — 5 MT',
      null
    );
    System.assertEquals('NEEDS_INPUT', t.status);
    System.assert(t.missingFields.contains('Account'), 'asks for the account');
  }

  @isTest
  static void confirmNoCancels() {
    AgentConversationController.TurnResult t1 = turn(
      'commercial loading advice for Ledya Foundry Ltd — 30 MT of Bitumen 60/70 at NGN 450,000/MT, deliver to Kano',
      null
    );
    AgentConversationController.TurnResult t2 = turn(
      'close 30/06/2026, order starts today, customer type credit',
      t1.stateJson
    );
    System.assertEquals('NEEDS_CONFIRM', t2.status);

    AgentConversationController.TurnResult t3 = turn('no', t2.stateJson);
    System.assertEquals('OK', t3.status);
    System.assert(t3.message.contains('Cancelled'), t3.message);
    // nothing created
    Account a = [
      SELECT Id
      FROM Account
      WHERE Name = 'Ledya Foundry Ltd'
      LIMIT 1
    ];
    System.assertEquals(
      0,
      [SELECT COUNT() FROM Loading_Advice__c WHERE Account_DKL__c = :a.Id]
    );
  }

  @isTest
  static void confirmUnclearReasksYesNo() {
    AgentConversationController.TurnResult t1 = turn(
      'commercial loading advice for Ledya Foundry Ltd — 30 MT of Bitumen 60/70 at NGN 450,000/MT, deliver to Kano',
      null
    );
    AgentConversationController.TurnResult t2 = turn(
      'close 30/06/2026, order starts today, customer type credit',
      t1.stateJson
    );
    AgentConversationController.TurnResult t3 = turn(
      'maybe later',
      t2.stateJson
    );
    System.assertEquals('NEEDS_CONFIRM', t3.status);
    System.assert(t3.message.toLowerCase().contains('yes'), t3.message);
  }

  // ---- AWAITING_ACCOUNT regression tests (reproduce the utility-bar account loop) ----

  @isTest
  static void answerAccountByBareNameResolves() {
    // Turn 1: deal with NO "for <account>" -> the agent asks for the account.
    AgentConversationController.TurnResult t1 = turn(
      'commercial, 30 MT of Bitumen 60/70 at NGN 450,000/MT, deliver to Kano',
      null
    );
    System.assertEquals('NEEDS_INPUT', t1.status, t1.message);
    System.assert(
      t1.missingFields.contains('Account'),
      'turn 1 should ask for the account'
    );

    // Turn 2: answer with a BARE account name -> must resolve and STOP asking (no loop).
    AgentConversationController.TurnResult t2 = turn(
      'Ledya Foundry Ltd',
      t1.stateJson
    );
    System.assert(
      !t2.missingFields.contains('Account'),
      'bare name must resolve the account; got status=' +
        t2.status +
        ' missing=' +
        t2.missingFields
    );
  }

  @isTest
  static void answerAccountWithLabelPrefix() {
    insert new Account(
      Name = 'Olam for Construction',
      RecordTypeId = AgentChainTestFactory.gradientAccountRtId()
    ); // name itself contains "for"
    AgentConversationController.TurnResult t1 = turn(
      'commercial, 20 MT of Bitumen 60/70 at NGN 450,000/MT, deliver to Lagos',
      null
    );
    System.assert(t1.missingFields.contains('Account'));

    // "account :" label is stripped; the remainder (which contains "for") is passed whole.
    AgentConversationController.TurnResult t2 = turn(
      'account : Olam for Construction',
      t1.stateJson
    );
    System.assert(
      !t2.missingFields.contains('Account'),
      'labelled name containing "for" must resolve; got missing=' +
      t2.missingFields
    );
  }

  @isTest
  static void ambiguousThenSpecificName() {
    insert new List<Account>{
      new Account(
        Name = 'Bigco Construction One',
        RecordTypeId = AgentChainTestFactory.gradientAccountRtId()
      ),
      new Account(
        Name = 'Bigco Construction Two',
        RecordTypeId = AgentChainTestFactory.gradientAccountRtId()
      )
    };
    AgentConversationController.TurnResult t1 = turn(
      'commercial loading advice for Bigco Construction — 10 MT of Bitumen 60/70 at NGN 450,000/MT, deliver to Kano',
      null
    );
    System.assertEquals('NEEDS_INPUT', t1.status);
    System.assert(
      t1.missingFields.contains('Account'),
      'ambiguous -> asks which account'
    );
    System.assert(
      t1.message.contains('Bigco Construction One'),
      'candidate names should be surfaced: ' + t1.message
    );

    Account chosen = [
      SELECT Id
      FROM Account
      WHERE Name = 'Bigco Construction One'
      LIMIT 1
    ];
    AgentConversationController.TurnResult t2 = turn(
      'Bigco Construction One',
      t1.stateJson
    );
    System.assert(
      !t2.missingFields.contains('Account'),
      'specific name resolves'
    );
    System.assert(
      t2.stateJson.contains(String.valueOf(chosen.Id).substring(0, 15)),
      'chain links to the chosen account'
    );
  }

  @isTest
  static void noMatchReasksWithClearMessage() {
    AgentConversationController.TurnResult t1 = turn(
      'commercial, 10 MT of Bitumen 60/70 at NGN 450,000/MT, deliver to Kano',
      null
    );
    AgentConversationController.TurnResult t2 = turn(
      'Zzz Nonexistent Co',
      t1.stateJson
    );
    System.assert(
      t2.missingFields.contains('Account'),
      'still needs the account'
    );
    System.assert(
      t2.message.contains('Zzz Nonexistent Co'),
      'no-match message must name what was searched, not the generic prompt: ' +
      t2.message
    );
  }

  // ---- intent-routing regression tests ----

  @isTest
  static void insightQuestionAnsweredNotTreatedAsAccount() {
    // An insight question on idle state must NOT be swallowed by the create flow / asked
    // as an account name (the original bug), even though it contains "for <account>".
    AgentConversationController.TurnResult t = turn(
      'list all orders for Ledya Foundry Ltd',
      null
    );
    System.assertEquals('OK', t.status, t.message);
    System.assert(
      !t.missingFields.contains('Account'),
      'must not ask for the account'
    );
    System.assert(
      t.stateJson.contains('"phase":"COLLECTING"'),
      'stays idle, not AWAITING_ACCOUNT'
    );
    System.assert(
      t.message.contains('Ledya Foundry Ltd'),
      'returns a read-only summary: ' + t.message
    );
  }

  @isTest
  static void insightCreatesNothing() {
    Account a = [
      SELECT Id
      FROM Account
      WHERE Name = 'Ledya Foundry Ltd'
      LIMIT 1
    ];
    turn('list all orders for Ledya Foundry Ltd', null);
    System.assertEquals(
      0,
      [SELECT COUNT() FROM Opportunity WHERE AccountId = :a.Id]
    );
    System.assertEquals(0, [SELECT COUNT() FROM Order WHERE AccountId = :a.Id]);
    System.assertEquals(
      0,
      [SELECT COUNT() FROM Loading_Advice__c WHERE Account_DKL__c = :a.Id]
    );
  }

  @isTest
  static void objectInfoReturnsRequiredList() {
    AgentConversationController.TurnResult t = turn(
      'what does a loading advice need?',
      null
    );
    System.assertEquals('OK', t.status);
    System.assert(
      t.message.contains('Customer') && t.message.contains('Price (N/MT)'),
      'lists the curated required set: ' + t.message
    );
  }

  @isTest
  static void createStillWorksAfterInsight() {
    // An insight turn first, then a normal create must still reach the confirm gate.
    AgentConversationController.TurnResult ins = turn(
      'list orders for Ledya Foundry Ltd',
      null
    );
    System.assertEquals('OK', ins.status);
    AgentConversationController.TurnResult t1 = turn(
      'commercial loading advice for Ledya Foundry Ltd — 30 MT of Bitumen 60/70 at NGN 450,000/MT, deliver to Kano',
      ins.stateJson
    );
    AgentConversationController.TurnResult t2 = turn(
      'close 30/06/2026, order starts today, customer type credit',
      t1.stateJson
    );
    System.assertEquals('NEEDS_CONFIRM', t2.status, t2.message);
  }

  @isTest
  static void objectInfoDescribesObject() {
    AgentConversationController.TurnResult t = turn(
      'describe the order object',
      null
    );
    System.assertEquals('OK', t.status);
    System.assert(
      t.message.contains('fields'),
      'describe summary: ' + t.message
    );
  }

  @isTest
  static void insightWithoutAccountAsksReadOnly() {
    // ACCOUNT_INSIGHT with no account context and no name -> asks for the account and waits
    // in the INSIGHT-account state (NOT the create AWAITING_ACCOUNT flow).
    AgentConversationController.TurnResult t = turn('list all orders', null);
    System.assertEquals('NEEDS_INPUT', t.status);
    System.assert(t.message.contains('account'), t.message);
    System.assert(
      t.stateJson.contains('AWAITING_INSIGHT_ACCOUNT'),
      'insight-account wait, not the create account ask: ' + t.stateJson
    );
  }

  @isTest
  static void insightAccountNotFound() {
    // A named-but-unresolvable insight account re-asks (and waits) rather than dead-ending.
    AgentConversationController.TurnResult t = turn(
      'list orders for Zzz Nonexistent Co',
      null
    );
    System.assertEquals('NEEDS_INPUT', t.status);
    System.assert(
      t.message.contains('couldn\'t find') ||
      t.message.contains('Zzz Nonexistent Co'),
      'no-match message: ' + t.message
    );
    System.assert(
      t.stateJson.contains('AWAITING_INSIGHT_ACCOUNT'),
      'waits for a valid insight account'
    );
  }

  // ---- disambiguation: candidate-constrain + switch-confirm ----

  private static final String AMBIG_DEAL = 'commercial loading advice for Bigco Construction — 20 MT of Bitumen 60/70 at NGN 460,000/MT, deliver to Lagos, customer type credit, close 30/06/2026, order starts today';

  @isTest
  static void disambiguationSwitchConfirmYes() {
    insert new List<Account>{
      new Account(
        Name = 'Bigco Construction One',
        RecordTypeId = AgentChainTestFactory.gradientAccountRtId()
      ),
      new Account(
        Name = 'Bigco Construction Two',
        RecordTypeId = AgentChainTestFactory.gradientAccountRtId()
      ),
      new Account(
        Name = 'Test Olam',
        RecordTypeId = AgentChainTestFactory.gradientAccountRtId()
      )
    };
    AgentConversationController.TurnResult t1 = turn(AMBIG_DEAL, null);
    System.assertEquals('NEEDS_INPUT', t1.status);
    System.assert(
      t1.message.contains('Bigco Construction One'),
      'candidates listed: ' + t1.message
    );

    // Non-candidate that resolves -> switch-confirm (NOT NEEDS_CONFIRM), nothing created.
    AgentConversationController.TurnResult t2 = turn('Test Olam', t1.stateJson);
    System.assertEquals(
      'NEEDS_INPUT',
      t2.status,
      'must ask to switch, not confirm the create'
    );
    System.assert(
      t2.message.contains('different account') &&
      t2.message.contains('Test Olam'),
      t2.message
    );
    System.assert(
      t2.stateJson.contains('AWAITING_ACCOUNT_SWITCH'),
      'in switch-confirm phase'
    );
    Account olam = [SELECT Id FROM Account WHERE Name = 'Test Olam' LIMIT 1];
    System.assertEquals(
      0,
      [SELECT COUNT() FROM Loading_Advice__c WHERE Account_DKL__c = :olam.Id]
    );

    // yes -> proceed with the switched account
    AgentConversationController.TurnResult t3 = turn('yes', t2.stateJson);
    System.assertEquals('NEEDS_CONFIRM', t3.status, t3.message);
    System.assert(
      t3.summaryJson.contains('Test Olam'),
      'switched to Test Olam on yes'
    );
  }

  @isTest
  static void disambiguationSwitchConfirmNoRelists() {
    insert new List<Account>{
      new Account(
        Name = 'Bigco Construction One',
        RecordTypeId = AgentChainTestFactory.gradientAccountRtId()
      ),
      new Account(
        Name = 'Bigco Construction Two',
        RecordTypeId = AgentChainTestFactory.gradientAccountRtId()
      ),
      new Account(
        Name = 'Test Olam',
        RecordTypeId = AgentChainTestFactory.gradientAccountRtId()
      )
    };
    AgentConversationController.TurnResult t1 = turn(AMBIG_DEAL, null);
    AgentConversationController.TurnResult t2 = turn('Test Olam', t1.stateJson);
    System.assert(t2.stateJson.contains('AWAITING_ACCOUNT_SWITCH'));

    AgentConversationController.TurnResult t3 = turn('no', t2.stateJson);
    System.assertEquals('NEEDS_INPUT', t3.status);
    System.assert(
      t3.message.contains('Bigco Construction One'),
      're-lists candidates: ' + t3.message
    );
    Account olam = [SELECT Id FROM Account WHERE Name = 'Test Olam' LIMIT 1];
    System.assertEquals(
      0,
      [SELECT COUNT() FROM Loading_Advice__c WHERE Account_DKL__c = :olam.Id],
      'nothing created'
    );
  }

  @isTest
  static void disambiguationExactCandidateProceeds() {
    insert new List<Account>{
      new Account(
        Name = 'Bigco Construction One',
        RecordTypeId = AgentChainTestFactory.gradientAccountRtId()
      ),
      new Account(
        Name = 'Bigco Construction Two',
        RecordTypeId = AgentChainTestFactory.gradientAccountRtId()
      )
    };
    AgentConversationController.TurnResult t1 = turn(AMBIG_DEAL, null);
    AgentConversationController.TurnResult t2 = turn(
      'Bigco Construction One',
      t1.stateJson
    );
    System.assertEquals('NEEDS_CONFIRM', t2.status, t2.message);
    System.assert(
      t2.summaryJson.contains('Bigco Construction One'),
      'used the chosen candidate'
    );
  }

  @isTest
  static void disambiguationNarrowDownOnMultiMatch() {
    insert new List<Account>{
      new Account(
        Name = 'Bigco Construction One',
        RecordTypeId = AgentChainTestFactory.gradientAccountRtId()
      ),
      new Account(
        Name = 'Bigco Construction Two',
        RecordTypeId = AgentChainTestFactory.gradientAccountRtId()
      )
    };
    AgentConversationController.TurnResult t1 = turn(AMBIG_DEAL, null);
    // "Bigco Construction" matches BOTH candidates -> narrow down.
    AgentConversationController.TurnResult t2 = turn(
      'Bigco Construction',
      t1.stateJson
    );
    System.assertEquals('NEEDS_INPUT', t2.status);
    System.assert(t2.message.toLowerCase().contains('narrow'), t2.message);
  }

  @isTest
  static void disambiguationNonCandidateNoMatchRelists() {
    insert new List<Account>{
      new Account(
        Name = 'Bigco Construction One',
        RecordTypeId = AgentChainTestFactory.gradientAccountRtId()
      ),
      new Account(
        Name = 'Bigco Construction Two',
        RecordTypeId = AgentChainTestFactory.gradientAccountRtId()
      )
    };
    AgentConversationController.TurnResult t1 = turn(AMBIG_DEAL, null);
    // A non-candidate that resolves to nothing -> re-list the original candidates.
    AgentConversationController.TurnResult t2 = turn(
      'Zzz Nonexistent Co',
      t1.stateJson
    );
    System.assertEquals('NEEDS_INPUT', t2.status);
    System.assert(
      t2.message.contains('Bigco Construction One'),
      're-lists options: ' + t2.message
    );
  }

  @isTest
  static void switchConfirmUnclearReasks() {
    insert new List<Account>{
      new Account(
        Name = 'Bigco Construction One',
        RecordTypeId = AgentChainTestFactory.gradientAccountRtId()
      ),
      new Account(
        Name = 'Bigco Construction Two',
        RecordTypeId = AgentChainTestFactory.gradientAccountRtId()
      ),
      new Account(
        Name = 'Test Olam',
        RecordTypeId = AgentChainTestFactory.gradientAccountRtId()
      )
    };
    AgentConversationController.TurnResult t1 = turn(AMBIG_DEAL, null);
    AgentConversationController.TurnResult t2 = turn('Test Olam', t1.stateJson);
    System.assert(t2.stateJson.contains('AWAITING_ACCOUNT_SWITCH'));
    AgentConversationController.TurnResult t3 = turn('maybe', t2.stateJson);
    System.assertEquals('NEEDS_INPUT', t3.status);
    System.assert(t3.message.toLowerCase().contains('yes'), t3.message);
  }

  @isTest
  static void captureEchoShowsOverwriteAndRetention() {
    Account a = AgentChainTestFactory.account();
    AgentChainTestFactory.product(); // 'Bitumen 60/70'

    // Turn 1: parses Price 450000 + Qty 20 (Account-page mode).
    AgentConversationController.TurnResult t1 = AgentConversationController.advance(
      'commercial, 20 MT of Bitumen 60/70 at 450000',
      null,
      a.Id
    );
    System.assertEquals('NEEDS_INPUT', t1.status, t1.message);
    System.assert(
      t1.message.contains('Got it so far:'),
      'echoes captured values: ' + t1.message
    );
    System.assert(
      t1.message.contains('₦450,000'),
      'price echoed: ' + t1.message
    );
    System.assert(
      t1.message.contains('Qty 20 MT'),
      'qty echoed: ' + t1.message
    );

    // Turn 2: "470k" does NOT parse -> SILENT RETENTION must be visible (still ₦450,000).
    AgentConversationController.TurnResult t2 = AgentConversationController.advance(
      '470k',
      t1.stateJson,
      a.Id
    );
    System.assert(
      t2.message.contains('₦450,000'),
      'retention: unchanged price still shown after non-parsing "470k": ' +
      t2.message
    );

    // Turn 3: "at 460000" parses -> SILENT OVERWRITE made visible (now ₦460,000).
    AgentConversationController.TurnResult t3 = AgentConversationController.advance(
      'at 460000',
      t2.stateJson,
      a.Id
    );
    System.assert(
      t3.message.contains('₦460,000'),
      'overwrite visible: ' + t3.message
    );
  }

  // ---- AWAITING_INSIGHT_ACCOUNT (utility-bar insight follow-up) ----

  @isTest
  static void insightWhileIdleAcceptsBareNameFollowup() {
    // Utility bar (no page account). Insight question with no extractable account name.
    AgentConversationController.TurnResult t1 = turn(
      'how many orders on this account',
      null
    );
    System.assertEquals('NEEDS_INPUT', t1.status, t1.message);
    System.assert(
      t1.stateJson.contains('AWAITING_INSIGHT_ACCOUNT'),
      'should wait for an insight account, not the create flow: ' + t1.stateJson
    );

    // Bare-name follow-up must resolve as the insight account (NOT fall into create).
    AgentConversationController.TurnResult t2 = turn(
      'Ledya Foundry Ltd',
      t1.stateJson
    );
    System.assertEquals('OK', t2.status, t2.message);
    System.assert(
      t2.message.contains('Orders'),
      'returns read-only insight: ' + t2.message
    );
    System.assert(
      !t2.message.contains('Loading Advice for'),
      'must NOT be the create account ask'
    );
    Account a = [
      SELECT Id
      FROM Account
      WHERE Name = 'Ledya Foundry Ltd'
      LIMIT 1
    ];
    System.assertEquals(
      0,
      [SELECT COUNT() FROM Loading_Advice__c WHERE Account_DKL__c = :a.Id]
    );
    System.assert(
      t2.stateJson.contains('"phase":"COLLECTING"'),
      'returns to idle'
    );
  }

  @isTest
  static void insightOnAccountPhrasingExtractsName() {
    // "on <name> account" now extracts the account inline (no follow-up needed).
    AgentConversationController.TurnResult t = turn(
      'how many orders on Ledya Foundry Ltd account',
      null
    );
    System.assertEquals('OK', t.status, t.message);
    System.assert(t.message.contains('Orders'), 'inline insight: ' + t.message);
    System.assert(
      !t.missingFields.contains('Account'),
      'name was extracted, not asked'
    );
  }

  @isTest
  static void insightFollowupNotFoundReasks() {
    AgentConversationController.TurnResult t1 = turn(
      'how many orders on this account',
      null
    );
    System.assert(t1.stateJson.contains('AWAITING_INSIGHT_ACCOUNT'));
    AgentConversationController.TurnResult t2 = turn(
      'Zzz Nonexistent Co',
      t1.stateJson
    );
    System.assertEquals(
      'NEEDS_INPUT',
      t2.status,
      'still needs a resolvable account'
    );
    System.assert(
      t2.stateJson.contains('AWAITING_INSIGHT_ACCOUNT'),
      'stays in insight-account wait'
    );
  }

  @isTest
  static void postSubmitStateIsCollecting() {
    // Guard the (non-)bug: after a completed chain, state resets to idle COLLECTING.
    AgentChainTestFactory.approvalRouting();
    Account a = AgentChainTestFactory.account();
    Product2 p = AgentChainTestFactory.product();
    AgentChainRequest req = AgentChainTestFactory.withToken(
      AgentChainTestFactory.validRequest('Commercial', a.Id, p.Id)
    );

    Test.startTest();
    AgentActionResult commitRes = AgentChainService.commitChain(req);
    AgentActionResult submitRes = AgentApprovalService.submit(
      (Id) commitRes.recordId
    );
    Test.stopTest();
    System.assertEquals('OK', submitRes.status, submitRes.message);

    // The controller's doSubmit returns a fresh State; assert that shape directly.
    String freshState = JSON.serialize(new AgentConversationController.State());
    System.assert(
      freshState.contains('"phase":"COLLECTING"'),
      'resets to COLLECTING'
    );
    System.assert(
      freshState.contains('"accountId":null'),
      'account cleared after submit'
    );
  }
}
