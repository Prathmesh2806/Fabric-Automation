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
                script {
                    // GitHub repo checkout
                    git branch: 'dev', credentialsId: 'github-creds', url: 'https://github.com/Prathmesh2806/Fabric-Automation.git'
                    
                    // Configuration - Adjust these as per your project
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

        stage('Prep Target Dataset') {
            steps {
                script {
                    // Find the Dataset GUID in the target workspace
                    def itemsResponse = sh(script: "curl -s -X GET https://api.fabric.microsoft.com/v1/workspaces/${env.TARGET_WORKSPACE_ID}/items -H 'Authorization: Bearer ${env.TOKEN}'", returnStdout: true)
                    def itemsJson = readJSON text: itemsResponse
                    def ds = itemsJson.value.find { it.displayName == env.DATASET_NAME }
                    
                    if (!ds) { 
                        error "❌ Dataset '${env.DATASET_NAME}' not found in target workspace!" 
                    }
                    
                    env.TARGET_DATASET_ID = ds.id
                    echo "🎯 Target Dataset GUID: ${env.TARGET_DATASET_ID}"
                }
            }
        }

        stage('Deploy Report') {
            steps {
                script {
                    def folderPath = "${env.DETECTED_FOLDER}/${env.REPORT_NAME}.Report"
                    
                    // 1. report.json base64
                    def reportContent = sh(script: "base64 -w 0 ${folderPath}/report.json", returnStdout: true).trim()
                    
                    // 2. definition.pbir (Binding logic)
                    // Fixed: Moving GUID to pbiModelDatabaseName as per Fabric Error errorCode: InvalidConnectionInformation
                    def pbirJson = """{
                      "version": "1.0",
                      "datasetReference": {
                        "byConnection":
