pipeline {
    agent any

    environment {
        // Credentials from Jenkins
        CLIENT_ID     = credentials('fabric-client-id')
        CLIENT_SECRET = credentials('fabric-client-secret')
        TENANT_ID     = credentials('fabric-tenant-id')
    }

    stages {
        stage('Checkout & Detect Change') {
            steps {
                git branch: 'dev', credentialsId: 'github-creds', url: 'https://github.com/Prathmesh2806/Fabric-Automation.git'
                script {
                    // Kontya folder madhe change jhala te detect kara
                    def changedFolder = sh(script: "git diff --name-only HEAD~1 | grep / | cut -d/ -f1 | head -1", returnStdout: true).trim()
                    env.DETECTED_FOLDER = changedFolder
                    
                    // 🎯 Dynamic Workspace & Report Mapping
                    if (env.DETECTED_FOLDER == "Customer-A") {
                        env.TARGET_WORKSPACE_ID = "afc6fad2-d19f-4f1b-bc5a-eb5f2caf40e6"
                        env.REPORT_NAME = "Sales_Report_A"
                        env.DATASET_NAME = "Sales_Model_A"
                    } else if (env.DETECTED_FOLDER == "Customer-B") {
                        env.TARGET_WORKSPACE_ID = "tujha-qa-b-id"
                        env.REPORT_NAME = "Sales_Report_B"
                        env.DATASET_NAME = "Sales_Model_B"
                    } else {
                        error "❌ Unknown folder: ${env.DETECTED_FOLDER}"
                    }
                    echo "📁 Folder: ${env.DETECTED_FOLDER} | 🎯 Workspace: ${env.TARGET_WORKSPACE_ID}"
                }
            }
        }

        stage('Validate & Get Token') {
            steps {
                script {
                    def tokenResponse = sh(script: "curl -s -X POST https://login.microsoftonline.com/${TENANT_ID}/oauth2/v2.0/token -d 'grant_type=client_credentials&client_id=${CLIENT_ID}&client_secret=${CLIENT_SECRET}&scope=https://api.fabric.microsoft.com/.default'", returnStdout: true)
                    def tokenJson = readJSON text: tokenResponse
                    env.TOKEN = tokenJson.access_token
                    echo "✅ Token generated!"
                }
            }
        }

        stage('Identify Target IDs') {
            steps {
                script {
                    def itemsResponse = sh(script: "curl -s -X GET https://api.fabric.microsoft.com/v1/workspaces/${env.TARGET_WORKSPACE_ID}/items -H 'Authorization: Bearer ${env.TOKEN}'", returnStdout: true)
                    def itemsJson = readJSON text: itemsResponse
                    
                    // 1. Report shodha
                    def targetItem = itemsJson.value.find { it.displayName == env.REPORT_NAME }
                    if (targetItem) {
                        env.TARGET_ITEM_ID = targetItem.id
                        env.REPORT_EXISTS = "true"
                        echo "✅ Report Found: ${env.TARGET_ITEM_ID}"
                    } else {
                        env.REPORT_EXISTS = "false"
                        echo "⚠️ Report not found, will create new."
                    }

                    // 2. Dataset ID shodha (Lineage sathi)
                    def targetDataset = itemsJson.value.find { it.displayName == env.DATASET_NAME }
                    if (targetDataset) {
                        env.TARGET_DATASET_ID = targetDataset.id
                        echo "✅ Dataset ID Found: ${env.TARGET_DATASET_ID}"
                    } else {
                        error "❌ Dataset ${env.DATASET_NAME} not found in Workspace!"
                    }
                }
            }
        }

        stage('Push to QA (API)') {
            steps {
                script {
                    def reportPath = "${env.DETECTED_FOLDER}/${env.REPORT_NAME}.Report/report.json"
                    def reportContent = sh(script: "base64 -w 0 ${reportPath}", returnStdout: true).trim()
                    
                    if (env.REPORT_EXISTS == "true") {
                        // UPDATE LOGIC
                        echo "🚀 Updating existing report..."
                        def updatePayload = [
                            definition: [
                                parts: [[path: "report.json", payload: reportContent, payloadType: "InlineBase64"]]
                            ]
                        ]
                        writeJSON file: 'update_payload.json', json: updatePayload
                        sh "curl -s -X POST https://api.fabric.microsoft.com/v1/workspaces/${env.TARGET_WORKSPACE_ID}/items/${env.TARGET_ITEM_ID}/updateDefinition -H 'Authorization: Bearer ${env.TOKEN}' -H 'Content-Type: application/json' -d @update_payload.json"
                    } else {
                        // CREATE LOGIC (With Dataset Lineage)
                        echo "🚀 Creating new report with lineage..."
                        def createPayload = [
                            displayName: env.REPORT_NAME,
                            type: "Report",
                            definition: [
                                parts: [[path: "report.json", payload: reportContent, payloadType: "InlineBase64"]]
                            ],
                            relations: [
                                [
                                    id: env.TARGET_DATASET_ID,
                                    type: "SemanticModel"
                                ]
                            ]
                        ]
                        writeJSON file: 'create_payload.json', json: createPayload
                        sh "curl -s -X POST https://api.fabric.microsoft.com/v1/workspaces/${env.TARGET_WORKSPACE_ID}/items -H 'Authorization: Bearer ${env.TOKEN}' -H 'Content-Type: application/json' -d @create_payload.json"
                    }
                }
            }
        }
    }
}
