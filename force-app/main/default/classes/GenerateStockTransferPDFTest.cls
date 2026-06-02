@isTest
private class GenerateStockTransferPDFTest {
  // Uses the dummy-PDF path (Test.isRunningTest) baked into the generator.

  @isTest
  static void generatesStockTransferPdf() {
    Account a = AgentChainTestFactory.account();
    Product2 p = AgentChainTestFactory.product();
    Loading_Advice__c la = AgentChainTestFactory.loadingAdvice(
      a.Id,
      p.Id,
      true
    );

    Test.startTest();
    List<String> docIds = GenerateStockTransferPDF.generatePDF(
      new List<Id>{ la.Id }
    );
    Test.stopTest();

    System.assertEquals(1, docIds.size(), 'one ContentVersion returned');
    ContentVersion cv = [
      SELECT Title
      FROM ContentVersion
      WHERE Id = :(Id) docIds[0]
    ];
    System.assert(cv.Title.contains('Stock Transfer Dispatch'), cv.Title);
    System.assert(cv.Title.contains('Bitumen 60/70'), cv.Title);
    System.assertEquals(
      1,
      [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :la.Id]
    );
  }

  @isTest
  static void noLinesFallsBackToUnknownProduct() {
    Account a = AgentChainTestFactory.account();
    Product2 p = AgentChainTestFactory.product();
    Loading_Advice__c la = AgentChainTestFactory.loadingAdvice(
      a.Id,
      p.Id,
      false
    );

    Test.startTest();
    List<String> docIds = GenerateStockTransferPDF.generatePDF(
      new List<Id>{ la.Id }
    );
    Test.stopTest();

    ContentVersion cv = [
      SELECT Title
      FROM ContentVersion
      WHERE Id = :(Id) docIds[0]
    ];
    System.assert(cv.Title.contains('Unknown_Product'), cv.Title);
  }

  @isTest
  static void emptyInputReturnsEmpty() {
    Test.startTest();
    List<String> docIds = GenerateStockTransferPDF.generatePDF(new List<Id>());
    Test.stopTest();
    System.assertEquals(0, docIds.size(), 'empty input short-circuits');
  }
}
