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
                    // Fetch existing items to see if we update or create
                    def itemsResp = sh(script: "curl -s -H 'Authorization: Bearer ${env.TOKEN}' https://api.fabric.microsoft.com/v1/workspaces/${env.WORKSPACE_ID}/items", returnStdout: true)
                    def existingModel = readJSON(text: itemsResp).value.find { it.displayName == env.MODEL_NAME && it.type == "SemanticModel" }

                    // Build Multi-Part TMDL Payload
                    def parts = []
                    parts << [
                        path: "definition.pbism", 
                        payload: sh(script: "base64 -w 0 ${env.MODEL_FOLDER}/definition.pbism", returnStdout: true).trim(), 
                        payloadType: "InlineBase64"
                    ]
                    
                    def tmdlFiles = sh(script: "find ${env.MODEL_FOLDER}/definition -name '*.tmdl'", returnStdout: true).split()
                    tmdlFiles.each { filePath ->
                        def relativePath = filePath.substring(filePath.indexOf("definition/"))
                        parts << [
                            path: relativePath, 
                            payload: sh(script: "base64 -w 0 ${filePath}", returnStdout: true).trim(), 
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
                    
                    echo "🚀 Deploying Semantic Model..."
                    fabricPoll(apiUrl, 'model_payload.json')
                }
            }
        }

        stage('Deploy Report') {
            steps {
                script {
                    def itemsResp = sh
