pipeline {
    agent any
    
    environment {
        // GUIDs from your log
        WORKSPACE_ID = "afc6fad2-d19f-4f1b-bc5a-eb5f2caf40e6"
        REPORT_NAME  = "Sales_Report_A"
        CREDENTIALS_ID = 'github-creds'
        // Service Principal Secret IDs
        AZURE_CREDS = credentials('your-azure-creds-id') 
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
                    def tokenResponse = sh(script: """
                        curl -s -X POST https://login.microsoftonline.com/${TENANT_ID}/oauth2/v2.0/token \
                        -d grant_type=client_credentials \
                        -d client_id=${CLIENT_ID} \
                        -d client_secret=${CLIENT_SECRET} \
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
                    // 1. Get all items in workspace
                    def itemsResponse = sh(script: """
                        curl -s -X GET https://api.fabric.microsoft.com/v1/workspaces/${WORKSPACE_ID}/items \
                        -H "Authorization: Bearer ${env.FABRIC_TOKEN}"
                    """, returnStdout: true)
                    
                    def itemsJson = readJSON text: itemsResponse
                    // 2. Search for the report by name
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

        stage('Deploy to Fabric') {
            steps {
                script {
                    // Prepare Base64 payloads
                    def reportBase64 = sh(script: "base64 -w 0 Customer-A/Sales_Report_A.Report/report.json", returnStdout: true).trim()
                    def pbirBase64 = sh(script: "base64 -w 0 definition.pbir", returnStdout: true).trim()

                    // Construct Payload
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

                    def apiEndpoint = ""
                    def httpMethod = ""

                    if (env.MODE == "UPDATE") {
                        // Use Update Definition API
                        apiEndpoint = "https://api.fabric.microsoft.com/v1/workspaces/${WORKSPACE_ID}/items/${env.ITEM_ID}/updateDefinition"
                        httpMethod = "POST" 
                    } else {
                        // Use Create Item API
                        apiEndpoint = "https://api.fabric.microsoft.com/v1/workspaces/${WORKSPACE_ID}/items"
                        httpMethod = "POST"
                    }

                    // Execute Deployment
                    def responseHeaders = sh(script: """
                        curl -i -s -X ${httpMethod} ${apiEndpoint} \
                        -H "Authorization: Bearer ${env.FABRIC_TOKEN}" \
                        -H "Content-Type: application/json" \
                        -d @payload.json > headers.txt
                    """, returnStatus: true)

                    // Extract Operation ID for polling
                    env.OPERATION_URL = sh(script: "grep -i 'location:' headers.txt | awk '{print \$2}' | tr -d '\\r'", returnStdout: true).trim()
                    echo "🔗 Monitoring Operation: ${env.OPERATION_URL}"
                }
            }
        }

        stage('Monitor Operation') {
            steps {
                script {
                    if (!env.OPERATION_URL) {
                        echo "✅ No background operation required (already finished)."
                        return
                    }

                    def status = "InProgress"
                    while (status == "InProgress" || status == "NotStarted") {
                        echo "⏳ Waiting for Fabric to finish deployment..."
                        sleep 15
                        def opResponse = sh(script: "curl -s -H 'Authorization: Bearer ${env.FABRIC_TOKEN}' ${env.OPERATION_URL}", returnStdout: true)
                        def opJson = readJSON text: opResponse
                        status = opJson.status
                        
                        if (status == "Failed") {
                            error "❌ Fabric Deployment Failed: ${opJson.error}"
                        }
                    }
                    echo "🚀 Deployment Successful! Status: ${status}"
                }
            }
        }
    }
    
    post {
        always {
            sh "rm -f payload.json headers.txt"
        }
    }
}
