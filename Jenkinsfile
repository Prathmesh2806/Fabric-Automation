pipeline {
    agent any

    environment {
        // Credentials IDs from your Jenkins
        CLIENT_ID     = credentials('fabric-client-id')
        CLIENT_SECRET = credentials('fabric-client-secret')
        TENANT_ID     = credentials('fabric-tenant-id')
        
        WORKSPACE_ID  = "afc6fad2-d19f-4f1b-bc5a-eb5f2caf40e6"
        MODEL_NAME    = "Sales_Model_A"
        REPORT_NAME   = "Sales_Report_A"
        // Based on your screenshot:
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
                    // 1. Check if model exists to decide Create vs Update
                    def itemsResp = sh(script: "curl -s -H 'Authorization: Bearer ${env.TOKEN}' https://api.fabric.microsoft.com/v1/workspaces/${env.WORKSPACE_ID}/items", returnStdout: true)
                    def existingModel = readJSON(text: itemsResp).value.find { it.displayName == env.MODEL_NAME && it.type == "SemanticModel" }

                    // 2. Build the "Parts" list for TMDL structure
                    def parts = []
                    
                    // Add core files
                    parts << [path: "definition.pbism", payload: sh(script: "base64 -w 0 ${env.MODEL_FOLDER}/definition.pbism", returnStdout: true).trim(), payloadType: "InlineBase64"]
                    parts << [path: "definition/model.tmdl", payload: sh(script: "base64 -w 0 ${env.MODEL_FOLDER}/definition/model.tmdl", returnStdout: true).trim(), payloadType: "InlineBase64"]
                    
                    // Automatically add all table TMDL files
                    def tableFiles = sh(script: "ls ${env.MODEL_FOLDER}/definition/tables/*.tmdl", returnStdout: true).split()
                    tableFiles.each { filePath ->
                        def fileName = filePath.split('/').last()
                        parts << [path: "definition/tables/${fileName}", payload: sh(script: "base64 -w 0 ${filePath}", returnStdout: true).trim(), payloadType: "InlineBase64"]
                    }

                    def modelPayload = [
                        displayName: env.MODEL_NAME,
                        type: "SemanticModel",
                        definition: [ parts: parts ]
                    ]
                    writeJSON file: 'model_payload.json', json: modelPayload

                    // 3. API Call
                    def apiUrl = existingModel ? 
                        "https://api.fabric.microsoft.com/v1/workspaces/${env.WORKSPACE_ID}/items/${existingModel.id}/updateDefinition" : 
                        "https://api.fabric.microsoft.com/v1/workspaces/${env.WORKSPACE_ID}/items"
                    
                    echo "🚀 Deploying Semantic Model..."
                    fabricPoll(apiUrl, 'model_payload.json')
                }
            }
        }

        stage('Deploy Report') {
            steps {
                script {
                    // 1. Get Model ID (to ensure report links correctly)
                    def itemsResp = sh(script: "curl -s -H 'Authorization: Bearer ${env.TOKEN}' https://api.fabric.microsoft.com/v1/workspaces/${env.WORKSPACE_ID}/items", returnStdout: true)
                    def itemsJson = readJSON text: itemsResp
                    def modelId = itemsJson.value.find { it.displayName == env.MODEL_NAME }?.id
                    def existingReport = itemsJson.value.find { it.displayName == env.REPORT_NAME }

                    // 2. Prep definition.pbir (updates connection to model)
                    def pbirJson = """{
                        "version": "1.0",
                        "datasetReference": {
                            "byConnection": {
                                "pbiModelDatabaseName": "${modelId}",
                                "name": "EntityDataSource",
                                "connectionType": "pbiServiceXml"
                            }
                        }
                    }"""
                    writeFile file: 'definition.pbir', text: pbirJson
                    
                    def reportParts = [
                        [path: "report.json", payload: sh(script: "base64 -w 0 ${env.REPORT_FOLDER}/report.json", returnStdout: true).trim(), payloadType: "InlineBase64"],
                        [path: "definition.pbir", payload: sh(script: "base64 -w 0 definition.pbir", returnStdout: true).trim(), payloadType: "InlineBase64"]
                    ]

                    def reportPayload = [
                        displayName: env.REPORT_NAME,
                        type: "Report",
                        definition: [ parts: reportParts ]
                    ]
                    writeJSON file: 'report_payload.json', json: reportPayload

                    // 3. API Call
                    def apiUrl = existingReport ? 
                        "https://api.fabric.microsoft.com/v1/workspaces/${env.WORKSPACE_ID}/items/${existingReport.id}/updateDefinition" : 
                        "https://api.fabric.microsoft.com/v1/workspaces/${env.WORKSPACE_ID}/items"
                    
                    echo "🚀 Deploying Report..."
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

// Helper function for Long Running Operations (LRO)
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
            echo "⏳ Still working..."
        }
    } else {
        error "❌ API failed to start. Headers: ${responseHeaders}"
    }
}
