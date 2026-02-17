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
                    echo "🎯 Target Dataset ID (GUID): ${env.TARGET_DATASET_ID}"

                    def rep = itemsJson.value.find { it.displayName == env.REPORT_NAME }
                    if (rep) {
                        echo "🧹 Removing existing report..."
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
                    def reportContent = sh(script: "base64 -w 0 ${folderPath}/report.json", returnStdout: true).trim()
                    
                    // FIXED PBIR SCHEMA: GUID is passed in pbiModelDatabaseName as required by the error.
                    // Also included pbiServiceModelId with the same GUID.
                    def pbirJson = """{
  "version": "1.0",
  "datasetReference": {
    "byConnection": {
      "connectionString": null,
      "pbiServiceXml": null,
      "pbiModelVirtualPath": null,
      "pbiModelDatabaseName": "${env.TARGET_DATASET_ID}",
      "name": "EntityDataSource",
      "pbiServiceModelId": "${env.TARGET_DATASET_ID}",
      "pbiModelVirtualServerName": null,
      "connectionType": "pbiServiceXml"
    }
  }
}"""
                    
                    def pbirBase64 = sh(script: "echo '${pbirJson}' | base64 -w 0", returnStdout: true).trim()
                    
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

                    echo "🚀 Deploying with Validated GUID Schema..."
                    
                    def curlCmd = "curl -i -s -X POST https://api.fabric.microsoft.com/v1/workspaces/${env.TARGET_WORKSPACE_ID}/items " +
                                  "-H 'Authorization: Bearer ${env.TOKEN}' " +
                                  "-H 'Content-Type: application/json' -d @payload.json"
                    
                    def responseHeaders = sh(script: curlCmd, returnStdout: true)
                    def opUrl = sh(script: "echo \"${responseHeaders}\" | grep -i 'location:' | cut -d' ' -f2", returnStdout: true).trim()
                    
                    if (opUrl) {
                        for(int i=0; i<10; i++) {
                            echo "⏳ Attempt ${i+1}: Monitoring Fabric Operation..."
                            sleep 20
                            def statusRaw = sh(script: "curl -s -X GET ${opUrl} -H 'Authorization: Bearer ${env.TOKEN}'", returnStdout: true)
                            def statusJson = readJSON text: statusRaw
                            
                            if (statusJson.status == "Succeeded") {
                                echo "✅ SUCCESS! Project Complete."
                                return
                            } else if (statusJson.status == "Failed") {
                                echo "❌ Error Details: ${statusRaw}"
                                error "❌ Fabric Deployment Failed."
                            }
                        }
                    } else {
                        error "❌ Operation URL not found. Check API Response."
                    }
                }
            }
        }
    }
}
