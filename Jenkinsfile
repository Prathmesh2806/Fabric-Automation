pipeline {
    agent any
    
    triggers {
        githubPush() // GitHub webhook trigger
    }

    environment {
        REPO_URL = "github.com/Prathmesh2806/Fabric-Automation.git"
        GITHUB_CREDENTIALS_ID = 'github-creds'
        
        // Jenkins Credentials (Secret Text) Manager madhun values uchat aahe
        TENANT_ID     = credentials('fabric-tenant-id')
        CLIENT_ID     = credentials('fabric-client-id')
        CLIENT_SECRET = credentials('fabric-client-secret')
    }

    stages {
        stage('Checkout & Detect Change') {
            steps {
                // Code download karne
                git branch: 'dev', credentialsId: "${GITHUB_CREDENTIALS_ID}", url: "https://${REPO_URL}"
                echo "✅ Code checked out from Dev branch."
                
                script {
                    // 1. Check karne kontya folder madhe change jhala (Jenkinsfile la ignore karun)
                    // 'grep /' mhanje fakt folder madhlya files filter karto
                    def folder = sh(script: "git diff --name-only HEAD~1 | grep '/' | cut -d/ -f1 | head -1", returnStdout: true).trim()
                    
                    if (!folder) {
                        echo "⚠️ Fakt Jenkinsfile kiva root files badallat. Customer folder madhe badal nahiye. Skipping Deploy."
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
                    // Report folder aahe ka check karne
                    echo "Validating structure for: ${env.CHANGED_FOLDER}"
                    sh "ls -R ${env.CHANGED_FOLDER} | grep '.Report' || (echo '❌ Error: Report folder missing!' && exit 1)"
                    
                    // Fabric Access Token ghene
                    echo "Fetching Fabric Access Token..."
                    def tokenResponse = sh(script: """
                        curl -s -X POST https://login.microsoftonline.com/${TENANT_ID}/oauth2/v2.0/token \
                        -d "grant_type=client_credentials&client_id=${CLIENT_ID}&client_secret=${CLIENT_SECRET}&scope=https://api.fabric.microsoft.com/.default"
                    """, returnStdout: true).trim()
                    
                    def tokenJson = readJSON text: tokenResponse
                    env.FABRIC_TOKEN = tokenJson.access_token
                    echo "✅ Validation successful and Token generated!"
                }
            }
        }

        stage('Identify Target IDs') {
            when { environment name: 'SKIP_DEPLOY', value: 'false' }
            steps {
                script {
                    // 1. Mapping logic: Customer-A -> QA-A
                    def suffix = env.CHANGED_FOLDER.split("-")[1] 
                    def targetWSName = "QA-${suffix}"
                    echo "Targeting Workspace: ${targetWSName}"

                    // 2. Resolve Workspace ID via API
                    def wsResponse = sh(script: "curl -s -X GET https://api.fabric.microsoft.com/v1/workspaces -H 'Authorization: Bearer ${env.FABRIC_TOKEN}'", returnStdout: true).trim()
                    def workspaces = readJSON text: wsResponse
                    def targetWS = workspaces.value.find { it.displayName == targetWSName }

                    if (!targetWS) { error "❌ Workspace ${targetWSName} Fabric madhe sapadla nahi!" }
                    env.TARGET_WS_ID = targetWS.id
                    echo "✅ Found Workspace ID: ${env.TARGET_WS_ID}"

                    // 3. Resolve Report Item ID
                    def itemResponse = sh(script: "curl -s -X GET https://api.fabric.microsoft.com/v1/workspaces/${env.TARGET_WS_ID}/items -H 'Authorization: Bearer ${env.FABRIC_TOKEN}'", returnStdout: true).trim()
                    def items = readJSON text: itemResponse
                    def targetItem = items.value.find { it.displayName == "Sales_Report_${suffix}" }
                    
                    if (!targetItem) { error "❌ Item 'Sales_Report_${suffix}' QA workspace madhe nahiye!" }
                    env.TARGET_ITEM_ID = targetItem.id
                    echo "✅ Found Report Item ID: ${env.TARGET_ITEM_ID}"
                }
            }
        }

        stage('Push to QA (API)') {
            when { environment name: 'SKIP_DEPLOY', value: 'false' }
            steps {
                script {
                    echo "Encoding files and pushing to Fabric..."
                    
                    def suffix = env.CHANGED_FOLDER.split("-")[1]
                    def reportFolder = "${env.CHANGED_FOLDER}/Sales_Report_${suffix}.Report"
                    
                    // Files la Base64 madhe convert karne
                    def reportJsonBase64 = sh(script: "base64 -w 0 ${reportFolder}/report.json", returnStdout: true).trim()
                    def pbirBase64 = sh(script: "base64 -w 0 ${reportFolder}/definition.pbir", returnStdout: true).trim()

                    // Final Update Definition API Call
                    def apiStatus = sh(script: """
                        curl -s -o /dev/null -w "%{http_code}" -X POST "https://api.fabric.microsoft.com/v1/workspaces/${env.TARGET_WS_ID}/items/${env.TARGET_ITEM_ID}/updateDefinition" \
                        -H "Authorization: Bearer ${env.FABRIC_TOKEN}" \
                        -H "Content-Type: application/json" \
                        -d '{
                            "parts": [
                                { "path": "report.json", "payload": "${reportJsonBase64}", "payloadType": "InlineBase64" },
                                { "path": "definition.pbir", "payload": "${pbirBase64}", "payloadType": "InlineBase64" }
                            ]
                        }'
                    """, returnStdout: true).trim()

                    if (apiStatus == "200" || apiStatus == "202") {
                        echo "🚀 Deployment Successful to ${env.TARGET_WS_ID}!"
                    } else {
                        error "❌ Fabric API failed with status: ${apiStatus}"
                    }
                }
            }
        }
    }

    post {
        success {
            echo "🎉 Job Success!"
        }
        failure {
            echo "❌ Job Failed. Check logs for details."
        }
    }
}
