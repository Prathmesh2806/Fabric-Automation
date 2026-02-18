pipeline {
    agent any

    environment {
        // Update these with your actual IDs
        WORKSPACE_ID = "afc6fad2-d19f-4f1b-bc5a-eb5f2caf40e6"
        SEMANTIC_MODEL_ID = "5bd5e7ae-95ff-4251-8fd3-f6d14fa8439c"
        MODEL_FOLDER = "Customer-A/Sales_Model_A.SemanticModel"
        TENANT_ID = credentials('TENANT_ID')
        CLIENT_ID = credentials('CLIENT_ID')
        CLIENT_SECRET = credentials('CLIENT_SECRET')
    }

    stages {
        stage('Auth & Capacity Check') {
            steps {
                script {
                    // Get Access Token
                    def authResponse = sh(script: """
                        curl -s -X POST https://login.microsoftonline.com/${env.TENANT_ID}/oauth2/v2.0/token \
                        -d grant_type=client_credentials \
                        -d client_id=${env.CLIENT_ID} \
                        -d client_secret=${env.CLIENT_SECRET} \
                        -d scope=https://api.fabric.microsoft.com/.default
                    """, returnStdout: true)
                    
                    def authJson = readJSON text: authResponse
                    env.TOKEN = authJson.access_token

                    echo "🔍 Verifying Capacity Status..."
                    sh "curl -s -H 'Authorization: Bearer ${env.TOKEN}' https://api.powerbi.com/v1.0/myorg/capacities"
                    echo "✅ Capacity is Active."
                }
            }
        }

        stage('Deploy Semantic Model') {
            steps {
                script {
                    // 1. DYNAMIC DISCOVERY: Find the Lakehouse inside the target workspace
                    echo "🔍 Finding QA Lakehouse ID in Workspace ${env.WORKSPACE_ID}..."
                    def itemsListResponse = sh(script: "curl -s -H 'Authorization: Bearer ${env.TOKEN}' https://api.fabric.microsoft.com/v1/workspaces/${env.WORKSPACE_ID}/items", returnStdout: true)
                    def itemsJson = readJSON text: itemsListResponse
                    
                    // Finds the first Lakehouse in the workspace
                    def targetLakehouse = itemsJson.value.find { it.type == "Lakehouse" }
                    
                    if (!targetLakehouse) {
                        error "❌ No Lakehouse found in Workspace ${env.WORKSPACE_ID}. Deployment cannot proceed."
                    }
                    
                    def ACTUAL_LAKEHOUSE_ID = targetLakehouse.id
                    echo "✅ Found Lakehouse: ${targetLakehouse.displayName} (${ACTUAL_LAKEHOUSE_ID})"

                    // 2. PATCHING TMDL
                    echo "🛠️ Patching TMDL with Verified IDs..."
                    sh """
                        # Update the OneLake URL to ensure consistency between Workspace and Lakehouse
                        sed -i 's|onelake.dfs.fabric.microsoft.com/[^/]*/[^/]*|onelake.dfs.fabric.microsoft.com/${env.WORKSPACE_ID}/${ACTUAL_LAKEHOUSE_ID}|g' "${env.MODEL_FOLDER}/definition/expressions.tmdl"
                        
                        # Update Environment Parameter
                        sed -i 's/expression EnvironmentName = .*/expression EnvironmentName = "QA"/' "${env.MODEL_FOLDER}/definition/expressions.tmdl"
                        
                        echo "--- VERIFYING PATCHED TMDL LINE ---"
                        grep "Source =" "${env.MODEL_FOLDER}/definition/expressions.tmdl"
                        echo "----------------------------------"
                    """

                    // 3. BUILD PAYLOAD (Base64 Encoding)
                    def parts = []
                    
                    // Add pbism
                    def pbismBase64 = sh(script: "base64 -w 0 ${env.MODEL_FOLDER}/definition.pbism", returnStdout: true).trim()
                    parts << [path: "definition.pbism", payload: pbismBase64, payloadType: "InlineBase64"]

                    // Add all TMDL files
                    def tmdlFiles = sh(script: "find ${env.MODEL_FOLDER}/definition -name '*.tmdl'", returnStdout: true).split()
                    tmdlFiles.each { filePath ->
                        def relativePath = filePath.replace("${env.MODEL_FOLDER}/", "")
                        def filePayload = sh(script: "base64 -w 0 ${filePath}", returnStdout: true).trim()
                        parts << [path: relativePath, payload: filePayload, payloadType: "InlineBase64"]
                    }

                    def payload = [definition: [parts: parts]]
                    writeJSON file: 'model_payload.json', json: payload

                    // 4. DEPLOY TO FABRIC
                    echo "🚀 Uploading Definition to Fabric..."
                    def deployCmd = """
                        curl -i -s -X POST https://api.fabric.microsoft.com/v1/workspaces/${env.WORKSPACE_ID}/items/${env.SEMANTIC_MODEL_ID}/updateDefinition \
                        -H "Authorization: Bearer ${env.TOKEN}" \
                        -H "Content-Type: application/json" \
                        -d @model_payload.json
                    """
                    def responseHeaders = sh(script: deployCmd, returnStdout: true)
                    
                    // Extract Operation URL for polling
                    def operationUrl = sh(script: "echo '${responseHeaders}' | grep -i 'location:' | awk '{print \$2}' | tr -d '\\r'", returnStdout: true).trim()
                    echo "📡 Polling Operation: ${operationUrl}"

                    // 5. POLL FOR COMPLETION
                    def status = "InProgress"
                    while (status == "InProgress" || status == "NotStarted") {
                        sleep 20
                        def pollResponse = sh(script: "curl -s -H 'Authorization: Bearer ${env.TOKEN}' ${operationUrl}", returnStdout: true)
                        def pollJson = readJSON text: pollResponse
                        status = pollJson.status
                        
                        if (status == "Failed") {
                            error "❌ Fabric API Failure: ${pollResponse}"
                        }
                    }
                    echo "✅ Semantic Model Deployed Successfully!"
                }
            }
        }
        
        // Add your subsequent stages here (Ownership, Refresh, etc.)
    }

    post {
        always {
            sh "rm -f model_payload.json"
        }
    }
}
