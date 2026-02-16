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
                    def changedFolder = sh(script: "git diff --name-only HEAD~1 | grep / | cut -d/ -f1 | head -1", returnStdout: true).trim()
                    env.DETECTED_FOLDER = changedFolder ?: "Customer-A" // Default for testing
                    
                    if (env.DETECTED_FOLDER == "Customer-A") {
                        env.TARGET_WORKSPACE_ID = "afc6fad2-d19f-4f1b-bc5a-eb5f2caf40e6"
                        env.REPORT_NAME = "Sales_Report_A"
                        env.DATASET_NAME = "Sales_Model_A"
                    }
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
        stage('Identify & Cleanup') {
            steps {
                script {
                    def itemsResponse = sh(script: "curl -s -X GET https://api.fabric.microsoft.com/v1/workspaces/${env.TARGET_WORKSPACE_ID}/items -H 'Authorization: Bearer ${env.TOKEN}'", returnStdout: true)
                    def itemsJson = readJSON text: itemsResponse
                    
                    // 1. Dataset ID shōdhā (Garjēchē āhē)
                    def ds = itemsJson.value.find { it.displayName == env.DATASET_NAME }
                    if (!ds) { error "❌ Dataset sapḍalā nāhī!" }
                    env.TARGET_DATASET_ID = ds.id

                    // 2. Jar rēpōrṭ astitvāt asēl, tar tyālā DELETE karā (State Clear karṇyāsāṭhī)
                    def rep = itemsJson.value.find { it.displayName == env.REPORT_NAME }
                    if (rep) {
                        echo "🧹 Junā rēpōrṭ sapḍalā, tyālā kāḍhūñ takatōy..."
                        sh "curl -s -X DELETE https://api.fabric.microsoft.com/v1/workspaces/${env.TARGET_WORKSPACE_ID}/items/${rep.id} -H 'Authorization: Bearer ${env.TOKEN}'"
                        sleep 5 // Thōḍā vēḷ thāmbā sync hōṇyāsāṭhī
                    }
                }
            }
        }
        stage('Final Deploy (Fresh Create)') {
            steps {
                script {
                    def reportPath = "${env.DETECTED_FOLDER}/${env.REPORT_NAME}.Report/report.json"
                    def reportContent = sh(script: "base64 -w 0 ${reportPath}", returnStdout: true).trim()
                    
                    // Navīn Rēpōrṭ Payload (Relations śī Linked)
                    def createPayload = [
                        displayName: env.REPORT_NAME,
                        type: "Report",
                        definition: [
                            parts: [[path: "report.json", payload: reportContent, payloadType: "InlineBase64"]]
                        ],
                        relations: [[id: env.TARGET_DATASET_ID, type: "SemanticModel"]]
                    ]
                    
                    writeJSON file: 'final_payload.json', json: createPayload
                    echo "🚀 Navīn rēpōrṭ banvat āhē..."
                    sh "curl -s -X POST https://api.fabric.microsoft.com/v1/workspaces/${env.TARGET_WORKSPACE_ID}/items -H 'Authorization: Bearer ${env.TOKEN}' -H 'Content-Type: application/json' -d @final_payload.json"
                }
            }
        }
    }
}
