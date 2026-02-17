pipeline {
    agent any
    environment {
        // Credentials IDs match with your Jenkins settings
        CLIENT_ID     = credentials('fabric-client-id')
        CLIENT_SECRET = credentials('fabric-client-secret')
        TENANT_ID     = credentials('fabric-tenant-id')
    }
    stages {
        stage('Checkout & Config') {
            steps {
                git branch: 'dev', credentialsId: 'github-creds', url: 'https://github.com/Prathmesh2806/Fabric-Automation.git'
                script {
                    // Tumche Environment Variables
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
                    // Workspace madhle items list kara
                    def itemsResponse = sh(script: "curl -s -X GET https://api.fabric.microsoft.com/v1/workspaces/${env.TARGET_WORKSPACE_ID}/items -H 'Authorization: Bearer ${env.TOKEN}'", returnStdout: true)
                    def itemsJson = readJSON text: itemsResponse
                    
                    // 1. Dataset ID shodha (Report link karnyasathi garjeche aahe)
                    def ds = itemsJson.value.find { it.displayName == env.DATASET_NAME }
                    if (!ds) { error "❌ Dataset '${env.DATASET_NAME}' sapdla nahi! Please check your workspace." }
                    env.TARGET_DATASET_ID = ds.id
                    echo "🎯 Dataset ID sapdla: ${env.TARGET_DATASET_ID}"

                    // 2. Juna Report asel tar to delete kara
                    def rep = itemsJson.value.find { it.displayName == env.REPORT_NAME }
                    if (rep) {
                        echo "🧹 Juna Report '${env.REPORT_NAME}' delete kartoy..."
                        sh "curl -s -X DELETE https://api.fabric.microsoft.com/v1/workspaces/${env.TARGET_WORKSPACE_ID}/items/${rep.id} -H 'Authorization: Bearer ${env.TOKEN}'"
                        sleep 10
                    }
                }
            }
        }
        stage('Deploy & Status Check') {
            steps {
                script {
                    def folderPath = "${env.DETECTED_FOLDER}/${env.REPORT_NAME}.Report"
                    
                    // 1. report.json Base64 madhe convert kara
                    def reportContent = sh(script: "base64 -w 0 ${folderPath}/report.json", returnStdout: true).trim()
                    
                    // 2. PBIR dynamic generate kara (byConnection format madhe)
                    // Fabric API la "ByPath" chalat nahi, tyamule apan swatacha JSON banavtoye
                    def pbirJson = """{
                        "version": "1.0",
                        "datasetReference": {
                            "byConnection": {
                                "connectionId": "${env.TARGET_DATASET_ID}",
                                "connectionType": "pbiServiceXml"
                            }
                        }
                    }"""
                    
                    def pbirBase64 = sh(script: "echo '${pbirJson}' | base64 -w 0", returnStdout: true).trim()
                    
                    // 3. Final Payload tayar kara
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

                    echo "🚀 Fabric API la Deployment Request pathavtoye..."
                    
                    // 4. API Call kara ani Location Header (Operation URL) capture kara
                    def curlCmd = "curl -i -s -X POST https://api.fabric.microsoft.com/v1/workspaces/${env.TARGET_WORKSPACE_ID}/items " +
                                  "-H 'Authorization: Bearer ${env.TOKEN}' " +
                                  "-H 'Content-Type: application/json' -d @payload.json"
                    
                    def responseHeaders = sh(script: curlCmd, returnStdout: true)
                    
                    // Location URL kadhnyasathi simple grep vapru (No Regex Serialization issues)
                    def opUrl = sh(script: "echo \"${responseHeaders}\" | grep -i 'location:' | cut -d' ' -f2", returnStdout: true).trim()
                    
                    if (opUrl) {
                        echo "🔍 Operation Track kartoy: ${opUrl}"
                        // Status loop (Check every 20 seconds)
                        for(int i=0; i<6; i++) {
                            echo "⏳ Attempt ${i+1}: Waiting for Fabric to finish..."
                            sleep 20
                            def statusRaw = sh(script: "curl -s -X GET ${opUrl} -H 'Authorization: Bearer ${env.TOKEN}'", returnStdout: true)
                            
                            if (statusRaw.contains("Succeeded")) {
                                echo "✅ SUCCESS! Report '${env.REPORT_NAME}' yashasviphane deploy jhala aahe."
                                return
                            } else if (statusRaw.contains("Failed")) {
                                error "❌ Fabric Failure: ${statusRaw}"
                            }
                        }
                        error "❌ Timeout: Fabric ne khup vel ghetla."
                    } else {
                        error "❌ Operation URL sapdli nahi. API Response check kara: ${responseHeaders}"
                    }
                }
            }
        }
    }
}
