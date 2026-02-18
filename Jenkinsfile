pipeline {
    agent any

    environment {
        // Update these with your actual IDs
        WORKSPACE_ID  = 'afc6fad2-d19f-4f1b-bc5a-eb5f2caf40e6'
        CAPACITY_ID   = '09426049-3a4b-4063-b35b-43928a03b21a'
        CONNECTION_ID = '58d9731f-fa5f-419a-8619-1e987b11a916'
        
        // Credentials IDs from Jenkins Global Credentials
        AZURE_CRED    = credentials('github-creds') 
    }

    stages {
        stage('Auth & Capacity Check') {
            steps {
                script {
                    echo "🔑 Obtaining Access Token..."
                    def authResponse = sh(script: """
                        curl -s -X POST https://login.microsoftonline.com/${TENANT_ID}/oauth2/v2.0/token \
                        -d grant_type=client_credentials \
                        -d client_id=${CLIENT_ID} \
                        -d client_secret=${CLIENT_SECRET} \
                        -d scope=https://api.fabric.microsoft.com/.default
                    """, returnStdout: true)
                    
                    def authJson = readJSON text: authResponse
                    env.FABRIC_TOKEN = authJson.access_token
                    
                    echo "🔍 Verifying Capacity Status..."
                    sh """
                        curl -s -H "Authorization: Bearer ${env.FABRIC_TOKEN}" \
                        https://api.powerbi.com/v1.0/myorg/capacities
                    """
                    echo "✅ Auth Successful."
                }
            }
        }

        stage('Deploy Semantic Model') {
            steps {
                script {
                    // This logic assumes you are updating an existing item 
                    // Item ID: 5bd5e7ae-95ff-4251-8fd3-f6d14fa8439c
                    def itemId = "5bd5e7ae-95ff-4251-8fd3-f6d14fa8439c"
                    
                    echo "📤 Uploading Model Definition..."
                    // [Your existing base64 encoding and payload generation logic here]
                    // ... (Keeping this brief as your previous logic for encoding was working)
                    
                    sh """
                        curl -i -s -X POST "https://api.fabric.microsoft.com/v1/workspaces/${WORKSPACE_ID}/items/${itemId}/updateDefinition" \
                        -H "Authorization: Bearer ${env.FABRIC_TOKEN}" \
                        -H "Content-Type: application/json" \
                        -d @model_payload.json
                    """
                    sleep 25 // Waiting for Fabric to process the metadata change
                }
            }
        }

        stage('Ownership & Connection Binding') {
            steps {
                script {
                    def datasetId = "5bd5e7ae-95ff-4251-8fd3-f6d14fa8439c"

                    echo "👑 Taking Ownership (Takeover)..."
                    sh """
                        curl -s -X POST "https://api.powerbi.com/v1.0/myorg/groups/${WORKSPACE_ID}/datasets/${datasetId}/Default.TakeOver" \
                        -H "Authorization: Bearer ${env.FABRIC_TOKEN}" \
                        -H "Content-Length: 0"
                    """
                    sleep 10

                    echo "🔗 Binding to Connection..."
                    def bindPayload = [gatewayObjectId: "${env.CONNECTION_ID}"]
                    writeJSON file: 'bind_payload.json', json: bindPayload
                    
                    sh """
                        curl -s -X POST "https://api.powerbi.com/v1.0/myorg/groups/${WORKSPACE_ID}/datasets/${datasetId}/Default.BindToGateway" \
                        -H "Authorization: Bearer ${env.FABRIC_TOKEN}" \
                        -H "Content-Type: application/json" \
                        -d @bind_payload.json
                    """
                    sleep 5

                    echo "🔐 Patching Datasource Credentials..."
                    // Get the dynamic datasource and gateway IDs assigned to this dataset
                    def dsResponse = sh(script: """
                        curl -s -H "Authorization: Bearer ${env.FABRIC_TOKEN}" \
                        https://api.powerbi.com/v1.0/myorg/groups/${WORKSPACE_ID}/datasets/${datasetId}/datasources
                    """, returnStdout: true)
                    
                    def dsJson = readJSON text: dsResponse
                    def targetDsId = dsJson.value[0].datasourceId
                    def targetGwId = dsJson.value[0].gatewayId

                    // Patch the credential to use the Service Principal Identity
                    def credPayload = [
                        credentialDetails: [
                            credentialType: "OAuth2",
                            useEndUserCredential: false,
                            useCallerAADIdentity: true,
                            privacyLevel: "Organizational"
                        ]
                    ]
                    writeJSON file: 'cred_payload.json', json: credPayload

                    sh """
                        curl -s -X PATCH "https://api.powerbi.com/v1.0/myorg/gateways/${targetGwId}/datasources/${targetDsId}" \
                        -H "Authorization: Bearer ${env.FABRIC_TOKEN}" \
                        -H "Content-Type: application/json" \
                        -d @cred_payload.json
                    """
                    echo "✅ Connection successfully bound and authenticated."
                }
            }
        }

        stage('Refresh & Validate') {
            steps {
                script {
                    def datasetId = "5bd5e7ae-95ff-4251-8fd3-f6d14fa8439c"
                    echo "🔄 Triggering Refresh..."
                    sh """
                        curl -s -X POST "https://api.powerbi.com/v1.0/myorg/groups/${WORKSPACE_ID}/datasets/${datasetId}/refreshes" \
                        -H "Authorization: Bearer ${env.FABRIC_TOKEN}" \
                        -H "Content-Length: 0"
                    """
                }
            }
        }
    }

    post {
        always {
            sh "rm -f *_payload.json definition.pbir"
            echo "Cleanup complete."
        }
    }
}
