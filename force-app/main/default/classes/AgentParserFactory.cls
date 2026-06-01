/**
 * Returns the active AgentPromptParser, chosen by Agent_Setting__mdt.Default.Active_Parser.
 * Swap the metadata value to an LLM parser class later — no code change needed here.
 */
public with sharing class AgentParserFactory {

    @TestVisible
    private static String parserClassOverride;

    public static AgentPromptParser getParser() {
        String className = 'RuleBasedPromptParser';
        if (parserClassOverride != null) {
            className = parserClassOverride;
        } else {
            Agent_Setting__mdt setting = Agent_Setting__mdt.getInstance('Default');
            if (setting != null && String.isNotBlank(setting.Active_Parser__c)) {
                className = setting.Active_Parser__c;
            }
        }
        Type t = Type.forName(className);
        if (t == null) {
            t = RuleBasedPromptParser.class; // safe fallback if the configured class is missing
        }
        return (AgentPromptParser) t.newInstance();
    }
}
