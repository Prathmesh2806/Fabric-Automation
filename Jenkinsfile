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
                    // GitHub repo checkout
                    git branch: 'dev', credentialsId: 'github-creds', url: 'https://github.com/Prathmesh2806/Fabric-Automation.git'
                    
                    // Configuration
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
                    // Shodha ki QA workspace madhe to dataset aahe ka (GUID pahije binding sathi)
                    def itemsResponse = sh(script: "curl -s -X GET https://api.fabric.microsoft.com/v1/workspaces/${env.TARGET_WORKSPACE_ID}/items -H 'Authorization: Bearer ${env.TOKEN}'", returnStdout: true)
                    def itemsJson = readJSON text: itemsResponse
                    def ds = itemsJson.value.find { it.displayName == env.DATASET_NAME }
                    
                    if (!ds) { 
                        error "❌ Dataset '${env.DATASET_NAME}' target workspace madhe sapdla nahi. Adhi dataset deploy kara!" 
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
                    
                    // 1. report.json base64
                    def reportContent = sh(script: "base64 -w 0 ${folderPath}/report.json", returnStdout: true).trim()
                    
                    // 2. definition.pbir (Binding logic)
                    // pbiServiceModelId null thevlay karan to Integer magto, connectionString madhe GUID dila aahe.
                    def pbirJson = """{
                      "version": "1.0",
                      "datasetReference": {
                        "byConnection": {
                          "connectionString": "Data Source=powerbi://api.powerbi.com/v1.0/myorg/TargetWorkspace;Initial Catalog=${env.DATASET_NAME};semanticModelId=${env.TARGET_DATASET_ID}",
                          "pbiServiceModelId": null,
                          "pbiModelVirtualServerName": null,
                          "pbiModelDatabaseName": null,
                          "name": "EntityDataSource",
                          "connectionType": "pbiServiceXml"
                        }
                      }
                    }"""
                    
                    writeFile file: 'definition.pbir', text: pbirJson
                    def pbirBase64 = sh(script: "base64 -w 0 definition.pbir", returnStdout: true).trim()
                    
                    // 3. Construct Payload
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

                    // 4. API Call
                    def curlCmd = "curl -i -s -X POST https://api.fabric.microsoft.com/v1/workspaces/${env.TARGET_WORKSPACE_ID}/items " +
                                  "-H 'Authorization: Bearer ${env.TOKEN}' " +
                                  "-H 'Content-Type: application/json' -d @payload.json"
                    
                    def responseHeaders = sh(script: curlCmd, returnStdout: true)
                    
                    // 5. Extract Operation ID for monitoring
                    // tr -d '\\r' vaparlay extra carriage return remove karayla
                    def opUrl = sh(script: "echo '${responseHeaders}' | grep -i 'location:' | awk '{print \$2}' | tr -d '\\r'", returnStdout: true).trim()
                    
                    if (opUrl && opUrl != "null") {
                        echo "🔗 Monitoring Operation: ${opUrl}"
                        
                        // 6. Monitoring Loop
                        for(int i=0; i<12; i++) {
                            echo "⏳ Monitoring (Attempt ${i+1})..."
                            sleep 20
                            
                            def statusRaw = sh(script: "curl -s -X GET '${opUrl}' -H 'Authorization: Bearer ${env.TOKEN}'", returnStdout: true)
                            echo "🔍 Status Response: ${statusRaw}"
                            
                            if (statusRaw.contains("Succeeded")) {
                                echo "✅ SUCCESS! Report '${env.REPORT_NAME}' is now live in QA."
                                return
                            } else if (statusRaw.contains("Failed")) {
                                error "❌ Fabric Error: ${statusRaw}"
                            }
                        }
                        error "⌛ Timeout: Deployment is taking too long."
                    } else {
                        error "❌ Deployment failed to start. API Headers: ${responseHeaders}"
                    }
                }
            }
        }
    }
}
