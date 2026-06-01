@isTest
private class RuleBasedPromptParserTest {

    private static AgentParseResult parse(String text, Id accountId) {
        return new RuleBasedPromptParser().parse(text, new AgentContext(accountId));
    }

    @isTest
    static void extractsQuantityPriceAndLoadType() {
        AgentChainTestFactory.product(); // 'Bitumen 60/70'
        AgentParseResult r = parse('Create a commercial loading advice — 30 MT of bitumen at NGN 450,000/MT, deliver to Kano', null);

        System.assertEquals('Commercial', r.typeOfLoad);
        System.assertEquals(30, (Decimal) r.fieldMap.get('QuantityMT_DKL__c'));
        System.assertEquals(450000, (Decimal) r.fieldMap.get('PricePerMT_DKL__c'));
        System.assertEquals('Kano', (String) r.fieldMap.get('Location_DKL__c'));
        System.assertEquals('Bitumen 60/70', [SELECT Name FROM Product2 WHERE Id = :(Id) r.fieldMap.get('Product_DKL__c')].Name);
    }

    @isTest
    static void stockTransferKeyword() {
        AgentParseResult r = parse('stock transfer of 12 tonnes', null);
        System.assertEquals('Stock Transfer', r.typeOfLoad);
        System.assertEquals(12, (Decimal) r.fieldMap.get('QuantityMT_DKL__c'));
    }

    @isTest
    static void customerFromPageContextAndCustomerType() {
        Account a = AgentChainTestFactory.account();
        AgentParseResult r = parse('customer type credit, deliver to Lagos', a.Id);
        System.assertEquals(a.Id, (Id) r.fieldMap.get('Customer_DKL__c'), 'customer from page ctx');
        System.assertEquals('Credit', (String) r.fieldMap.get('CustomerType_DKL__c'));
    }

    @isTest
    static void parsesDates() {
        AgentParseResult r = parse('close 30/06/2026, order starts today', null);
        System.assertEquals(Date.newInstance(2026, 6, 30), (Date) r.fieldMap.get('CloseDate'));
        System.assertEquals(Date.today(), (Date) r.fieldMap.get('EffectiveDate'));
    }

    @isTest
    static void accountHintWhenNoPageContext() {
        AgentParseResult r = parse('Create a commercial LA for Ledya Foundry Ltd — 10 MT', null);
        System.assertEquals('Ledya Foundry Ltd', r.accountHint);
    }

    @isTest
    static void ambiguousProductLeftUnresolved() {
        insert new List<Product2>{
            new Product2(Name = 'Bitumen 60/70', IsActive = true),
            new Product2(Name = 'Bitumen + PolyGRA', IsActive = true)
        };
        AgentParseResult r = parse('20 MT of bitumen', null);
        System.assert(!r.fieldMap.containsKey('Product_DKL__c'), 'must not guess between products');
        System.assert(!r.unresolved.isEmpty(), 'ambiguity noted for the ask-loop');
    }

    @isTest
    static void noArgContextWorks() {
        AgentParseResult r = new RuleBasedPromptParser().parse('commercial 5 MT', new AgentContext());
        System.assertEquals('Commercial', r.typeOfLoad);
        System.assertEquals(5, (Decimal) r.fieldMap.get('QuantityMT_DKL__c'));
    }

    @isTest
    static void blankTextIsEmptyResult() {
        AgentParseResult r = parse('   ', null);
        System.assert(r.fieldMap.isEmpty());
        System.assertEquals(null, r.typeOfLoad);
    }
}
