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
                git branch: 'dev', credentialsId: 'github-creds', url: 'https://github.com/Prathmesh2806/Fabric-Automation.git'
                script {
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
        stage('Cleanup') {
            steps {
                script {
                    def itemsResponse = sh(script: "curl -s -X GET https://api.fabric.microsoft.com/v1/workspaces/${env.TARGET_WORKSPACE_ID}/items -H 'Authorization: Bearer ${env.TOKEN}'", returnStdout: true)
                    def itemsJson = readJSON text: itemsResponse
                    
                    def ds = itemsJson.value.find { it.displayName == env.DATASET_NAME }
                    if (!ds) { error "❌ Dataset '${env.DATASET_NAME}' sapdla nahi!" }
                    env.TARGET_DATASET_ID = ds.id

                    def rep = itemsJson.value.find { it.displayName == env.REPORT_NAME }
                    if (rep) {
                        sh "curl -s -X DELETE https://api.fabric.microsoft.com/v1/workspaces/${env.TARGET_WORKSPACE_ID}/items/${rep.id} -H 'Authorization: Bearer ${env.TOKEN}'"
                        echo "🧹 June items clean kele..."
                        sleep 10
                    }
                }
            }
        }
        stage('Deploy & Status Check') {
            steps {
                script {
                    def reportPath = "${env.DETECTED_FOLDER}/${env.REPORT_NAME}.Report/report.json"
                    def reportContent = sh(script: "base64 -w 0 ${reportPath}", returnStdout: true).trim()
                    
                    def createPayload = [
                        displayName: env.REPORT_NAME,
                        type: "Report",
                        definition: [parts: [[path: "report.json", payload: reportContent, payloadType: "InlineBase64"]]],
                        relations: [[id: env.TARGET_DATASET_ID, type: "SemanticModel"]]
                    ]
                    writeJSON file: 'payload.json', json: createPayload

                    // Capture location header using grep to avoid Regex Serialization issues
                    def opUrl = sh(script: "curl -i -s -X POST https://api.fabric.microsoft.com/v1/workspaces/${env.TARGET_WORKSPACE_ID}/items -H 'Authorization: Bearer ${env.TOKEN}' -H 'Content-Type: application/json' -d @payload.json | grep -i 'location:' | cut -d' ' -f2", returnStdout: true).trim()
                    
                    if (opUrl) {
                        echo "🔍 Tracking Operation: ${opUrl}"
                        // Loop for checking status
                        for(int i=0; i<6; i++) {
                            echo "⏳ Attempt ${i+1}: Waiting for Fabric to finish..."
                            sleep 20
                            def statusJson = sh(script: "curl -s -X GET ${opUrl} -H 'Authorization: Bearer ${env.TOKEN}'", returnStdout: true)
                            echo "Current Status: ${statusJson}"
                            
                            if (statusJson.contains("Succeeded")) {
                                echo "✅ EXCELLENT! Report '${env.REPORT_NAME}' banla aahe."
                                return
                            } else if (statusJson.contains("Failed")) {
                                error "❌ Fabric error dila: ${statusJson}"
                            }
                        }
                    } else {
                        echo "⚠️ Operation URL sapdli nahi, manually check kara."
                        sleep 30
                    }
                }
            }
        }
    }
}
