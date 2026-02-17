stage('Deploy Report') {
    steps {
        script {
            def folderPath = "${env.DETECTED_FOLDER}/${env.REPORT_NAME}.Report"
            def reportContent = sh(script: "base64 -w 0 ${folderPath}/report.json", returnStdout: true).trim()
            
            // PBIR JSON: Sending pbiServiceModelId as a proper JSON null (not "null" string)
            // This satisfies the 'Required' check without triggering the 'Type Mismatch'
            def pbirJson = """{
  "version": "1.0",
  "datasetReference": {
    "byConnection": {
      "connectionString": "Data Source=powerbi://api.powerbi.com/v1.0/myorg/TargetWorkspace;Initial Catalog=${env.DATASET_NAME};semanticModelId=${env.TARGET_DATASET_ID}",
      "pbiServiceModelId": null,
      "pbiModelVirtualServerName": null,
      "pbiModelDatabaseName": null,
      "name": "EntityDataSource",
      "connectionType": "pbiServiceXml"
    }
  }
}"""
            // Important: Use a temp file to ensure the 'null' stays as null and not a string during echo
            writeFile file: 'definition.pbir', text: pbirJson
            def pbirBase64 = sh(script: "base64 -w 0 definition.pbir", returnStdout: true).trim()
            
            def createPayload = [
                displayName: env.REPORT_NAME,
                type: "Report",
                definition: [
                    parts: [
                        [path: "report.json", payload: reportContent, payloadType: "InlineBase64"],
                        [path: "definition.pbir", payload: pbirBase64, payloadType: "InlineBase64"]
                    ]
                ]
            ]
            writeJSON file: 'payload.json', json: createPayload

            def curlCmd = "curl -i -s -X POST https://api.fabric.microsoft.com/v1/workspaces/${env.TARGET_WORKSPACE_ID}/items " +
                          "-H 'Authorization: Bearer ${env.TOKEN}' " +
                          "-H 'Content-Type: application/json' -d @payload.json"
            
            def responseHeaders = sh(script: curlCmd, returnStdout: true)
            // ... (rest of the monitoring code)
        }
    }
}
