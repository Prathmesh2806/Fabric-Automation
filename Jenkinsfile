pipeline {
    agent any
    environment {
        CLIENT_ID     = credentials('fabric-client-id')
        CLIENT_SECRET = credentials('fabric-client-secret')
        TENANT_ID     = credentials('fabric-tenant-id')
        WORKSPACE_ID  = "afc6fad2-d19f-4f1b-bc5a-eb5f2caf40e6"
        REPORT_NAME   = "Sales_Report_A"
        DATASET_NAME  = "Sales_Model_A"
        DETECTED_FOLDER = "Customer-A"
    }
    
    stages {
        stage('Checkout & Config') {
            steps {
                script {
                    git branch: 'dev', credentialsId: 'github-creds', url: 'https://github.com/Prathmesh2806/Fabric-Automation.git'
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

        stage('Find IDs & Prep') {
            steps {
                script {
                    // 1. Find Dataset GUID and Report ID in one go
                    def itemsResponse = sh(script: "curl -s -X GET https://api.fabric.microsoft.com/v1/workspaces/${env.WORKSPACE_ID}/items -H 'Authorization: Bearer ${env.TOKEN}'", returnStdout: true)
                    def itemsJson = readJSON text: itemsResponse
                    
                    def ds = itemsJson.value.find { it.displayName == env.DATASET_NAME }
                    if (!ds) { error "❌ Target Dataset '${env.DATASET_NAME}' sapdla nahi!" }
                    env.TARGET_DATASET_ID = ds.id

                    def existingReport = itemsJson.value.find { it.displayName == env.REPORT_NAME && it.type == "Report" }
                    if (existingReport) {
                        env.REPORT_ID = existingReport.id
                        echo "🔍 Found existing report ID: ${env.REPORT_ID}. Will perform updateItemDefinition."
                    } else {
                        env.REPORT_ID = ""
                        echo "🆕 Report not found. Will perform fresh Create."
                    }
                }
            }
        }

        stage('Update or Create Report') {
            steps {
                script {
                    def folderPath = "${env.DETECTED_FOLDER}/${env.REPORT_NAME}.Report"
                    def reportContent = sh(script: "base64 -w 0 ${folderPath}/report.json", returnStdout: true).trim()
                    
                    def pbirJson = """{
                      "version": "1.0",
                      "datasetReference": {
                        "byConnection": {
                          "connectionString": null,
                          "pbiModelDatabaseName": "${env.TARGET_DATASET_ID}",
                          "name": "EntityDataSource",
                          "connectionType": "pbiServiceXml"
                        }
                      }
                    }"""
                    
                    writeFile file: 'definition.pbir', text: pbirJson
                    def pbirBase64 = sh(script: "base64 -w 0 definition.pbir", returnStdout: true).trim()
                    
                    def payload = [
                        definition: [
                            parts: [
                                [path: "report.json", payload: reportContent, payloadType: "InlineBase64"],
                                [path: "definition.pbir", payload: pbirBase64, payloadType: "InlineBase64"]
                            ]
                        ]
                    ]
                    writeJSON file: 'payload.json', json: payload

                    def apiEndpoint = ""
                    if (env.REPORT_ID != "") {
                        // UPDATE Logic: No displayName needed in payload
                        apiEndpoint = "https://api.fabric.microsoft.com/v1/workspaces/${env.WORKSPACE_ID}/items/${env.REPORT_ID}/updateItemDefinition"
                    } else {
                        // CREATE Logic: Add displayName to payload
                        payload.displayName = env.REPORT_NAME
                        payload.type = "Report"
                        writeJSON file: 'payload.json', json: payload
                        apiEndpoint = "https://api.fabric.microsoft.com/v1/workspaces/${env.WORKSPACE_ID}/items"
                    }

                    def curlCmd = "curl -i -s -X POST ${apiEndpoint} -H 'Authorization: Bearer ${env.TOKEN}' -H 'Content-Type: application/json' -d @payload.json"
                    def responseHeaders = sh(script: curlCmd, returnStdout: true)
                    
                    def opUrl = sh(script: "echo '${responseHeaders}' | grep -i 'location:' | awk '{print \$2}' | tr -d '\\r'", returnStdout: true).trim()
                    
                    if (opUrl && opUrl != "null") {
                        echo "🔗 Monitoring Operation: ${opUrl}"
                        for(int i=0; i<15; i++) {
                            sleep 25
                            def statusRaw = sh(script: "curl -s -X GET '${opUrl}' -H 'Authorization: Bearer ${env.TOKEN}'", returnStdout: true)
                            if (statusRaw.contains("Succeeded")) {
                                echo "✅ SUCCESS! Report Updated In-place without deletion."
                                return
                            }
                        }
                    } else {
                        error "❌ API failed. Response: ${responseHeaders}"
                    }
                }
            }
        }
    }
    post {
        always {
            sh "rm -f definition.pbir payload.json"
        }
    }
}
