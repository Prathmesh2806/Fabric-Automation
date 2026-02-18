pipeline {
    agent any 

    environment {
        WORKSPACE_ID = "afc6fad2-d19f-4f1b-bc5a-eb5f2caf40e6"
        SEMANTIC_MODEL_ID = "5bd5e7ae-95ff-4251-8fd3-f6d14fa8439c"
        MODEL_FOLDER = "Customer-A/Sales_Model_A.SemanticModel"
    }

    stages {
        stage('Fabric Deployment') {
            steps {
                // withCredentials ensures the secrets are masked and available in the shell context
                withCredentials([
                    string(credentialsId: 'TENANT_ID', variable: 'TENANT_ID'),
                    string(credentialsId: 'CLIENT_ID', variable: 'CLIENT_ID'),
                    string(credentialsId: 'CLIENT_SECRET', variable: 'CLIENT_SECRET')
                ]) {
                    script {
                        // 1. Auth & Token Acquisition
                        echo "🔑 Authenticating with Microsoft..."
                        def authResponse = sh(script: """
                            curl -s -X POST https://login.microsoftonline.com/${TENANT_ID}/oauth2/v2.0/token \
                            -d grant_type=client_credentials \
                            -d client_id=${CLIENT_ID} \
                            -d client_secret=${CLIENT_SECRET} \
                            -d scope=https://api.fabric.microsoft.com/.default
                        """, returnStdout: true)
                        
                        def authJson = readJSON text: authResponse
                        if (!authJson.access_token) {
                            error "❌ Failed to acquire token. Response: ${authResponse}"
                        }
                        env.TOKEN = authJson.access_token

                        // 2. Dynamic Lakehouse Discovery
                        echo "🔍 Finding Lakehouse in Workspace ${env.WORKSPACE_ID}..."
                        def itemsListResponse = sh(script: "curl -s -H 'Authorization: Bearer ${env.TOKEN}' https://api.fabric.microsoft.com/v1/workspaces/${env.WORKSPACE_ID}/items", returnStdout: true)
                        def itemsJson = readJSON text: itemsListResponse
                        def targetLakehouse = itemsJson.value.find { it.type == "Lakehouse" }
                        
                        if (!targetLakehouse) {
                            error "❌ No Lakehouse found in target workspace. Deployment halted."
                        }
                        
                        def ACTUAL_LAKEHOUSE_ID = targetLakehouse.id
                        echo "✅ Target Lakehouse: ${targetLakehouse.displayName} (${ACTUAL_LAKEHOUSE_ID})"

                        // 3. Patching TMDL for QA
                        echo "🛠️ Patching TMDL metadata..."
                        sh """
                            # Update OneLake URL to match the local Workspace/Lakehouse ID
                            sed -i 's|onelake.dfs.fabric.microsoft.com/[^/]*/[^/]*|onelake.dfs.fabric.microsoft.com/${env.WORKSPACE_ID}/${ACTUAL_LAKEHOUSE_ID}|g' "${env.MODEL_FOLDER}/definition/expressions.tmdl"
                            
                            # Update Environment Parameter
                            sed -i 's/expression EnvironmentName = .*/expression EnvironmentName = "QA"/' "${env.MODEL_FOLDER}/definition/expressions.tmdl"
                            
                            echo "--- Patched Line Check ---"
                            grep "Source =" "${env.MODEL_FOLDER}/definition/expressions.tmdl"
                        """

                        // 4. Build Deployment Payload
                        echo "📦 Encoding model files..."
                        def parts = []
                        
                        // definition.pbism
                        def pbismBase64 = sh(script: "base64 -w 0 ${env.MODEL_FOLDER}/definition.pbism", returnStdout: true).trim()
                        parts << [path: "definition.pbism", payload: pbismBase64, payloadType: "InlineBase64"]

                        // All TMDL files
                        def tmdlFiles = sh(script: "find ${env.MODEL_FOLDER}/definition -name '*.tmdl'", returnStdout: true).split()
                        tmdlFiles.each { filePath ->
                            def relativePath = filePath.replace("${env.MODEL_FOLDER}/", "")
                            def filePayload = sh(script: "base64 -w 0 ${filePath}", returnStdout: true).trim()
                            parts << [path: relativePath, payload: filePayload, payloadType: "InlineBase64"]
                        }

                        writeJSON file: 'model_payload.json', json: [definition: [parts: parts]]

                        // 5. Deploy to Fabric
                        echo "🚀 Updating Semantic Model Definition..."
                        def deployHeaders = sh(script: """
                            curl -i -s -X POST https://api.fabric.microsoft.com/v1/workspaces/${env.WORKSPACE_ID}/items/${env.SEMANTIC_MODEL_ID}/updateDefinition \
                            -H "Authorization: Bearer ${env.TOKEN}" \
                            -H "Content-Type: application/json" \
                            -d @model_payload.json
                        """, returnStdout: true)
                        
                        def operationUrl = sh(script: "echo '${deployHeaders}' | grep -i 'location:' | awk '{print \$2}' | tr -d '\\r'", returnStdout: true).trim()
                        
                        // 6. Polling for Completion
                        def status = "InProgress"
                        while (status == "InProgress" || status == "NotStarted") {
                            echo "📡 Status: ${status}. Waiting 20s..."
                            sleep 20
                            def pollResponse = sh(script: "curl -s -H 'Authorization: Bearer ${env.TOKEN}' ${operationUrl}", returnStdout: true)
                            def pollJson = readJSON text: pollResponse
                            status = pollJson.status
                            
                            if (status == "Failed") {
                                error "❌ Fabric Deployment Failed: ${pollResponse}"
                            }
                        }
                        echo "🎉 Successfully deployed to QA!"
                    }
                }
            }
        }
    }

    post {
        always {
            // Since agent any is at the top, this sh call will now have a valid context
            echo "🧹 Cleaning up workspace..."
            sh "rm -f model_payload.json"
        }
    }
}
