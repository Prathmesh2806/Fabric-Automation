import groovy.transform.NonCPS

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
                    if (!ds) { error "❌ Dataset sapḍalā nāhī!" }
                    env.TARGET_DATASET_ID = ds.id

                    def rep = itemsJson.value.find { it.displayName == env.REPORT_NAME }
                    if (rep) {
                        sh "curl -s -X DELETE https://api.fabric.microsoft.com/v1/workspaces/${env.TARGET_WORKSPACE_ID}/items/${rep.id} -H 'Authorization: Bearer ${env.TOKEN}'"
                        sleep 5
                    }
                }
            }
        }
        stage('Deploy & Track') {
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

                    def responseHeaders = sh(script: "curl -i -s -X POST https://api.fabric.microsoft.com/v1/workspaces/${env.TARGET_WORKSPACE_ID}/items -H 'Authorization: Bearer ${env.TOKEN}' -H 'Content-Type: application/json' -d @payload.json", returnStdout: true)
                    
                    // Call the NonCPS function to extract URL safely
                    String opUrl = getOperationUrl(responseHeaders)
                    
                    if (opUrl) {
                        echo "🔍 Operation Track kartōy: ${opUrl}"
                        for(int i=0; i<5; i++) {
                            echo "⏳ Check karūn pāhtōy... (Attempt ${i+1})"
                            sleep 20
                            def statusRaw = sh(script: "curl -s -X GET ${opUrl} -H 'Authorization: Bearer ${env.TOKEN}'", returnStdout: true)
                            echo "Status: ${statusRaw}"
                            if (statusRaw.contains("Succeeded")) {
                                echo "✅ SUCCESS! Report UI madhe dhisala pahije."
                                return
                            } else if (statusRaw.contains("Failed")) {
                                error "❌ Fabric Failure: ${statusRaw}"
                            }
                        }
                    } else {
                        echo "⚠️ Operation URL sapḍalī nāhī, 30 sec thāmbūn Workspace check karā."
                        sleep 30
                    }
                }
            }
        }
    }
}

@NonCPS
def getOperationUrl(String headers) {
    def matcher = (headers =~ /location: (.*)/)
    if (matcher) {
        return matcher[0][1].trim()
    }
    return null
}
