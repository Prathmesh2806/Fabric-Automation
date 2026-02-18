pipeline {
    agent any

    environment {
        // Fabric / Power BI Workspace & Item IDs
        WORKSPACE_ID  = 'afc6fad2-d19f-4f1b-bc5a-eb5f2caf40e6'
        CONNECTION_ID = '58d9731f-fa5f-419a-8619-1e987b11a916'
        DATASET_ID    = '5bd5e7ae-95ff-4251-8fd3-f6d14fa8439c'
    }

    stages {
        stage('Auth & Capacity Check') {
            steps {
                // 'github-creds' must be of type "Username with password" or "Microsoft Azure Service Principal"
                // If it's a Username/Password type, Username = ClientID, Password = ClientSecret
                withCredentials([usernamePassword(credentialsId: 'github-creds', 
                                                 usernameVariable: 'CLIENT_ID', 
                                                 passwordVariable: 'CLIENT_SECRET')]) {
                    script {
                        // Manually define your Tenant ID here if it's not part of the credential object
                        def tenant_id = "your-actual-tenant-id-here" 
                        
                        echo "🔑 Obtaining Access Token..."
                        def authResponse = sh(script: """
                            curl -s -X POST https://login.microsoftonline.com/${tenant_id}/oauth2/v2.0/token \
                            -d grant_type=client_credentials \
                            -d client_id=${CLIENT_ID} \
                            -d client_secret=${CLIENT_SECRET} \
                            -d scope=https://api.fabric.microsoft.com/.default
                        """, returnStdout: true).trim()
                        
                        def authJson = readJSON text: authResponse
                        env.FABRIC_TOKEN = authJson.access_token
                        echo "✅ Auth Successful."
                    }
                }
            }
        }

        stage('Deploy Semantic Model') {
            steps {
                script {
                    echo "📤 Uploading Model Definition to Fabric..."
                    // This assumes model_payload.json is generated in your workspace earlier
                    sh """
                        curl -i -s -X POST "https://api.fabric.microsoft.com/v1/workspaces/${WORKSPACE_ID}/items/${DATASET_ID}/updateDefinition" \
                        -H "Authorization: Bearer ${env.FABRIC_TOKEN}" \
                        -H "Content-Type: application/json" \
                        -d @model_payload.json
                    """
                    sleep 20
                }
            }
        }

        stage('Ownership & Connection Binding') {
            steps {
                script {
                    echo "👑 Taking Ownership (Takeover)..."
                    sh """
                        curl -s -X POST "https://api.powerbi.com/v1.0/myorg/groups/${WORKSPACE_ID}/datasets/${DATASET_ID}/Default.TakeOver" \
                        -H "Authorization: Bearer ${env.FABRIC_TOKEN}" \
                        -H "Content-Length: 0"
                    """
                    sleep 10

                    echo "🔗 Binding to Connection..."
                    def bindPayload = [gatewayObjectId: "${CONNECTION_ID}"]
                    writeJSON file: 'bind_payload.json', json: bindPayload
                    
                    sh """
                        curl -s -X POST "https://api.powerbi.com/v1.0/myorg/groups/${WORKSPACE_ID}/datasets/${DATASET_ID}/Default.BindToGateway" \
                        -H "Authorization: Bearer ${env.FABRIC_TOKEN}" \
                        -H "Content-Type: application/json" \
                        -d @bind_payload.json
                    """
                    sleep 5

                    echo "🔐 Patching Datasource Credentials to fix 'Undefined' connection..."
                    def dsResponse = sh(script: "curl -s -H 'Authorization: Bearer ${env.FABRIC_TOKEN}' https://api.powerbi.com/v1.0/myorg/groups/${WORKSPACE_ID}/datasets/${DATASET_ID}/datasources", returnStdout: true)
                    def dsJson = readJSON text: dsResponse
                    
                    def targetDsId = dsJson.value[0].datasourceId
                    def targetGwId = dsJson.value[0].gatewayId

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
                }
            }
        }

        stage('Refresh Data') {
            steps {
                script {
                    echo "🔄 Triggering Refresh..."
                    sh """
                        curl -s -X POST "https://api.powerbi.com/v1.0/myorg/groups/${WORKSPACE_ID}/datasets/${DATASET_ID}/refreshes" \
                        -H "Authorization: Bearer ${env.FABRIC_TOKEN}" \
                        -H "Content-Length: 0"
                    """
                }
            }
        }
    }

    post {
        always {
            sh "rm -f *_payload.json"
            echo "Cleanup complete."
        }
