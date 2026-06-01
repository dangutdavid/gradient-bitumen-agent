/**
 * Pluggable natural-language parser seam. v1 is RuleBasedPromptParser; a future
 * LLMPromptParser can be swapped in via Agent_Setting__mdt.Active_Parser with no other change.
 */
public interface AgentPromptParser {
    AgentParseResult parse(String text, AgentContext ctx);
}
