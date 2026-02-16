pipeline {
    agent any

    environment {
        CLIENT_ID     = credentials('fabric-client-id')
        CLIENT_SECRET = credentials('fabric-client-secret')
        TENANT_ID     = credentials('fabric-tenant-id')
    }

    stages {
        stage('Checkout & Detect Change') {
            steps {
                git branch: 'dev', credentialsId: 'github-creds', url: 'https://github.com/Prathmesh2806/Fabric-Automation.git'
                script {
                    // Detect changed folder (Customer-A or Customer-B)
                    def changedFolder = sh(script: "git diff --name-only HEAD~1 | grep / | cut -d/ -f1 | head -1", returnStdout: true).trim()
                    env.DETECTED_FOLDER = changedFolder
                    
                    // Workspace ID Mapping Logic
                    if (env.DETECTED_FOLDER == "Customer-A") {
                        env.TARGET_WORKSPACE_ID = "afc6fad2-d19f-4f1b-bc5a-eb5f2caf40e6" // QA-A
                        env.REPORT_NAME = "Sales_Report_A"
                    } else if (env.DETECTED_FOLDER == "Customer-B") {
                        env.TARGET_WORKSPACE_ID = "tujha-qa-b-workspace-id-ithe-tak" // QA-B ID
                        env.REPORT_NAME = "Sales_Report_B"
                    } else {
                        error "❌ Unknown folder detected: ${env.DETECTED_FOLDER}. Pipeline stopped."
                    }
                    
                    echo "📁 Detected Folder: ${env.DETECTED_FOLDER}"
                    echo "🎯 Target Workspace: ${env.TARGET_WORKSPACE_ID}"
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
                    
                    def targetItem = itemsJson.value.find { it.displayName == env.REPORT_NAME }
                    
                    if (targetItem) {
                        env.TARGET_ITEM_ID = targetItem.id
                        env.REPORT_EXISTS = "true"
                        echo "✅ Existing Report Found! ID: ${env.TARGET_ITEM_ID}"
                    } else {
                        env.REPORT_EXISTS = "false"
                        echo "⚠️ Report not found. New one will be created."
                    }
                }
            }
        }

        stage('Push to QA (API)') {
            steps {
                script {
                    // Dynamic path based on folder and report name
                    def reportPath = "${env.DETECTED_FOLDER}/${env.REPORT_NAME}.Report/report.json"
                    def reportContent = sh(script: "base64 -w 0 ${reportPath}", returnStdout: true).trim()
                    
                    def payload = [
                        definition: [
                            parts: [[path: "report.json", payload: reportContent, payloadType: "InlineBase64"]]
                        ]
                    ]
                    writeJSON file: 'payload.json', json: payload

                    if (env.REPORT_EXISTS == "true") {
                        echo "🚀 Updating ${env.REPORT_NAME} in ${env.DETECTED_FOLDER}..."
                        sh "curl -s -X POST https://api.fabric.microsoft.com/v1/workspaces/${env.TARGET_WORKSPACE_ID}/items/${env.TARGET_ITEM_ID}/updateDefinition -H 'Authorization: Bearer ${env.TOKEN}' -H 'Content-Type: application/json' -d @payload.json"
                    } else {
                        echo "🚀 Creating ${env.REPORT_NAME} in ${env.DETECTED_FOLDER}..."
                        def createPayload = [
                            displayName: env.REPORT_NAME,
                            type: "Report",
                            definition: payload.definition
                        ]
                        writeJSON file: 'create_payload.json', json: createPayload
                        sh "curl -s -X POST https://api.fabric.microsoft.com/v1/workspaces/${env.TARGET_WORKSPACE_ID}/items -H 'Authorization: Bearer ${env.TOKEN}' -H 'Content-Type: application/json' -d @create_payload.json"
                    }
                }
            }
        }
    }
}
