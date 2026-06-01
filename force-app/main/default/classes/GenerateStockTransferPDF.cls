public class GenerateStockTransferPDF {
    
    @InvocableMethod(label='Generate Stock Transfer PDF' description='Generates the Stock Transfer Dispatch PDF and saves it to the record.')
    public static List<String> generatePDF(List<Id> loadingAdviceIds) {
        
        List<String> documentIds = new List<String>();
        if (loadingAdviceIds.isEmpty()) return documentIds;
        
        List<ContentVersion> cvListToInsert = new List<ContentVersion>();
        
        // 1. Get the Loading Advice Numbers
        Map<Id, Loading_Advice__c> laMap = new Map<Id, Loading_Advice__c>(
            [SELECT Id, Name FROM Loading_Advice__c WHERE Id IN :loadingAdviceIds]
        );
        
        // 2. Get the Product Names from the Line Items
        List<Loading_Advice_Line__c> lines = [
            SELECT LoadingAdvice_DKL__c, Product_DKL__r.Name 
            FROM Loading_Advice_Line__c 
            WHERE LoadingAdvice_DKL__c IN :loadingAdviceIds
        ];
        
        // 3. Match the Product Name to the correct Loading Advice ID
        Map<Id, String> productMap = new Map<Id, String>();
        for(Loading_Advice_Line__c line : lines) {
            if(!productMap.containsKey(line.LoadingAdvice_DKL__c) && line.Product_DKL__r != null) {
                // Keep the standard product name for the Title
                String originalProdName = line.Product_DKL__r.Name;
                productMap.put(line.LoadingAdvice_DKL__c, originalProdName);
            }
        }
        
        // Get today's date in the format requested (e.g., 30.04.2026)
        String dateStr = Datetime.now().format('dd.MM.yyyy');
        
        for (Id recordId : loadingAdviceIds) {
            PageReference pdfPage = Page.StockTransferDispatchPDF; 
            pdfPage.getParameters().put('id', recordId);
            
            Blob pdfBlob;
            if (Test.isRunningTest()) {
                pdfBlob = Blob.valueOf('Test PDF Data');
            } else {
                pdfBlob = pdfPage.getContentAsPDF();
            }
            
            // 4. Construct the Dynamic File Name
            String laNumber = laMap.containsKey(recordId) ? laMap.get(recordId).Name : 'LA';
            String prodName = productMap.containsKey(recordId) ? productMap.get(recordId) : 'Unknown_Product';
            
            // NEW FORMAT: [Product Name] Stock Transfer Dispatch - [Number] - [Date]
            String displayTitle = prodName + ' Stock Transfer Dispatch - ' + laNumber + ' - ' + dateStr;
            
            // Clean file name for actual download
            String safeProdName = prodName.replaceAll('[^a-zA-Z0-9\\s]', '_').replaceAll('\\s+', '_');
            String safeDateStr = dateStr.replaceAll('\\.', '_');
            String downloadName = safeProdName + '_Stock_Transfer_Dispatch_' + laNumber + '_' + safeDateStr + '.pdf';
            
            ContentVersion cv = new ContentVersion();
            
            cv.Title = displayTitle;
            cv.PathOnClient = downloadName;
            cv.VersionData = pdfBlob;
            cv.IsMajorVersion = true;
            
            // This automatically attaches it to the record AND makes the test class pass!
            cv.FirstPublishLocationId = recordId; 
            
            cvListToInsert.add(cv);
        }
        
        if (!cvListToInsert.isEmpty()) {
            insert cvListToInsert;
            
            // FIXED: We are now actually adding the ID to the list before returning it!
            for (ContentVersion cv : cvListToInsert) {
                documentIds.add(cv.Id); 
            }
        }
        
        return documentIds;
    }
}