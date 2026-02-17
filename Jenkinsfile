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
                    git branch: 'dev', credentialsId: 'github-creds', url: 'https://github.com/Prathmesh2806/Fabric-Automation.git'
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

        stage('Prep Target & Check Existence') {
            steps {
                script {
                    // Fetch all items to find both the Dataset and the existing Report
                    def itemsResponse = sh(script: "curl -s -X GET https://api.fabric.microsoft.com/v1/workspaces/${env.TARGET_WORKSPACE_ID}/items -H 'Authorization: Bearer ${env.TOKEN}'", returnStdout: true)
                    def itemsJson = readJSON text: itemsResponse

                    // 1. Find the Dataset GUID (Your existing logic)
                    def ds = itemsJson.value.find { it.displayName == env.DATASET_NAME }
                    if (!ds) { error "❌ Dataset '${env.DATASET_NAME}' not found!" }
                    env.TARGET_DATASET_ID = ds.id

                    // 2. NEW: Check if the Report already exists
                    def existingReport = itemsJson.value.find { it.displayName == env.REPORT_NAME && it.type == "Report" }
                    if (existingReport) {
                        env.EXISTING_REPORT_ID = existingReport.id
                        env.IS_UPDATE = "true"
                        echo "🔍 Found existing report (ID: ${env.EXISTING_REPORT_ID}). Switching to UPDATE mode."
                    } else {
                        env.IS_UPDATE = "false"
                        echo "🆕 Report not found. Switching to CREATE mode."
                    }
                }
            }
        }

        stage('Deploy Report') {
            steps {
                script {
                    def folderPath = "${env.DETECTED_FOLDER}/${env.REPORT_NAME}.Report"
                    def reportContent = sh(script: "base64 -w 0 ${folderPath}/report.json", returnStdout: true).trim()

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

                    def deployPayload = [
                        displayName: env.REPORT_NAME,
                        type: "Report",
                        definition: [
                            parts: [
                                [path: "report.json", payload: reportContent, payloadType: "InlineBase64"],
                                [path: "definition.pbir", payload: pbirBase64, payloadType: "InlineBase64"]
                            ]
                        ]
                    ]
                    writeJSON file: 'payload.json', json: deployPayload

                    // Logic to decide API endpoint
                    def apiUrl = ""
                    if (env.IS_UPDATE == "true") {
                        // API to OVERWRITE existing report
                        apiUrl = "https://api.fabric.microsoft.com/v1/workspaces/${env.TARGET_WORKSPACE_ID}/items/${env.EXISTING_REPORT_ID}/updateDefinition"
                    } else {
                        // API to CREATE new report
                        apiUrl = "https://api.fabric.microsoft.com/v1/workspaces/${env.TARGET_WORKSPACE_ID}/items"
                    }

                    def curlCmd = "curl -i -s -X POST ${apiUrl} -H 'Authorization: Bearer ${env.TOKEN}' -H 'Content-Type: application/json' -d @payload.json"
                    def responseHeaders = sh(script: curlCmd, returnStdout: true)

                    def opUrl = sh(script: "echo '${responseHeaders}' | grep -i 'location:' | awk '{print \$2}' | tr -d '\\r'", returnStdout: true).trim()

                    if (opUrl && opUrl != "null") {
                        echo "🔗 Operation URL: ${opUrl}"
                        for(int i=0; i<15; i++) {
                            echo "⏳ Monitoring (Attempt ${i + 1})..."
                            sleep 25
                            def statusRaw = sh(script: "curl -s -X GET '${opUrl}' -H 'Authorization: Bearer ${env.TOKEN}'", returnStdout: true)
                            
                            if (statusRaw.contains("Succeeded")) {
                                echo "✅ SUCCESS! Deployment Complete."
                                return
                            } else if (statusRaw.contains("Failed")) {
                                error "❌ Fabric Error: ${statusRaw}"
                            }
                        }
                    } else {
                        error "❌ Deployment Start Failed: ${responseHeaders}"
                    }
                }
            }
        }
    }

    post {
        always {
            script {
                sh "rm -f definition.pbir payload.json"
            }
        }
    }
}
