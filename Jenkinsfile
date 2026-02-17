pipeline {
    agent any // Defining agent here ensures the workspace persists for post-actions
    
    environment {
        WORKSPACE_ID = "afc6fad2-d19f-4f1b-bc5a-eb5f2caf40e6"
        REPORT_NAME  = "Sales_Report_A"
        // Replace 'github-creds' with your actual Jenkins Credential ID for Azure/Fabric
        AZURE_CREDS = credentials('github-creds') 
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Get Access Token') {
            steps {
                script {
                    // Note the use of $AZURE_CREDS_PSW to avoid interpolation warnings
                    def tokenResponse = sh(script: """
                        curl -s -X POST https://login.microsoftonline.com/${TENANT_ID}/oauth2/v2.0/token \
                        -d grant_type=client_credentials \
                        -d client_id=${AZURE_CREDS_USR} \
                        -d client_secret=${AZURE_CREDS_PSW} \
                        -d scope=https://api.fabric.microsoft.com/.default
                    """, returnStdout: true)
                    def tokenJson = readJSON text: tokenResponse
                    env.FABRIC_TOKEN = tokenJson.access_token
                }
            }
        }

        stage('Find or Prep Item') {
            steps {
                script {
                    def itemsResponse = sh(script: """
                        curl -s -X GET https://api.fabric.microsoft.com/v1/workspaces/${WORKSPACE_ID}/items \
                        -H "Authorization: Bearer ${env.FABRIC_TOKEN}"
                    """, returnStdout: true)
                    
                    def itemsJson = readJSON text: itemsResponse
                    def existingItem = itemsJson.value.find { it.displayName == env.REPORT_NAME }
                    
                    if (existingItem) {
                        echo "🔍 Found existing report: ${env.REPORT_NAME} (ID: ${existingItem.id})"
                        env.ITEM_ID = existingItem.id
                        env.MODE = "UPDATE"
                    } else {
                        echo "🆕 Report not found. Switching to CREATE mode."
                        env.MODE = "CREATE"
                    }
                }
            }
        }

        stage('Deploy & Monitor') {
            steps {
                script {
                    def reportBase64 = sh(script: "base64 -w 0 Customer-A/Sales_Report_A.Report/report.json", returnStdout: true).trim()
                    def pbirBase64 = sh(script: "base64 -w 0 definition.pbir", returnStdout: true).trim()

                    def payload = [
                        displayName: env.REPORT_NAME,
                        type: "Report",
                        definition: [
                            parts: [
                                [path: "report.json", payload: reportBase64, payloadType: "InlineBase64"],
                                [path: "definition.pbir", payload: pbirBase64, payloadType: "InlineBase64"]
                            ]
                        ]
                    ]
                    writeJSON file: 'payload.json', json: payload

                    def apiEndpoint = (env.MODE == "UPDATE") ? 
                        "https://api.fabric.microsoft.com/v1/workspaces/${WORKSPACE_ID}/items/${env.ITEM_ID}/updateDefinition" : 
                        "https://api.fabric.microsoft.com/v1/workspaces/${WORKSPACE_ID}/items"

                    sh """
                        curl -i -s -X POST ${apiEndpoint} \
                        -H "Authorization: Bearer ${env.FABRIC_TOKEN}" \
                        -H "Content-Type: application/json" \
                        -d @payload.json > headers.txt
                    """

                    env.OPERATION_URL = sh(script: "grep -i 'location:' headers.txt | awk '{print \$2}' | tr -d '\\r'", returnStdout: true).trim()
                    
                    // Polling logic
                    if (env.OPERATION_URL) {
                        def status = "InProgress"
                        while (status == "InProgress" || status == "NotStarted") {
                            echo "⏳ Waiting for Fabric (Status: ${status})..."
                            sleep 20
                            def opResponse = sh(script: "curl -s -H 'Authorization: Bearer ${env.FABRIC_TOKEN}' ${env.OPERATION_URL}", returnStdout: true)
                            def opJson = readJSON text: opResponse
                            status = opJson.status
                            if (status == "Failed") error "❌ Fabric Error: ${opJson.error}"
                        }
                        echo "🚀 Success!"
                    }
                }
            }
        }
    }
    
    post {
        always {
            // This will now work because 'agent any' keeps the workspace context open
            sh "rm -f payload.json headers.txt"
        }
    }
}
