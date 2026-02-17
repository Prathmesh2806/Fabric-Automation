pipeline {
    agent any
    
    environment {
        CLIENT_ID     = credentials('fabric-client-id')
        CLIENT_SECRET = credentials('fabric-client-secret')
        TENANT_ID     = credentials('fabric-tenant-id')
    }
    
    stages {
        stage('Checkout & Config') {
            steps {
                script {
                    // Repo checkout
                    git branch: 'dev', credentialsId: 'github-creds', url: 'https://github.com/Prathmesh2806/Fabric-Automation.git'
                    
                    // Config settings
                    env.TARGET_WORKSPACE_ID = "afc6fad2-d19f-4f1b-bc5a-eb5f2caf40e6"
                    env.REPORT_NAME = "Sales_Report_A"
                    env.DATASET_NAME = "Sales_Model_A"
                    env.DETECTED_FOLDER = "Customer-A"
                }
            }
        }

        stage('Get Token') {
            steps {
                script {
                    def tokenResponse = sh(script: "curl -s -X POST https://login.microsoftonline.com/${TENANT_ID}/oauth2/v2.0/token -d 'grant_type=client_credentials&client_id=${CLIENT_ID}&client_secret=${CLIENT_SECRET}&scope=https://api.fabric.microsoft.com/.default'", returnStdout: true)
                    env.TOKEN = readJSON(text: tokenResponse).access_token
                }
            }
        }

        stage('Prep Target Dataset') {
            steps {
                script {
                    // Get Dataset GUID for binding
                    def itemsResponse = sh(script: "curl -s -X GET https://api.fabric.microsoft.com/v1/workspaces/${env.TARGET_WORKSPACE_ID}/items -H 'Authorization: Bearer ${env.TOKEN}'", returnStdout: true)
                    def itemsJson = readJSON text: itemsResponse
                    def ds = itemsJson.value.find { it.displayName == env.DATASET_NAME }
                    
                    if (!ds) { 
                        error "❌ Dataset '${env.DATASET_NAME}' sapdla nahi target workspace madhe!" 
                    }
                    
                    env.TARGET_DATASET_ID = ds.id
                    echo "🎯 Target Dataset GUID: ${env.TARGET_DATASET_ID}"
                }
            }
        }

        stage('Deploy Report') {
            steps {
                script {
                    def folderPath = "${env.DETECTED_FOLDER}/${env.REPORT_NAME}.Report"
                    
                    // 1. Convert report.json to Base64
                    def reportContent = sh(script: "base64 -w 0 ${folderPath}/report.json", returnStdout: true).trim()
                    
                    // 2. Create PBIR with Dataset Binding
                    def pbirJson = """{
                      "version": "1.0",
                      "datasetReference": {
                        "byConnection": {
                          "connectionString": null,
                          "pbiServiceModelId": null,
                          "pbiModelVirtualServerName": null,
                          "pbiModelDatabaseName": "${env.TARGET_DATASET_ID}",
                          "name": "EntityDataSource",
                          "connectionType": "pbiServiceXml"
                        }
                      }
                    }"""
                    
                    writeFile file: 'definition.pbir', text: pbirJson
                    def pbirBase64 = sh(script: "base64 -w 0 definition.pbir", returnStdout: true).trim()
                    
                    // 3. Prepare Payload
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

                    // 4. Call Fabric API
                    def curlCmd = "curl -i -s -X POST https://api.fabric.microsoft.com/v1/workspaces/${env.TARGET_WORKSPACE_ID}/items -H 'Authorization: Bearer ${env.TOKEN}' -H 'Content-Type: application/json' -d @payload.json"
                    def responseHeaders = sh(script: curlCmd, returnStdout: true)
                    
                    // 5. Extract Operation URL for monitoring
                    def opUrl = sh(script: "echo '${responseHeaders}' | grep -i 'location:' | awk '{print \$2}' | tr -d '\\r'", returnStdout: true).trim()
                    
                    if (opUrl && opUrl != "null") {
                        echo "🔗 Monitoring Operation URL: ${opUrl}"
                        
                        // 6. Monitoring Loop
                        for(int i=0; i<15; i++) {
                            int attemptNumber = i + 1
                            echo "⏳ Monitoring (Attempt ${attemptNumber})..."
                            sleep 25
                            
                            // Using Double Quotes for shell to access Groovy variable 'opUrl'
                            def statusRaw = sh(script: "curl -s -X GET '${opUrl}' -H 'Authorization: Bearer ${env.TOKEN}'", returnStdout: true)
                            echo
