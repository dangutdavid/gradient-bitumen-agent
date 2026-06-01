/**
 * v1 keyword-based intent classifier. Read-only questions classify as ACCOUNT_INSIGHT or
 * OBJECT_INFO; everything else is CREATE (the default — so an unrecognised message still
 * flows into the guided create loop). Deliberately conservative: a create prompt like
 * "commercial loading advice for X — 30 MT…" must NOT be read as a question.
 */
public with sharing class RuleBasedIntentClassifier implements AgentIntentClassifier {
  public String classify(String text) {
    if (String.isBlank(text)) {
      return AgentIntentRouter.INTENT_CREATE;
    }
    String t = text.toLowerCase();

    // --- Object / required-field questions ---
    if (
      t.contains('what does') ||
      t.contains('required field') ||
      t.contains('what fields') ||
      t.contains('what do i need') ||
      t.startsWith('describe') ||
      t.contains(' describe ')
    ) {
      return AgentIntentRouter.INTENT_OBJECT_INFO;
    }
    // "what does a loading advice need" style, but not a create instruction
    if (
      t.contains('need') &&
      t.contains('loading advice') &&
      !t.contains('create') &&
      !t.contains('commercial') &&
      !t.contains('stock transfer')
    ) {
      return AgentIntentRouter.INTENT_OBJECT_INFO;
    }

    // --- Read-only record questions (account insight) ---
    Boolean readVerb =
      t.startsWith('list') ||
      t.startsWith('show') ||
      t.contains('show me') ||
      t.contains('how many') ||
      t.contains('what are') ||
      t.contains('summary') ||
      t.contains('insight');
    Boolean recordNoun =
      t.contains('order') ||
      t.contains('opp') ||
      t.contains('loading advice') ||
      t.contains('insight') ||
      t.contains('summary');
    if (readVerb && recordNoun) {
      return AgentIntentRouter.INTENT_ACCOUNT_INSIGHT;
    }

    return AgentIntentRouter.INTENT_CREATE;
  }
}
