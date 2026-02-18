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
        QA_CONNECTION_ID = "7d3a6d82-0f86-42b0-9c98-84610e10ff95"
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
                    echo "🛠️ Patching TMDL..."
                    
                    // We use a simpler sed approach: find the line starting with "Source =" 
                    // and replace the entire line with the correctly quoted string.
                    sh """
                        FILE_PATH="${env.MODEL_FOLDER}/definition/expressions.tmdl"
                        NEW_VAL="onelake.dfs.fabric.microsoft.com/${env.WORKSPACE_ID}/${env.LAKEHOUSE_ID}"
                        
                        # This replaces the line containing 'onelake' with the full correct syntax
                        # We use double backslashes to ensure the quotes survive the Jenkins shell
                        sed -i "s|onelake.dfs.fabric.microsoft.com/[^\\\"]*|\$NEW_VAL|g" \$FILE_PATH
                        
                        # Patch EnvironmentName
                        sed -i 's/expression EnvironmentName = .*/expression EnvironmentName = "QA"/' \$FILE_PATH
                        
                        echo "📝 Patched file preview (Source line):"
                        grep "onelake" \$FILE_PATH || true
                    """

                    echo "📦 Encoding Payload..."
                    def pbismBase64 = sh(script: "base64 -w 0 ${env.MODEL_FOLDER}/definition.pbism", returnStdout: true).trim()
                    def parts = [[path: "definition.pbism", payload: pbismBase64, payloadType: "InlineBase64"]]
                    
                    // Find and add all .tmdl files
                    def tmdlFiles = sh(script: "find ${env.MODEL_FOLDER}/definition -name '*.tmdl'", returnStdout: true).split()
                    tmdlFiles.each { filePath ->
                        def relativePath = filePath.substring(filePath.indexOf("definition/"))
                        def fileBase64 = sh(script: "base64 -w 0 ${filePath}", returnStdout: true).trim()
                        parts << [path: relativePath, payload: fileBase64, payloadType: "InlineBase64"]
                    }

                    writeJSON file: 'model_payload.json', json: [displayName: env.MODEL_NAME, type: "SemanticModel", definition: [parts: parts]]

                    echo "🚀 Uploading to Fabric API..."
                    fabricPoll("https://api.fabric.microsoft.com/v1/workspaces/${env.WORKSPACE_ID}/items/${env.SEMANTIC_MODEL_ID}/updateDefinition", 'model_payload.json')
                }
            }
        }

        stage('Finalize') {
            steps {
                script {
                    echo "👑 Taking Ownership & Refreshing..."
                    sh "curl -s -X POST 'https://api.powerbi.com/v1.0/myorg/groups/${env.WORKSPACE_ID}/datasets/${env.SEMANTIC_MODEL_ID}/Default.TakeOver' -H 'Authorization: Bearer ${env.TOKEN}' -H 'Content-Length: 0'"
                    
                    sleep 5

                    def bindPayload = [gatewayObjectId: "00000000-0000-0000-0000-000000000000", datasourceObjectIds: ["${env.QA_CONNECTION_ID}"]]
                    writeJSON file: 'bind_payload.json', json: bindPayload
                    sh "curl -s -X POST 'https://api.powerbi.com/v1.0/myorg/groups/${env.WORKSPACE_ID}/datasets/${env.SEMANTIC_MODEL_ID}/Default.BindToGateway' -H 'Authorization: Bearer ${env.TOKEN}' -H 'Content-Type: application/json' -d @bind_payload.json"

                    sh "curl -s -X POST 'https://api.powerbi.com/v1.0/myorg/groups/${env.WORKSPACE_ID}/datasets/${env.SEMANTIC_MODEL_ID}/refreshes' -H 'Authorization: Bearer ${env.TOKEN}' -H 'Content-Type: application/json' -d '{\"type\": \"Full\"}'"
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
        echo "📡 Operation URL: ${opUrl}"
        while (true) {
            sleep 15
            def statusRaw = sh(script: "curl -s -H 'Authorization: Bearer ${env.TOKEN}' ${opUrl}", returnStdout: true)
            def statusJson = readJSON(text: statusRaw)
            if (statusJson.status == "Succeeded") {
                echo "✅ Success!"
                break
            }
            if (statusJson.status == "Failed") {
                echo "❌ API Details: ${statusRaw}"
                error "Deployment Failed."
            }
        }
    } else {
        error "❌ API did not return an operation location."
    }
}
