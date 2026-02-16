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
        stage('Cleanup & Get Dataset ID') {
            steps {
                script {
                    def itemsResponse = sh(script: "curl -s -X GET https://api.fabric.microsoft.com/v1/workspaces/${env.TARGET_WORKSPACE_ID}/items -H 'Authorization: Bearer ${env.TOKEN}'", returnStdout: true)
                    def itemsJson = readJSON text: itemsResponse
                    
                    def ds = itemsJson.value.find { it.displayName == env.DATASET_NAME }
                    if (!ds) { error "❌ Dataset '${env.DATASET_NAME}' सापडला नाही!" }
                    env.TARGET_DATASET_ID = ds.id

                    def rep = itemsJson.value.find { it.displayName == env.REPORT_NAME }
                    if (rep) {
                        sh "curl -s -X DELETE https://api.fabric.microsoft.com/v1/workspaces/${env.TARGET_WORKSPACE_ID}/items/${rep.id} -H 'Authorization: Bearer ${env.TOKEN}'"
                        echo "🧹 जुना रिपोर्ट हटवला. नवीन बनवण्याची तयारी सुरू..."
                        sleep 10
                    }
                }
            }
        }
        stage('Deploy & Track Operation') {
            steps {
                script {
                    def reportPath = "${env.DETECTED_FOLDER}/${env.REPORT_NAME}.Report/report.json"
                    def reportContent = sh(script: "base64 -w 0 ${reportPath}", returnStdout: true).trim()
                    
                    def createPayload = [
                        displayName: env.REPORT_NAME,
                        type: "Report",
                        definition: [
                            parts: [[path: "report.json", payload: reportContent, payloadType: "InlineBase64"]]
                        ],
                        relations: [[id: env.TARGET_DATASET_ID, type: "SemanticModel"]]
                    ]
                    writeJSON file: 'payload.json', json: createPayload

                    // POST Request - capturing headers to get Operation Location
                    def responseHeaders = sh(script: "curl -i -s -X POST https://api.fabric.microsoft.com/v1/workspaces/${env.TARGET_WORKSPACE_ID}/items -H 'Authorization: Bearer ${env.TOKEN}' -H 'Content-Type: application/json' -d @payload.json", returnStdout: true)
                    echo "Full Response Headers:\n${responseHeaders}"

                    def locationHeader = (responseHeaders =~ /location: (.*)/)
                    if (locationHeader) {
                        def opUrl = locationHeader[0][1].trim()
                        echo "🔍 Operation Track करतोय: ${opUrl}"
                        
                        // Wait and Poll status
                        for(int i=0; i<6; i++) {
                            echo "⏳ तपासत आहे (Attempt ${i+1})..."
                            sleep 15
                            def opStatus = sh(script: "curl -s -X GET ${opUrl} -H 'Authorization: Bearer ${env.TOKEN}'", returnStdout: true)
                            echo "Current Status: ${opStatus}"
                            if (opStatus.contains("Succeeded")) {
                                echo "✅ रिपोर्ट यशस्वीरित्या बनला!"
                                break
                            } else if (opStatus.contains("Failed")) {
                                error "❌ Fabric Operation Failed! नक्की काय चुकलंय ते वरच्या स्टेटसमध्ये बघा."
                            }
                        }
                    } else {
                        echo "⚠️ Operation URL सापडली नाही. डायरेक्ट लिस्ट चेक करा."
                    }
                }
            }
        }
    }
}
