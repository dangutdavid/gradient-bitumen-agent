@isTest
private class LoadingAdvicePDFExtensionTest {
  // VF StandardController extension — exercised via a StandardController, no page render needed.

  @isTest
  static void loadsHeaderLinesAndRecordType() {
    Account a = AgentChainTestFactory.account();
    Product2 p = AgentChainTestFactory.product(); // Family 'Bitumen 60/70'
    Loading_Advice__c la = AgentChainTestFactory.loadingAdvice(
      a.Id,
      p.Id,
      true
    );

    Test.startTest();
    ApexPages.StandardController sc = new ApexPages.StandardController(la);
    LoadingAdvicePDFExtension ext = new LoadingAdvicePDFExtension(sc);
    Test.stopTest();

    System.assertEquals(la.Id, ext.loadingAdvice.Id, 'header loaded');
    System.assertEquals(1, ext.lines.size(), 'line loaded');
    System.assertEquals(
      'Commercial_DKL',
      ext.recordTypeName,
      'record type developer name'
    );
    System.assertEquals(
      'Bitumen 60/70',
      ext.productFamily,
      'product family from the first line'
    );
  }

  @isTest
  static void noLinesGivesNaProductFamily() {
    Account a = AgentChainTestFactory.account();
    Product2 p = AgentChainTestFactory.product();
    Loading_Advice__c la = AgentChainTestFactory.loadingAdvice(
      a.Id,
      p.Id,
      false
    ); // no lines

    Test.startTest();
    LoadingAdvicePDFExtension ext = new LoadingAdvicePDFExtension(
      new ApexPages.StandardController(la)
    );
    Test.stopTest();

    System.assert(ext.lines.isEmpty(), 'no lines');
    System.assertEquals(
      'N/A',
      ext.productFamily,
      'falls back to N/A when no line'
    );
  }
}
