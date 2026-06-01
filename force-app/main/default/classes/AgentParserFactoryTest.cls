@isTest
private class AgentParserFactoryTest {

    @isTest
    static void returnsRuleBasedByDefault() {
        AgentPromptParser p = AgentParserFactory.getParser();
        System.assert(p instanceof RuleBasedPromptParser, 'default parser is rule-based');
    }

    @isTest
    static void unknownConfiguredClassFallsBackToRuleBased() {
        AgentParserFactory.parserClassOverride = 'NoSuchParserClass_xyz';
        AgentPromptParser p = AgentParserFactory.getParser();
        System.assert(p instanceof RuleBasedPromptParser, 'falls back when class is missing');
    }

    @isTest
    static void honoursConfiguredClass() {
        AgentParserFactory.parserClassOverride = 'RuleBasedPromptParser';
        AgentPromptParser p = AgentParserFactory.getParser();
        System.assert(p instanceof RuleBasedPromptParser);
    }
}
