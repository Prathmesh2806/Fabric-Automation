pipeline {
    agent any

    environment {
        // Credentials IDs from Jenkins Global Credentials
        CLIENT_ID        = credentials('fabric-client-id')
        CLIENT_SECRET    = credentials('fabric-client-secret')
        TENANT_ID        = credentials('fabric-tenant-id')
        
        // Configuration
        WORKSPACE_ID     = "afc6fad2-d19f-4f1b-bc5a-eb5f2caf40e6"
        MODEL_NAME       = "Sales_Model_A"
        REPORT_NAME      = "Sales_Report_A"
        
        // Target QA IDs (The IDs for your QA Lakehouse/Workspace)
        QA_LAKEHOUSE_ID  = "34963548-ee7e-42aa-a705-e36d06461251"
        QA_CONNECTION_ID = "58d9731f-fa5f-419a-8619-1e987b11a916"
        
        // Folders
        MODEL_FOLDER     = "Customer-A/Sales_Model_A.SemanticModel"
        REPORT_FOLDER    = "Customer-A/Sales_Report_A.Report"
    }

    stages {
        stage('Auth & Capacity Check') {
            steps {
                script {
                    def tokenResponse = sh(script: """
                        curl -s -X POST https://login.microsoftonline.com/${TENANT_ID}/oauth2/v2.0/token \
                        -d grant_type=client_credentials \
                        -d client_id=${CLIENT_ID} \
                        -d client_secret=${CLIENT_SECRET} \
                        -d scope=https://api.fabric.microsoft.com/.default
                    """, returnStdout: true)
                    env.TOKEN = readJSON(text: tokenResponse).access_token

                    echo "🔍 Verifying Capacity Status..."
                    def capCheck = sh(script: "curl -s -H 'Authorization: Bearer ${env.TOKEN}' https://api.powerbi.com/v1.0/myorg/capacities", returnStdout: true)
                    if (capCheck.contains("Paused") || capCheck.contains("Inactive")) {
                        error "❌ Capacity is PAUSED. Please resume it in the Azure Portal."
                    }
                    echo "✅ Capacity is Active."
                }
            }
        }

        stage('Deploy Semantic Model') {
            steps {
                script {
                    echo "🛠️ Patching TMDL for QA Environment..."
                    // Use a different delimiter (|) for sed to avoid escaping slashes in the URL
                    // We also ensure we only replace the IDs inside the existing quotes
                    sh """
                        # 1. Replace the Workspace ID and Lakehouse ID in the Onelake URL
                        # This regex looks for the specific URL pattern and swaps the IDs
                        sed -i 's|onelake.dfs.fabric.microsoft.com/[a-f0-9-]*/[a-f0-9-]*|onelake.dfs.fabric.microsoft.com/${env.WORKSPACE_ID}/${env.QA_LAKEHOUSE_ID}|g' "${env.MODEL_FOLDER}/definition/expressions.tmdl"
                        
                        # 2. Update Environment Parameter
                        sed -i 's/expression EnvironmentName = ".*"/expression EnvironmentName = "QA"/' "${env.MODEL_FOLDER}/definition/expressions.tmdl"
                    """

                    // 2. Build Payload
                    def itemsResp = sh(script: "curl -s -H 'Authorization: Bearer ${env.TOKEN}' https://api.fabric.microsoft.com/v1/workspaces/${env.WORKSPACE_ID}/items", returnStdout: true)
                    def existingModel = readJSON(text: itemsResp).value.find { it.displayName == env.MODEL_NAME && it.type == "SemanticModel" }

                    def pbismBase64 = sh(script: "base64 -w 0 ${env.MODEL_FOLDER}/definition.pbism", returnStdout: true).trim()
                    def parts = [[path: "definition.pbism", payload: pbismBase64, payloadType: "InlineBase64"]]
                    
                    def tmdlFiles = sh(script: "find ${env.MODEL_FOLDER}/definition -name '*.tmdl'", returnStdout: true).split()
                    tmdlFiles.each { filePath ->
                        def relativePath = filePath.substring(filePath.indexOf("definition/"))
                        def fileBase64 = sh(script: "base64 -w 0 ${filePath}", returnStdout: true).trim()
                        parts << [path: relativePath, payload: fileBase64, payloadType: "InlineBase64"]
                    }

                    def modelPayload = [displayName: env.MODEL_NAME, type: "SemanticModel", definition: [ parts: parts ]]
                    writeJSON file: 'model_payload.json', json: modelPayload

                    def apiUrl = existingModel ? 
                        "https://api.fabric.microsoft.com/v1/workspaces/${env.WORKSPACE_ID}/items/${existingModel.id}/updateDefinition" : 
                        "https://api.fabric.microsoft.com/v1/workspaces/${env.WORKSPACE_ID}/items"
                    
                    fabricPoll(apiUrl, 'model_payload.json')
                }
            }
        }

        stage('Ownership & Connection Binding') {
            steps {
                script {
                    def itemsResp = sh(script: "curl -s -H 'Authorization: Bearer ${env.TOKEN}' https://api.fabric.microsoft.com/v1/workspaces/${env.WORKSPACE_ID}/items", returnStdout: true)
                    def modelId = readJSON(text: itemsResp).value.find { it.displayName == env.MODEL_NAME }?.id

                    echo "👑 Taking Ownership of Model: ${modelId}"
                    sh "curl -s -X POST 'https://api.powerbi.com/v1.0/myorg/groups/${env.WORKSPACE_ID}/datasets/${modelId}/Default.TakeOver' -H 'Authorization: Bearer ${env.TOKEN}' -H 'Content-Length: 0'"
                    
                    sleep 10 

                    echo "🔗 Binding to Cloud Connection ID: ${env.QA_CONNECTION_ID}"
                    def bindPayload = [
                        gatewayObjectId: "00000000-0000-0000-0000-000000000000",
                        datasourceObjectIds: ["${env.QA_CONNECTION_ID}"]
                    ]
                    writeJSON file: 'bind_payload.json', json: bindPayload
                    sh "curl -s -X POST 'https://api.powerbi.com/v1.0/myorg/groups/${env.WORKSPACE_ID}/datasets/${modelId}/Default.BindToGateway' -H 'Authorization: Bearer ${env.TOKEN}' -H 'Content-Type: application/json' -d @bind_payload.json"
                }
            }
        }

        stage('Refresh & Validate') {
            steps {
                script {
                    def itemsResp = sh(script: "curl -s -H 'Authorization: Bearer ${env.TOKEN}' https://api.fabric.microsoft.com/v1/workspaces/${env.WORKSPACE_ID}/items", returnStdout: true)
                    def modelId = readJSON(text: itemsResp).value.find { it.displayName == env.MODEL_NAME }?.id

                    echo "🔄 Triggering Refresh to lock in Connection..."
                    def refreshPayload = [ type: "Full", commitMode: "transactional" ]
                    writeJSON file: 'refresh_payload.json', json: refreshPayload

                    sh "curl -s -X POST 'https://api.powerbi.com/v1.0/myorg/groups/${env.WORKSPACE_ID}/datasets/${modelId}/refreshes' -H 'Authorization: Bearer ${env.TOKEN}' -H 'Content-Type: application/json' -d @refresh_payload.json"
                    
                    echo "✅ Refresh triggered. The UI will now display 'Cust-A-QA' as the active connection."
                }
            }
        }

        stage('Deploy Report') {
            steps {
                script {
                    def itemsResp = sh(script: "curl -s -H 'Authorization: Bearer ${env.TOKEN}' https://api.fabric.microsoft.com/v1/workspaces/${env.WORKSPACE_ID}/items", returnStdout: true)
                    def modelId = readJSON(text: itemsResp).value.find { it.displayName == env.MODEL_NAME }?.id
                    def existingReport = readJSON(text: itemsResp).value.find { it.displayName == env.REPORT_NAME }

                    def pbirJson = """{
                        "version": "1.0",
                        "datasetReference": {
                            "byConnection": {
                                "connectionString": null,
                                "pbiServiceModelId": null,
                                "pbiModelVirtualServerName": "sobe_wowvirtualserver",
                                "pbiModelDatabaseName": "${modelId}",
                                "name": "EntityDataSource",
                                "connectionType": "pbiServiceXml"
                            }
                        }
                    }"""
                    writeFile file: 'definition.pbir', text: pbirJson
                    
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
            sh "rm -f model_payload.json report_payload.json definition.pbir bind_payload.json refresh_payload.json"
        }
    }
}

def fabricPoll(apiUrl, payloadFile) {
    def responseHeaders = sh(script: "curl -i -s -X POST ${apiUrl} -H 'Authorization: Bearer ${env.TOKEN}' -H 'Content-Type: application/json' -d @${payloadFile}", returnStdout: true)
    def opUrl = sh(script: "echo '${responseHeaders}' | grep -i 'location:' | awk '{print \$2}' | tr -d '\\r'", returnStdout: true).trim()

    if (opUrl && opUrl != "null") {
        echo "📡 Polling Operation: ${opUrl}"
        int retryCount = 0
        while (retryCount < 20) {
            sleep 20
            def statusRaw = sh(script: "curl -s -H 'Authorization: Bearer ${env.TOKEN}' ${opUrl}", returnStdout: true)
            def statusJson = readJSON text: statusRaw
            if (statusJson.status == "Succeeded") {
                echo "✅ Operation Success!"
                return 
            } else if (statusJson.status == "Failed") {
                error "❌ Fabric API Failure: ${statusRaw}"
            }
            retryCount++
        }
        error "❌ Operation timed out."
    } else {
        error "❌ Failed to initiate operation. No Location header found."
    }
}
