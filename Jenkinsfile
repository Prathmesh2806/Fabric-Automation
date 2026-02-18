pipeline {
    agent any

    environment {
        CLIENT_ID        = credentials('fabric-client-id')
        CLIENT_SECRET    = credentials('fabric-client-secret')
        TENANT_ID        = credentials('fabric-tenant-id')
        
        WORKSPACE_ID     = "afc6fad2-d19f-4f1b-bc5a-eb5f2caf40e6"
        SEMANTIC_MODEL_ID = "5bd5e7ae-95ff-4251-8fd3-f6d14fa8439c"
        MODEL_NAME       = "Sales_Model_A"
        MODEL_FOLDER     = "Customer-A/Sales_Model_A.SemanticModel"
        QA_CONNECTION_ID = "58d9731f-fa5f-419a-8619-1e987b11a916"
    }

    stages {
        stage('Initial Setup') {
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

                    def itemsResp = sh(script: "curl -s -H 'Authorization: Bearer ${env.TOKEN}' https://api.fabric.microsoft.com/v1/workspaces/${env.WORKSPACE_ID}/items", returnStdout: true)
                    def targetLakehouse = readJSON(text: itemsResp).value.find { it.type == "Lakehouse" }
                    if (!targetLakehouse) error "❌ No Lakehouse found!"
                    env.LAKEHOUSE_ID = targetLakehouse.id
                }
            }
        }

        stage('Patch & Deploy Model') {
            steps {
                script {
                    echo "🛠️ Patching TMDL with strict quote preservation..."
                    
                    // The fix: explicitly adding escaped double quotes around the new URL
                    sh """
                        NEW_URL="onelake.dfs.fabric.microsoft.com/${env.WORKSPACE_ID}/${env.LAKEHOUSE_ID}"
                        sed -i "s|onelake.dfs.fabric.microsoft.com/[^/]*/[^/]*|\\\$NEW_URL|g" "${env.MODEL_FOLDER}/definition/expressions.tmdl"
                        
                        # Ensure EnvironmentName is also properly quoted
                        sed -i 's/expression EnvironmentName = .*/expression EnvironmentName = "QA"/' "${env.MODEL_FOLDER}/definition/expressions.tmdl"
                    """

                    // DEBUG: Check if quotes exist. If they don't, the next step will fail.
                    echo "📝 Verifying TMDL syntax:"
                    sh "grep 'onelake.dfs.fabric.microsoft.com' '${env.MODEL_FOLDER}/definition/expressions.tmdl'"

                    def pbismBase64 = sh(script: "base64 -w 0 ${env.MODEL_FOLDER}/definition.pbism", returnStdout: true).trim()
                    def parts = [[path: "definition.pbism", payload: pbismBase64, payloadType: "InlineBase64"]]
                    
                    def tmdlFiles = sh(script: "find ${env.MODEL_FOLDER}/definition -name '*.tmdl'", returnStdout: true).split()
                    tmdlFiles.each { filePath ->
                        def relativePath = filePath.substring(filePath.indexOf("definition/"))
                        def fileBase64 = sh(script: "base64 -w 0 ${filePath}", returnStdout: true).trim()
                        parts << [path: relativePath, payload: fileBase64, payloadType: "InlineBase64"]
                    }

                    writeJSON file: 'model_payload.json', json: [displayName: env.MODEL_NAME, type: "SemanticModel", definition: [parts: parts]]

                    fabricPoll("https://api.fabric.microsoft.com/v1/workspaces/${env.WORKSPACE_ID}/items/${env.SEMANTIC_MODEL_ID}/updateDefinition", 'model_payload.json')
                }
            }
        }

        stage('Binding & Refresh') {
            steps {
                script {
                    sh """
                        curl -s -X POST "https://api.powerbi.com/v1.0/myorg/groups/${env.WORKSPACE_ID}/datasets/${env.SEMANTIC_MODEL_ID}/Default.TakeOver" \
                        -H "Authorization: Bearer ${env.TOKEN}" -H "Content-Length: 0"
                    """
                    
                    sleep 10

                    def bindPayload = [gatewayObjectId: "00000000-0000-0000-0000-000000000000", datasourceObjectIds: ["${env.QA_CONNECTION_ID}"]]
                    writeJSON file: 'bind_payload.json', json: bindPayload
                    sh """
                        curl -s -X POST "https://api.powerbi.com/v1.0/myorg/groups/${env.WORKSPACE_ID}/datasets/${env.SEMANTIC_MODEL_ID}/Default.BindToGateway" \
                        -H "Authorization: Bearer ${env.TOKEN}" -H "Content-Type: application/json" -d @bind_payload.json
                    """

                    sh """
                        curl -s -X POST "https://api.powerbi.com/v1.0/myorg/groups/${env.WORKSPACE_ID}/datasets/${env.SEMANTIC_MODEL_ID}/refreshes" \
                        -H "Authorization: Bearer ${env.TOKEN}" -H "Content-Type: application/json" -d '{"type": "Full"}'
                    """
                }
            }
        }
    }

    post {
        always {
            sh "rm -f model_payload.json bind_payload.json"
        }
    }
}

def fabricPoll(apiUrl, payloadFile) {
    def responseHeaders = sh(script: "curl -i -s -X POST ${apiUrl} -H 'Authorization: Bearer ${env.TOKEN}' -H 'Content-Type: application/json' -d @${payloadFile}", returnStdout: true)
    def opUrl = sh(script: "echo '${responseHeaders}' | grep -i 'location:' | awk '{print \$2}' | tr -d '\\r'", returnStdout: true).trim()

    if (opUrl && opUrl != "null") {
        echo "📡 Polling Operation: ${opUrl}"
        while (true) {
            sleep 15
            def statusRaw = sh(script: "curl -s -H 'Authorization: Bearer ${env.TOKEN}' ${opUrl}", returnStdout: true)
            def status = readJSON(text: statusRaw).status
            if (status == "Succeeded") break
            if (status == "Failed") {
                echo "Full Error Response: ${statusRaw}"
                error "❌ Fabric API Failure."
            }
        }
    } else {
        error "❌ Failed to initiate operation."
    }
}
