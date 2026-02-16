pipeline {
    agent any
    
    triggers {
        githubPush() 
    }

    environment {
        REPO_URL = "github.com/Prathmesh2806/Fabric-Automation.git"
        GITHUB_CREDENTIALS_ID = 'github-creds'
        TENANT_ID     = credentials('fabric-tenant-id')
        CLIENT_ID     = credentials('fabric-client-id')
        CLIENT_SECRET = credentials('fabric-client-secret')
    }

    stages {
        stage('Checkout & Detect Change') {
            steps {
                git branch: 'dev', credentialsId: "${GITHUB_CREDENTIALS_ID}", url: "https://${REPO_URL}"
                script {
                    def folder = sh(script: "git diff --name-only HEAD~1 | grep '/' | cut -d/ -f1 | head -1", returnStdout: true).trim()
                    if (!folder || folder == "Jenkinsfile") {
                        env.SKIP_DEPLOY = "true"
                        echo "⚠️ No customer folder changes detected."
                    } else {
                        env.CHANGED_FOLDER = folder
                        env.SKIP_DEPLOY = "false"
                        echo "Detected change in folder: ${env.CHANGED_FOLDER}"
                    }
                }
            }
        }

        stage('Validate & Get Token') {
            when { environment name: 'SKIP_DEPLOY', value: 'false' }
            steps {
                script {
                    def tokenResponse = sh(script: "curl -s -X POST https://login.microsoftonline.com/${TENANT_ID}/oauth2/v2.0/token -d 'grant_type=client_credentials&client_id=${CLIENT_ID}&client_secret=${CLIENT_SECRET}&scope=https://api.fabric.microsoft.com/.default'", returnStdout: true).trim()
                    def tokenJson = readJSON text: tokenResponse
                    env.FABRIC_TOKEN = tokenJson.access_token
                    echo "✅ Token generated!"
                }
            }
        }

        stage('Identify Target IDs') {
            when { environment name: 'SKIP_DEPLOY', value: 'false' }
            steps {
                script {
                    def suffix = env.CHANGED_FOLDER.split("-")[1] 
                    def targetWSName = "QA-${suffix}"
                    
                    def wsResponse = sh(script: "curl -s -X GET https://api.fabric.microsoft.com/v1/workspaces -H 'Authorization: Bearer ${env.FABRIC_TOKEN}'", returnStdout: true).trim()
                    def workspaces = readJSON text: wsResponse
                    def targetWS = workspaces.value.find { it.displayName == targetWSName }
                    if (!targetWS) { error "❌ Workspace ${targetWSName} not found!" }
                    env.TARGET_WS_ID = targetWS.id

                    def itemResponse = sh(script: "curl -s -X GET https://api.fabric.microsoft.com/v1/workspaces/${env.TARGET_WS_ID}/items -H 'Authorization: Bearer ${env.FABRIC_TOKEN}'", returnStdout: true).trim()
                    def items = readJSON text: itemResponse
                    def reportName = "Sales_Report_${suffix}"
                    def targetItem = items.value.find { it.displayName == reportName }
                    if (!targetItem) { error "❌ Item ${reportName} not found!" }
                    env.TARGET_ITEM_ID = targetItem.id
                }
            }
        }

        stage('Push to QA (API)') {
            when { environment name: 'SKIP_DEPLOY', value: 'false' }
            steps {
                script {
                    def suffix = env.CHANGED_FOLDER.split("-")[1]
                    def reportFolder = "${env.CHANGED_FOLDER}/Sales_Report_${suffix}.Report"
                    
                    def rptBase64 = sh(script: "base64 -w 0 ${reportFolder}/report.json", returnStdout: true).trim()
                    def pbirBase64 = sh(script: "base64 -w 0 ${reportFolder}/definition.pbir", returnStdout: true).trim()

                    def payload = [
                        definition: [
                            parts: [
                                [ path: "report.json", payload: rptBase64, payloadType: "InlineBase64" ],
                                [ path: "definition.pbir", payload: pbirBase64, payloadType: "InlineBase64" ]
                            ]
                        ]
                    ]
                    writeJSON file: 'payload.json', json: payload

                    def apiStatus = sh(script: "curl -s -o /dev/null -w '%{http_code}' -X POST 'https://api.fabric.microsoft.com/v1/workspaces/${env.TARGET_WS_ID}/items/${env.TARGET_ITEM_ID}/updateDefinition' -H 'Authorization: Bearer ${env.FABRIC_TOKEN}' -H 'Content-Type: application/json' -d @payload.json", returnStdout: true).trim()

                    if (apiStatus == "200" || apiStatus == "202") {
                        echo "🚀 Deployment Successful to ${targetWSName}!"
                    } else {
                        error "❌ Fabric API failed with status: ${apiStatus}"
                    }
                }
            }
        }
    }
    post {
        success { echo "🎉 Success!" }
        failure { echo "❌ Failed!" }
    }
}
