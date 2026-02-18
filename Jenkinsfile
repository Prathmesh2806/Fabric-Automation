pipeline {
    agent any

    environment {
        // Credentials IDs from Jenkins Global Credentials
        CLIENT_ID        = credentials('fabric-client-id')
        CLIENT_SECRET    = credentials('fabric-client-secret')
        TENANT_ID        = credentials('fabric-tenant-id')
        
        // Configuration
        WORKSPACE_ID     = "afc6fad2-d19f-4f1b-bc5a-eb5f2caf40e6"
        SEMANTIC_MODEL_ID = "5bd5e7ae-95ff-4251-8fd3-f6d14fa8439c"
        MODEL_NAME       = "Sales_Model_A"
        REPORT_NAME      = "Sales_Report_A"
        
        // Connection Info
        QA_CONNECTION_ID = "58d9731f-fa5f-419a-8619-1e987b11a916"
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
                    // 1. DYNAMIC DISCOVERY: Get the Lakehouse ID
                    echo "🔍 Finding Lakehouse in Workspace ${env.WORKSPACE_ID}..."
                    def itemsResp = sh(script: "curl -s -H 'Authorization: Bearer ${env.TOKEN}' https://api.fabric.microsoft.com/v1/workspaces/${env.WORKSPACE_ID}/items", returnStdout: true)
                    def itemsJson = readJSON(text: itemsResp)
                    
                    def targetLakehouse = itemsJson.value.find { it.type == "Lakehouse" }
                    if (!targetLakehouse) {
                        error "❌ No Lakehouse found in target workspace!"
                    }
                    def ACTUAL_LAKEHOUSE_ID = targetLakehouse.id
                    echo "✅ Found Lakehouse ID: ${ACTUAL_LAKEHOUSE_ID}"

                    // 2. PATCHING: The 'sed' command now strictly preserves double quotes
                    echo "🛠️ Patching TMDL metadata..."
                    sh """
                        # We use | as a delimiter. We match the URL pattern and replace it 
                        # while ensuring the result is wrapped in double quotes.
                        sed -i 's|onelake.dfs.fabric.microsoft.com/[^/]*/[^/]*|onelake.dfs.fabric.microsoft.com/${env.WORKSPACE_ID}/${ACTUAL_LAKEHOUSE_ID}|g' "${env.MODEL_FOLDER}/definition/expressions.tmdl"
                        
                        # Ensure EnvironmentName is set to QA
                        sed -i 's/expression EnvironmentName = .*/expression EnvironmentName = "QA"/' "${env.MODEL_FOLDER}/definition/expressions.tmdl"
                    """

                    // PRE-FLIGHT CHECK: Print the file to Jenkins console to verify quotes
                    echo "📝 Verifying patched expressions.tmdl content:"
                    sh "cat ${env.MODEL_FOLDER}/definition/expressions.tmdl"

                    // 3. ENCODING: Build the payload
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

                    // 4. DEPLOY
                    // Using the SEMANTIC_MODEL_ID from environment to update existing model
                    def apiUrl = "https://api.fabric.microsoft.com/v1/workspaces/${env.WORKSPACE_ID}/items/${env.SEMANTIC_MODEL_ID}/updateDefinition"
                    
                    fabricPoll(apiUrl, 'model_payload.json')
                }
            }
        }

        stage('Ownership & Connection Binding') {
            steps {
                script {
                    echo "👑 Taking Ownership of Model: ${env.SEMANTIC_MODEL_ID}"
                    sh "curl -s
