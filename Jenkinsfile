pipeline {
    agent any

    environment {
        CLIENT_ID        = credentials('fabric-client-id')
        CLIENT_SECRET    = credentials('fabric-client-secret')
        TENANT_ID        = credentials('fabric-tenant-id')

        WORKSPACE_ID      = "afc6fad2-d19f-4f1b-bc5a-eb5f2caf40e6"
        SEMANTIC_MODEL_ID = "5bd5e7ae-95ff-4251-8fd3-f6d14fa8439c"

        REPORT_NAME   = "Sales_Report_A"
        DATASET_NAME  = "Sales_Model_A"

        MODEL_FOLDER  = "Customer-A/Sales_Model_A.SemanticModel"
        REPORT_FOLDER = "Customer-A/Sales_Report_A.Report"

        QA_CONNECTION_ID = "7d3a6d82-0f86-42b0-9c98-84610e10ff95"
    }

    stages {

        stage('Checkout') {
            steps {
                git branch: 'dev',
                    credentialsId: 'github-creds',
                    url: 'https://github.com/Prathmesh2806/Fabric-Automation.git'
            }
        }

        stage('Get Token') {
            steps {
                script {
                    def tokenResponse = sh(script: """
                        curl -s -X POST https://login.microsoftonline.com/${TENANT_ID}/oauth2/v2.0/token \
                        -d grant_type=client_credentials \
                        -d client_id=${CLIENT_ID} \
                        -d client_secret=${CLIENT_SECRET} \
                        -d scope=https://api.fabric.microsoft.com/.default
                    """, returnStdout: true)

                    env.TOKEN = readJSON(text: tokenResponse).access_token
                }
            }
        }

        stage('Get Lakehouse') {
            steps {
                script {
                    def itemsResp = sh(script: """
                        curl -s -H 'Authorization: Bearer ${env.TOKEN}' \
                        https://api.fabric.microsoft.com/v1/workspaces/${env.WORKSPACE_ID}/items
                    """, returnStdout: true)

                    def lakehouse = readJSON(text: itemsResp).value.find { it.type == "Lakehouse" }
                    if (!lakehouse) error "❌ No Lakehouse found!"

                    env.LAKEHOUSE_ID  = lakehouse.id
                    env.LAKEHOUSE_URL = "https://onelake.dfs.fabric.microsoft.com/${env.WORKSPACE_ID}/${env.LAKEHOUSE_ID}/"
                }
            }
        }

        stage('Deploy Semantic Model') {
            steps {
                script {

                    sh """
                        FILE_PATH="${env.MODEL_FOLDER}/definition/expressions.tmdl"
                        sed -i 's|https://onelake.dfs.fabric.microsoft.com/.*"|${env.LAKEHOUSE_URL}"|g' \$FILE_PATH
                        sed -i 's/expression EnvironmentName = "DEV"/expression EnvironmentName = "QA"/g' \$FILE_PATH
                    """

                    def pbismBase64 = sh(script: "base64 -w 0 ${env.MODEL_FOLDER}/definition.pbism", returnStdout: true).trim()

                    def parts = [[path: "definition.pbism", payload: pbismBase64, payloadType: "InlineBase64"]]

                    def tmdlFiles = sh(script: "find ${env.MODEL_FOLDER}/definition -name '*.tmdl'", returnStdout: true).split()

                    tmdlFiles.each { filePath ->
                        def relativePath = filePath.substring(filePath.indexOf("definition/"))
                        def fileBase64 = sh(script: "base64 -w 0 ${filePath}", returnStdout: true).trim()
                        parts << [path: relativePath, payload: fileBase64, payloadType: "InlineBase64"]
                    }

                    writeJSON file: 'model_payload.json', json: [
                        displayName: env.DATASET_NAME,
                        type: "SemanticModel",
                        definition: [parts: parts]
                    ]

                    def responseHeaders = sh(script: """
                        curl -i -s -X POST \
                        https://api.fabric.microsoft.com/v1/workspaces/${env.WORKSPACE_ID}/items/${env.SEMANTIC_MODEL_ID}/updateDefinition \
                        -H 'Authorization: Bearer ${env.TOKEN}' \
                        -H 'Content-Type: application/json' \
                        -d @model_payload.json
                    """, returnStdout: true)

                    def opUrl = sh(script: "echo '${responseHeaders}' | grep -i 'location:' | awk '{print \$2}' | tr -d '\\r'", returnStdout: true).trim()

                    if (!opUrl) error "❌ Model deployment failed to start."

                    while (true) {
                        sleep 15
                        def statusRaw = sh(script: "curl -s -H 'Authorization: Bearer ${env.TOKEN}' ${opUrl}", returnStdout: true)
                        def statusJson = readJSON(text: statusRaw)

                        if (statusJson.status == "Succeeded") break
                        if (statusJson.status == "Failed") error "❌ Model Deployment Failed: ${statusRaw}"
                    }
                }
            }
        }

        stage('Deploy Report') {
            steps {
                script {

                    def reportContent = sh(script: "base64 -w 0 ${env.REPORT_FOLDER}/report.json", returnStdout: true).trim()

                    def pbirJson = """{
                      "version": "1.0",
                      "datasetReference": {
                        "byConnection": {
                          "pbiModelDatabaseName": "${env.SEMANTIC_MODEL_ID}",
                          "name": "EntityDataSource",
                          "connectionType": "pbiServiceXml"
                        }
                      }
                    }"""

                    writeFile file: 'definition.pbir', text: pbirJson
                    def pbirBase64 = sh(script: "base64 -w 0 definition.pbir", returnStdout: true).trim()

                    def deployPayload = [
                        displayName: env.REPORT_NAME,
                        type: "Report",
                        definition: [
                            parts: [
                                [path: "report.json", payload: reportContent, payloadType: "InlineBase64"],
                                [path: "definition.pbir", payload: pbirBase64, payloadType: "InlineBase64"]
                            ]
                        ]
                    ]

                    writeJSON file: 'report_payload.json', json: deployPayload

                    sh """
                        curl -s -X POST \
                        https://api.fabric.microsoft.com/v1/workspaces/${env.WORKSPACE_ID}/items \
                        -H 'Authorization: Bearer ${env.TOKEN}' \
                        -H 'Content-Type: application/json' \
                        -d @report_payload.json
                    """
                }
            }
        }

        stage('TakeOver + Bind + Refresh') {
            steps {
                script {

                    echo "👑 Taking Ownership..."

                    sh """
                    curl -s -X POST \
                    https://api.powerbi.com/v1.0/myorg/groups/${env.WORKSPACE_ID}/datasets/${env.SEMANTIC_MODEL_ID}/Default.TakeOver \
                    -H "Authorization: Bearer ${env.TOKEN}" \
                    -H "Content-Length: 0"
                    """

                    sleep 5

                    echo "🔗 Binding Connection..."

                    def dsPayload = [
                        updateDetails: [[
                            datasourceSelector: [
                                datasourceType: "AzureDataLakeStorage",
                                connectionDetails: [
                                    path: env.LAKEHOUSE_URL
                                ]
                            ],
                            connectionId: env.QA_CONNECTION_ID
                        ]]
                    ]

                    writeJSON file: 'ds_payload.json', json: dsPayload

                    def bindResp = sh(script: """
                    curl -s -X POST \
                    https://api.powerbi.com/v1.0/myorg/groups/${env.WORKSPACE_ID}/datasets/${env.SEMANTIC_MODEL_ID}/Default.UpdateDatasources \
                    -H "Authorization: Bearer ${env.TOKEN}" \
                    -H "Content-Type: application/json" \
                    -d @ds_payload.json
                    """, returnStdout: true)

                    echo "Bind Response: ${bindResp}"

                    echo "🔄 Refreshing..."

                    sh """
                    curl -s -X POST \
                    https://api.powerbi.com/v1.0/myorg/groups/${env.WORKSPACE_ID}/datasets/${env.SEMANTIC_MODEL_ID}/refreshes \
                    -H "Authorization: Bearer ${env.TOKEN}" \
                    -H "Content-Type: application/json" \
                    -d '{"type":"Full"}'
                    """
                }
            }
        }
    }

    post {
        always {
            sh "rm -f model_payload.json report_payload.json ds_payload.json definition.pbir"
        }
    }
}
 
