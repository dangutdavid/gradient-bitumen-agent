@isTest
private class LoadingAdvicePDFGeneratorTest {
  // Uses the dummy-PDF path (Test.isRunningTest) baked into the generator, so no VF render.

  @isTest
  static void generatesAndAttachesPdfWithProductTitle() {
    Account a = AgentChainTestFactory.account();
    Product2 p = AgentChainTestFactory.product(); // 'Bitumen 60/70'
    Loading_Advice__c la = AgentChainTestFactory.loadingAdvice(
      a.Id,
      p.Id,
      true
    );

    Test.startTest();
    List<Id> cvIds = LoadingAdvicePDFGenerator.generatePDFAndAttach(
      new List<Id>{ la.Id }
    );
    Test.stopTest();

    System.assertEquals(1, cvIds.size(), 'one ContentVersion returned');
    ContentVersion cv = [
      SELECT Title, PathOnClient
      FROM ContentVersion
      WHERE Id = :cvIds[0]
    ];
    System.assert(
      cv.Title.contains('Bitumen 60/70'),
      'title carries the product: ' + cv.Title
    );
    System.assert(cv.Title.contains('Loading Advice'), cv.Title);
    // attached to the LA
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
    ); // no line

    Test.startTest();
    List<Id> cvIds = LoadingAdvicePDFGenerator.generatePDFAndAttach(
      new List<Id>{ la.Id }
    );
    Test.stopTest();

    ContentVersion cv = [SELECT Title FROM ContentVersion WHERE Id = :cvIds[0]];
    System.assert(
      cv.Title.contains('Unknown_Product'),
      'no-line LA uses Unknown_Product: ' + cv.Title
    );
  }

  @isTest
  static void emptyInputReturnsEmpty() {
    Test.startTest();
    List<Id> cvIds = LoadingAdvicePDFGenerator.generatePDFAndAttach(
      new List<Id>()
    );
    Test.stopTest();
    System.assertEquals(0, cvIds.size());
  }
}
