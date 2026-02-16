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
                echo "✅ Code checked out from Dev branch."
                
                script {
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
                    def itemResponse =
