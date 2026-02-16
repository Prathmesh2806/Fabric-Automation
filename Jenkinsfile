pipeline {
    agent any
    
    triggers {
        githubPush() // GitHub webhook trigger sathi
    }

    environment {
        REPO_URL = "github.com/Prathmesh2806/Fabric-Automation.git"
        GITHUB_CREDENTIALS_ID = 'github-creds'
        
        // Jenkins Credentials (Secret Text) madhun values uchat aahe
        TENANT_ID     = credentials('fabric-tenant-id')
        CLIENT_ID     = credentials('fabric-client-id')
        CLIENT_SECRET = credentials('fabric-client-secret')
    }

    stages {
        stage('Checkout & Detect Change') {
            steps {
                git branch: 'dev', credentialsId: "${GITHUB_CREDENTIALS_ID}", url: "https://${REPO_URL}"
                echo "✅ Code checked out from Dev branch."
                
                script {
                    // Git diff vaprun kontya folder madhe badal aahe te shodha
                    def folder = sh(script: "git diff --name-only HEAD~1 | grep '/' | cut -d/ -f1 | head -1", returnStdout: true).trim()
                    
                    if (!folder || folder == "Jenkinsfile") {
                        echo "⚠️ No customer folder changes detected. Skipping deployment."
                        env.SKIP_DEPLOY = "true"
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
                    echo "Validating structure for: ${env.CHANGED_FOLDER}"
                    sh "ls -R ${env.CHANGED_FOLDER} | grep '.Report' || (echo '❌ Error: Report folder missing!' && exit 1)"
                    
                    echo "Fetching Fabric Access Token..."
                    def tokenResponse = sh(script: """
                        curl -s -X POST https://login.microsoftonline.com/${TENANT_ID}/oauth2/v2.0/token \
                        -d "grant_type=client_credentials&client_id=${CLIENT_ID}&client_secret=${CLIENT_SECRET}&scope=https://api.fabric.microsoft.com/.default"
                    """, returnStdout: true).trim()
                    
                    def tokenJson = readJSON text: tokenResponse
                    env.FABRIC_TOKEN = tokenJson.access_token
                    echo "✅ Token generated successfully!"
                }
            }
        }

        stage('Identify Target IDs') {
            when { environment name: 'SKIP_DEPLOY', value: 'false' }
            steps {
                script {
                    // Mapping: Customer-A -> QA-A
                    def suffix = env.CHANGED_FOLDER.split("-")[1] 
                    def targetWSName = "QA-${suffix}"
                    echo "Targeting Workspace: ${targetWSName}"

                    // 1. Resolve Workspace ID
                    def wsResponse = sh(script: "curl -s -X GET https://api.fabric.microsoft.com/v1/workspaces -H 'Authorization: Bearer ${env.FABRIC_TOKEN}'", returnStdout: true).trim()
                    def workspaces = readJSON text: wsResponse
                    def targetWS = workspaces.value.find { it.displayName == targetWSName }

                    if (!targetWS) { error "❌ Workspace ${targetWSName} sapadla nahi!" }
                    env.TARGET_WS_ID = targetWS.id
                    echo "✅ Found Workspace ID: ${env.TARGET_WS_ID}"

                    // 2. Resolve Report Item ID
                    def itemResponse = sh(script: "curl -s -X GET https://api.fabric.microsoft.com/v1/workspaces/${env.TARGET_WS_ID}/items -H 'Authorization: Bearer ${env.FABRIC_TOKEN}'", returnStdout: true).trim()
                    def items = readJSON text: itemResponse
                    def reportName = "Sales_Report_${suffix}"
                    def targetItem = items.value.find { it.displayName == reportName }
                    
                    if (!targetItem) { error "❌ Item ${reportName} QA workspace madhe nahiye!" }
                    env.TARGET_ITEM_ID = targetItem.id
                    echo "✅ Found Report Item ID: ${env.TARGET_ITEM_ID}"
                }
            }
        }

        stage('Push to QA (API)') {
            when { environment name: 'SKIP_DEPLOY', value: 'false' }
            steps {
                script {
                    echo "Encoding files and creating payload..."
                    
                    def suffix = env.CHANGED_FOLDER.split("-")[1]
                    def reportFolder = "${env.CHANGED_FOLDER}/Sales_Report_${suffix}.Report"
                    
                    // Base64 Conversion
                    def reportJsonBase64 = sh(script: "base64 -w 0 ${reportFolder}/report.json", returnStdout: true).trim()
                    def pbirBase64 = sh(script: "base64 -w 0 ${reportFolder}/definition.pbir", returnStdout: true).trim()

                    // Temporary Payload JSON file banvane (Corruption talnyasathi)
                    def payload = [
                        parts: [
                            [ path: "report.json", payload: reportJsonBase64, payloadType: "InlineBase64" ],
                            [ path: "definition.pbir", payload: pbirBase64, payloadType: "InlineBase64" ]
                        ]
                    ]
                    writeJSON file: 'payload.json', json: payload

                    echo "Pushing payload to Fabric API..."
                    def apiStatus = sh(script: """
                        curl -s -o /dev/null -w "%{http_code}" -X POST "https://api.fabric.microsoft.com/v1/workspaces/${env.TARGET_WS_ID}/items/${env.TARGET_ITEM_ID}/updateDefinition" \
                        -H "Authorization: Bearer ${env.FABRIC_TOKEN}" \
                        -H "Content-Type: application/json" \
                        -d @payload.json
                    """, returnStdout: true).trim()

                    if (apiStatus == "200" || apiStatus == "202") {
                        echo "🚀 Deployment Successful to ${env.CHANGED_FOLDER.split("-")[1]} QA Workspace!"
                    } else {
                        // Jar fail jhale tar error response print kara
                        def errorLog = sh(script: "curl -s -X POST 'https://api.fabric.microsoft.com/v1/workspaces/${env.TARGET_WS_ID}/items/${env.TARGET_ITEM_ID}/updateDefinition' -H 'Authorization: Bearer ${env.FABRIC_TOKEN}' -H 'Content-Type: application/json' -d @payload.json", returnStdout: true).trim()
                        echo "Detailed Error: ${errorLog}"
                        error "❌ Fabric API failed with status: ${apiStatus}"
                    }
                }
            }
        }
    }

    post {
        success { echo "🎉 Sagle kaam fattesik jhale!" }
        failure { echo "❌ Kahiतरी chukle aahe, logs check kara." }
    }
}
