pipeline {
    agent any

    environment {
        CLIENT_ID     = credentials('fabric-client-id')
        CLIENT_SECRET = credentials('fabric-client-secret')
        TENANT_ID     = credentials('fabric-tenant-id')
        
        WORKSPACE_ID  = "afc6fad2-d19f-4f1b-bc5a-eb5f2caf40e6"
        MODEL_NAME    = "Sales_Model_A"
        REPORT_NAME   = "Sales_Report_A"
        
        MODEL_FOLDER  = "Customer-A/Sales_Model_A.SemanticModel"
        REPORT_FOLDER = "Customer-A/Sales_Report_A.Report"
    }

    stages {
        stage('Checkout & Auth') {
            steps {
                script {
                    git branch: 'dev', credentialsId: 'github-creds', url: 'https://github.com/Prathmesh2806/Fabric-Automation.git'
                    
                    def tokenResponse = sh(script: """
                        curl -s -X POST https://login.microsoftonline.com/${TENANT_ID}/oauth2/v2.0/token \
                        -d grant_type=client_credentials \
                        -d client_id=${CLIENT_ID} \
                        -d client_secret=${CLIENT_SECRET} \
                        -d scope=https://api.fabric.microsoft.com/.default
                    """, returnStdout: true)
                    env.TOKEN = readJSON(text: tokenResponse).access_token
                }
            }
        }

        stage('Deploy Semantic Model') {
            steps {
                script {
                    def itemsResp = sh(script: "curl -s -H 'Authorization: Bearer ${env.TOKEN}' https://api.fabric.microsoft.com/v1/workspaces/${env.WORKSPACE_ID}/items", returnStdout: true)
                    def existingModel = readJSON(text: itemsResp).value.find { it.displayName == env.MODEL_NAME && it.type == "SemanticModel" }

                    def pbismBase64 = sh(script: "base64 -w 0 ${env.MODEL_FOLDER}/definition.pbism", returnStdout: true).trim()
                    
                    def parts = []
                    parts << [
                        path: "definition.pbism", 
                        payload: pbismBase64, 
                        payloadType: "InlineBase64"
                    ]
                    
                    def tmdlFiles = sh(script: "find ${env.MODEL_FOLDER}/definition -name '*.tmdl'", returnStdout: true).split()
                    tmdlFiles.each { filePath ->
                        def relativePath = filePath.substring(filePath.indexOf("definition/"))
                        def fileBase64 = sh(script: "base64 -w 0 ${filePath}", returnStdout: true).trim()
                        parts << [
                            path: relativePath, 
                            payload: fileBase64, 
                            payloadType: "InlineBase64"
                        ]
                    }

                    def modelPayload = [
                        displayName: env.MODEL_NAME,
                        type: "SemanticModel",
                        definition: [ parts: parts ]
                    ]
                    writeJSON file: 'model_payload.json', json: modelPayload

                    def apiUrl = existingModel ? 
                        "https://api.fabric.microsoft.com/v1/workspaces/${env.WORKSPACE_ID}/items/${existingModel.id}/updateDefinition" : 
                        "https://api.fabric.microsoft.com/v1/workspaces/${env.WORKSPACE_ID}/items"
                    
                    fabricPoll(apiUrl, 'model_payload.json')
                }
            }
        }

        stage('Deploy Report') {
            steps {
                script {
                    def itemsResp = sh(script: "curl -s -H 'Authorization: Bearer ${env.TOKEN}' https://api.fabric.microsoft.com/v1/workspaces/${env.WORKSPACE_ID}/items", returnStdout: true)
                    def itemsJson = readJSON text: itemsResp
                    def modelId = itemsJson.value.find { it.displayName == env.MODEL_NAME }?.id
                    def existingReport = itemsJson.value.find { it.displayName == env.REPORT_NAME }

                    // PBIR Definition
                    def pbirJson = """{
                        "version": "1.0",
                        "datasetReference": {
                            "byConnection": {
                                "connectionString": null,
                                "pbiServiceModelId": null,
                                "pbiModelVirtualServerName": null,
                                "pbiModelDatabaseName": "${modelId}",
                                "name": "EntityDataSource",
                                "connectionType": "pbiServiceXml"
                            }
                        }
                    }"""
                    writeFile file: 'definition.pbir', text: pbirJson
                    
                    // Encode files separately to avoid line-break issues in the Map definition
                    def reportBase64 = sh(script: "base64 -w 0 ${env.REPORT_FOLDER}/report.json", returnStdout: true).trim()
                    def pbirBase64 = sh(script: "base64 -w 0 definition.pbir", returnStdout: true).trim()

                    def reportPayload = [
                        displayName: env.REPORT_NAME,
                        type: "Report",
                        definition: [
                            parts: [
                                [path: "report.json", payload: reportBase64, payloadType: "InlineBase64"],
                                [path: "definition.pbir", payload: pbirBase64, payloadType: "InlineBase64"]
                            ]
                        ]
                    ]
                    writeJSON file: 'report_payload.json', json: reportPayload

                    def apiUrl = existingReport ? 
                        "https://api.fabric.microsoft.com/v1/workspaces/${env.WORKSPACE_ID}/items/${existingReport.id}/updateDefinition" : 
                        "https://api.fabric.microsoft.com/v1/workspaces/${env.WORKSPACE_ID}/items"
                    
                    fabricPoll(apiUrl, 'report_payload.json')
                }
            }
        }
    }
    
    post {
        always {
            sh "rm -f model_payload.json report_payload.json definition.pbir"
        }
    }
}

def fabricPoll(apiUrl, payloadFile) {
    def responseHeaders = sh(script: "curl -i -s -X POST ${apiUrl} -H 'Authorization: Bearer ${env.TOKEN}' -H 'Content-Type: application/json' -d @${payloadFile}", returnStdout: true)
    def opUrl = sh(script: "echo '${responseHeaders}' | grep -i 'location:' | awk '{print \$2}' | tr -d '\\r'", returnStdout: true).trim()

    if (opUrl && opUrl != "null") {
        while (true) {
            sleep 15
            def statusRaw = sh(script: "curl -s -H 'Authorization: Bearer ${env.TOKEN}' ${opUrl}", returnStdout: true)
            def statusJson = readJSON text: statusRaw
            if (statusJson.status == "Succeeded") {
                echo "✅ Success!"
                break
            } else if (statusJson.status == "Failed") {
                error "❌ Fabric API Error: ${statusRaw}"
            }
            echo "⏳ Polling Fabric API..."
        }
    } else {
        error "❌ API failed to start. Headers: ${responseHeaders}"
    }
}
