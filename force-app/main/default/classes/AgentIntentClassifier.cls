/**
 * Pluggable intent classification seam (same pattern as AgentPromptParser).
 * Returns one of AgentIntentRouter's INTENT_* constants. v1 is RuleBasedIntentClassifier;
 * an LLM classifier can be swapped in via Agent_Setting__mdt.Active_Intent_Classifier.
 */
public interface AgentIntentClassifier {
  String classify(String text);
}
