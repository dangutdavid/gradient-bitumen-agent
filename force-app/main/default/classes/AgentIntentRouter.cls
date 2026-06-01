/**
 * Routes a user message to an intent BEFORE the create parser sees it, so read-only questions
 * ("list orders for X", "what does a loading advice need") are never hijacked by the create
 * parser's "for <name>" extractor. The active classifier is chosen via
 * Agent_Setting__mdt.Default.Active_Intent_Classifier (defaults to RuleBasedIntentClassifier),
 * so an LLM classifier can be swapped in with no code change — same seam as the parser.
 */
public with sharing class AgentIntentRouter {
  public static final String INTENT_CREATE = 'CREATE';
  public static final String INTENT_ACCOUNT_INSIGHT = 'ACCOUNT_INSIGHT';
  public static final String INTENT_OBJECT_INFO = 'OBJECT_INFO';

  @TestVisible
  private static String classifierOverride;

  public static String classify(String text) {
    return getClassifier().classify(text);
  }

  private static AgentIntentClassifier getClassifier() {
    String className = 'RuleBasedIntentClassifier';
    if (classifierOverride != null) {
      className = classifierOverride;
    } else {
      Agent_Setting__mdt setting = Agent_Setting__mdt.getInstance('Default');
      if (
        setting != null &&
        String.isNotBlank(setting.Active_Intent_Classifier__c)
      ) {
        className = setting.Active_Intent_Classifier__c;
      }
    }
    Type t = Type.forName(className);
    if (t == null) {
      t = RuleBasedIntentClassifier.class;
    }
    return (AgentIntentClassifier) t.newInstance();
  }
}
