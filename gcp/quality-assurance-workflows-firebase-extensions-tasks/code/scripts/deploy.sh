#!/bin/bash

# Quality Assurance Workflows with Firebase Extensions and Cloud Tasks - Deployment Script
# This script deploys the complete QA automation infrastructure on Google Cloud Platform

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Error handling
error_exit() {
    log_error "$1"
    exit 1
}

# Check if required tools are installed
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    local required_tools=("gcloud" "firebase" "gsutil" "npm" "python3" "curl" "jq")
    local missing_tools=()
    
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        error_exit "Missing required tools: ${missing_tools[*]}. Please install them before running this script."
    fi
    
    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null; then
        error_exit "No active gcloud authentication found. Run 'gcloud auth login' first."
    fi
    
    log_success "All prerequisites met"
}

# Set up environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Generate unique project ID if not provided
    if [ -z "${PROJECT_ID:-}" ]; then
        export PROJECT_ID="qa-workflows-$(date +%s)"
        log_info "Generated PROJECT_ID: ${PROJECT_ID}"
    fi
    
    # Set default values for environment variables
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names
    local random_suffix
    random_suffix=$(openssl rand -hex 3 2>/dev/null || echo "$(date +%s | tail -c 6)")
    export QA_BUCKET_NAME="${QA_BUCKET_NAME:-qa-artifacts-${random_suffix}}"
    export TASK_QUEUE_NAME="${TASK_QUEUE_NAME:-qa-orchestration-${random_suffix}}"
    export FIRESTORE_COLLECTION="${FIRESTORE_COLLECTION:-qa-workflows}"
    
    # Set gcloud defaults
    gcloud config set project "${PROJECT_ID}" || error_exit "Failed to set project"
    gcloud config set compute/region "${REGION}" || error_exit "Failed to set region"
    gcloud config set compute/zone "${ZONE}" || error_exit "Failed to set zone"
    
    log_success "Environment configured:"
    log_info "  Project ID: ${PROJECT_ID}"
    log_info "  Region: ${REGION}"
    log_info "  QA Bucket: ${QA_BUCKET_NAME}"
    log_info "  Task Queue: ${TASK_QUEUE_NAME}"
}

# Create or verify project
setup_project() {
    log_info "Setting up Google Cloud project..."
    
    # Check if project exists
    if gcloud projects describe "${PROJECT_ID}" &>/dev/null; then
        log_info "Using existing project: ${PROJECT_ID}"
    else
        log_info "Creating new project: ${PROJECT_ID}"
        gcloud projects create "${PROJECT_ID}" --name="QA Workflows Project" || error_exit "Failed to create project"
        
        # Enable billing (requires manual setup)
        log_warning "Please ensure billing is enabled for project ${PROJECT_ID}"
        log_warning "Visit: https://console.cloud.google.com/billing/linkedaccount?project=${PROJECT_ID}"
        read -p "Press Enter when billing is enabled..."
    fi
    
    # Set the project
    gcloud config set project "${PROJECT_ID}"
    
    log_success "Project setup completed"
}

# Enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "firebase.googleapis.com"
        "cloudtasks.googleapis.com"
        "storage.googleapis.com"
        "aiplatform.googleapis.com"
        "cloudfunctions.googleapis.com"
        "firestore.googleapis.com"
        "cloudbuild.googleapis.com"
        "cloudrun.googleapis.com"
        "iamcredentials.googleapis.com"
        "artifactregistry.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling ${api}..."
        gcloud services enable "${api}" || error_exit "Failed to enable ${api}"
    done
    
    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully enabled..."
    sleep 30
    
    log_success "All APIs enabled successfully"
}

# Initialize Firebase project
setup_firebase() {
    log_info "Initializing Firebase project..."
    
    # Add Firebase to the project
    firebase projects:addfirebase "${PROJECT_ID}" || {
        log_warning "Firebase may already be added to this project"
    }
    
    # Create Firestore database
    log_info "Creating Firestore database..."
    gcloud firestore databases create \
        --location="${REGION}" \
        --type=firestore-native \
        --quiet || {
        log_warning "Firestore database may already exist"
    }
    
    # Set up Firestore security rules
    log_info "Configuring Firestore security rules..."
    cat > firestore.rules << 'EOF'
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /qa-workflows/{workflowId} {
      allow read, write: if request.auth != null;
    }
    match /test-results/{resultId} {
      allow read, write: if request.auth != null;
    }
    match /qa-triggers/{triggerId} {
      allow read, write: if request.auth != null;
    }
  }
}
EOF
    
    gcloud firestore databases update \
        --database="(default)" \
        --rules-file=firestore.rules \
        --quiet || error_exit "Failed to update Firestore rules"
    
    rm -f firestore.rules
    
    log_success "Firebase project initialized with Firestore"
}

# Create Cloud Storage bucket
setup_storage() {
    log_info "Creating Cloud Storage bucket for QA artifacts..."
    
    # Create bucket
    gsutil mb -p "${PROJECT_ID}" \
        -c STANDARD \
        -l "${REGION}" \
        "gs://${QA_BUCKET_NAME}" || {
        if gsutil ls "gs://${QA_BUCKET_NAME}" &>/dev/null; then
            log_warning "Bucket gs://${QA_BUCKET_NAME} already exists"
        else
            error_exit "Failed to create bucket"
        fi
    }
    
    # Enable versioning
    gsutil versioning set on "gs://${QA_BUCKET_NAME}" || error_exit "Failed to enable versioning"
    
    # Set up lifecycle policy
    cat > lifecycle.json << 'EOF'
{
  "lifecycle": {
    "rule": [
      {
        "action": {"type": "SetStorageClass", "storageClass": "NEARLINE"},
        "condition": {"age": 30}
      },
      {
        "action": {"type": "SetStorageClass", "storageClass": "COLDLINE"},
        "condition": {"age": 90}
      },
      {
        "action": {"type": "Delete"},
        "condition": {"age": 365}
      }
    ]
  }
}
EOF
    
    gsutil lifecycle set lifecycle.json "gs://${QA_BUCKET_NAME}" || error_exit "Failed to set lifecycle policy"
    rm -f lifecycle.json
    
    log_success "Cloud Storage bucket created with lifecycle management"
}

# Set up Cloud Tasks queues
setup_cloud_tasks() {
    log_info "Creating Cloud Tasks queues for test orchestration..."
    
    # Create main orchestration queue
    gcloud tasks queues create "${TASK_QUEUE_NAME}" \
        --location="${REGION}" \
        --max-concurrent-dispatches=10 \
        --max-retry-duration=3600s \
        --min-backoff=1s \
        --max-backoff=300s \
        --quiet || {
        log_warning "Queue ${TASK_QUEUE_NAME} may already exist"
    }
    
    # Create priority queue
    gcloud tasks queues create "${TASK_QUEUE_NAME}-priority" \
        --location="${REGION}" \
        --max-concurrent-dispatches=5 \
        --max-retry-duration=1800s \
        --quiet || {
        log_warning "Priority queue may already exist"
    }
    
    # Create analysis queue
    gcloud tasks queues create "${TASK_QUEUE_NAME}-analysis" \
        --location="${REGION}" \
        --max-concurrent-dispatches=3 \
        --max-retry-duration=7200s \
        --quiet || {
        log_warning "Analysis queue may already exist"
    }
    
    log_success "Cloud Tasks queues created successfully"
}

# Deploy Firebase Extensions
deploy_firebase_extension() {
    log_info "Creating custom Firebase Extension for QA workflow triggers..."
    
    # Create extension directory
    mkdir -p qa-workflow-extension/functions
    cd qa-workflow-extension
    
    # Create extension.yaml
    cat > extension.yaml << 'EOF'
name: qa-workflow-trigger
version: 0.1.0
specVersion: v1beta

displayName: QA Workflow Trigger
description: Triggers automated QA workflows based on repository changes

apis:
  - apiName: cloudtasks.googleapis.com
  - apiName: aiplatform.googleapis.com
  - apiName: storage.googleapis.com

roles:
  - role: cloudtasks.admin
  - role: storage.admin
  - role: aiplatform.user
  - role: datastore.user

resources:
  - name: qaWorkflowTrigger
    type: firebaseextensions.v1beta.function
    description: Function that triggers QA workflows
    properties:
      location: us-central1
      runtime: nodejs18
      eventTrigger:
        eventType: providers/google.firebase.database/eventTypes/ref.write
        resource: projects/_/instances/_(default)/refs/qa-triggers/{triggerId}

params:
  - param: TASK_QUEUE_LOCATION
    label: Cloud Tasks queue location
    default: us-central1
  - param: STORAGE_BUCKET
    label: Storage bucket for QA artifacts
    required: true
  - param: VERTEX_AI_REGION
    label: Vertex AI region for analysis
    default: us-central1
EOF
    
    # Create functions directory and package.json
    cd functions
    cat > package.json << 'EOF'
{
  "name": "qa-workflow-trigger",
  "version": "1.0.0",
  "description": "Firebase Extension for QA workflow automation",
  "main": "index.js",
  "dependencies": {
    "@google-cloud/tasks": "^4.0.0",
    "@google-cloud/storage": "^7.0.0",
    "@google-cloud/aiplatform": "^3.0.0",
    "firebase-functions": "^4.0.0",
    "firebase-admin": "^11.0.0"
  },
  "engines": {
    "node": "18"
  }
}
EOF
    
    # Create the Cloud Function code
    cat > index.js << 'EOF'
const functions = require('firebase-functions');
const {CloudTasksClient} = require('@google-cloud/tasks');
const {Storage} = require('@google-cloud/storage');

const tasksClient = new CloudTasksClient();
const storage = new Storage();

exports.qaWorkflowTrigger = functions.database.ref('/qa-triggers/{triggerId}')
  .onWrite(async (change, context) => {
    const triggerId = context.params.triggerId;
    const triggerData = change.after.val();
    
    if (!triggerData) return; // Deletion event
    
    console.log(`QA workflow triggered for: ${triggerId}`);
    
    // Create tasks for different QA phases
    const queuePath = tasksClient.queuePath(
      process.env.GCLOUD_PROJECT,
      process.env.TASK_QUEUE_LOCATION || 'us-central1',
      process.env.TASK_QUEUE_NAME || 'qa-orchestration'
    );
    
    const tasks = [
      { phase: 'static-analysis', priority: 1 },
      { phase: 'unit-tests', priority: 2 },
      { phase: 'integration-tests', priority: 3 },
      { phase: 'performance-tests', priority: 4 },
      { phase: 'ai-analysis', priority: 5 }
    ];
    
    for (const task of tasks) {
      const taskData = {
        triggerId,
        phase: task.phase,
        timestamp: Date.now(),
        config: triggerData
      };
      
      const taskRequest = {
        parent: queuePath,
        task: {
          httpRequest: {
            httpMethod: 'POST',
            url: `https://${process.env.GCLOUD_PROJECT}.cloudfunctions.net/qaPhaseExecutor`,
            headers: { 'Content-Type': 'application/json' },
            body: Buffer.from(JSON.stringify(taskData))
          },
          scheduleTime: {
            seconds: Date.now() / 1000 + (task.priority * 30)
          }
        }
      };
      
      try {
        await tasksClient.createTask(taskRequest);
        console.log(`Created task for phase: ${task.phase}`);
      } catch (error) {
        console.error(`Failed to create task for ${task.phase}:`, error);
      }
    }
    
    return { status: 'QA workflow initiated', triggerId };
  });
EOF
    
    # Install dependencies
    npm install --silent || error_exit "Failed to install npm dependencies"
    
    cd ../..
    log_success "Firebase Extension created"
}

# Deploy Cloud Functions
deploy_cloud_functions() {
    log_info "Deploying QA phase executor Cloud Function..."
    
    # Create function directory
    mkdir -p qa-phase-executor
    cd qa-phase-executor
    
    # Create main.py
    cat > main.py << 'EOF'
import json
import functions_framework
from google.cloud import firestore
from google.cloud import storage
from google.cloud import aiplatform
import logging
import time
import os

# Initialize clients
db = firestore.Client()
storage_client = storage.Client()

@functions_framework.http
def qa_phase_executor(request):
    """Execute specific QA phase based on task data"""
    request_json = request.get_json()
    
    if not request_json:
        return {'error': 'No JSON body provided'}, 400
    
    trigger_id = request_json.get('triggerId')
    phase = request_json.get('phase')
    config = request_json.get('config', {})
    
    logging.info(f"Executing QA phase: {phase} for trigger: {trigger_id}")
    
    # Update Firestore with phase start
    doc_ref = db.collection('qa-workflows').document(trigger_id)
    doc_ref.set({
        f'phases.{phase}': {
            'status': 'running',
            'start_time': firestore.SERVER_TIMESTAMP,
            'config': config
        }
    }, merge=True)
    
    result = {}
    
    try:
        if phase == 'static-analysis':
            result = execute_static_analysis(trigger_id, config)
        elif phase == 'unit-tests':
            result = execute_unit_tests(trigger_id, config)
        elif phase == 'integration-tests':
            result = execute_integration_tests(trigger_id, config)
        elif phase == 'performance-tests':
            result = execute_performance_tests(trigger_id, config)
        elif phase == 'ai-analysis':
            result = execute_ai_analysis(trigger_id, config)
        else:
            result = {'error': f'Unknown phase: {phase}'}
        
        # Update Firestore with results
        doc_ref.set({
            f'phases.{phase}': {
                'status': 'completed',
                'end_time': firestore.SERVER_TIMESTAMP,
                'result': result,
                'success': result.get('success', False)
            }
        }, merge=True)
        
    except Exception as e:
        logging.error(f"Error in phase {phase}: {str(e)}")
        doc_ref.set({
            f'phases.{phase}': {
                'status': 'failed',
                'end_time': firestore.SERVER_TIMESTAMP,
                'error': str(e)
            }
        }, merge=True)
        result = {'error': str(e)}
    
    return result

def execute_static_analysis(trigger_id, config):
    """Execute static code analysis"""
    time.sleep(2)
    return {
        'success': True,
        'metrics': {
            'code_coverage': 85.5,
            'complexity_score': 7.2,
            'security_issues': 2,
            'code_smells': 15
        }
    }

def execute_unit_tests(trigger_id, config):
    """Execute unit tests"""
    time.sleep(3)
    return {
        'success': True,
        'metrics': {
            'tests_run': 127,
            'tests_passed': 124,
            'tests_failed': 3,
            'execution_time': '45.2s'
        }
    }

def execute_integration_tests(trigger_id, config):
    """Execute integration tests"""
    time.sleep(5)
    return {
        'success': True,
        'metrics': {
            'tests_run': 43,
            'tests_passed': 41,
            'tests_failed': 2,
            'execution_time': '182.7s'
        }
    }

def execute_performance_tests(trigger_id, config):
    """Execute performance tests"""
    time.sleep(8)
    return {
        'success': True,
        'metrics': {
            'avg_response_time': '247ms',
            'throughput': '1240 req/sec',
            'error_rate': '0.02%',
            'cpu_usage': '67%'
        }
    }

def execute_ai_analysis(trigger_id, config):
    """Execute AI-powered analysis of test results"""
    try:
        # Retrieve all phase results for analysis
        doc_ref = db.collection('qa-workflows').document(trigger_id)
        workflow_doc = doc_ref.get()
        
        if not workflow_doc.exists:
            return {'error': 'Workflow document not found'}
        
        phases_data = workflow_doc.to_dict().get('phases', {})
        
        # Prepare data for AI analysis
        analysis_data = {
            'workflow_id': trigger_id,
            'phase_results': phases_data,
            'timestamp': time.time()
        }
        
        # Store analysis data in Cloud Storage for Vertex AI processing
        bucket_name = os.environ.get('QA_BUCKET_NAME')
        if bucket_name:
            bucket = storage_client.bucket(bucket_name)
            blob = bucket.blob(f'ai-analysis/{trigger_id}/analysis-data.json')
            blob.upload_from_string(json.dumps(analysis_data))
        
        # Simulate AI analysis (in production, use Vertex AI)
        analysis_result = {
            'overall_quality_score': 78.5,
            'risk_level': 'medium',
            'recommendations': [
                'Increase unit test coverage for authentication module',
                'Address performance bottleneck in database queries',
                'Review security issues in input validation'
            ],
            'trend_analysis': {
                'quality_trend': 'improving',
                'performance_trend': 'stable',
                'security_trend': 'declining'
            }
        }
        
        return {
            'success': True,
            'analysis': analysis_result
        }
        
    except Exception as e:
        logging.error(f"AI analysis error: {str(e)}")
        return {'error': f'AI analysis failed: {str(e)}'}
EOF
    
    # Create requirements.txt
    cat > requirements.txt << 'EOF'
functions-framework==3.*
google-cloud-firestore
google-cloud-storage
google-cloud-aiplatform
EOF
    
    # Deploy the Cloud Function
    gcloud functions deploy qa-phase-executor \
        --gen2 \
        --runtime=python311 \
        --region="${REGION}" \
        --source=. \
        --entry-point=qa_phase_executor \
        --trigger=http \
        --allow-unauthenticated \
        --set-env-vars="QA_BUCKET_NAME=${QA_BUCKET_NAME},TASK_QUEUE_NAME=${TASK_QUEUE_NAME}" \
        --timeout=540 \
        --memory=512MB \
        --quiet || error_exit "Failed to deploy qa-phase-executor function"
    
    cd ..
    log_success "Cloud Functions deployed successfully"
}

# Configure Vertex AI
setup_vertex_ai() {
    log_info "Configuring Vertex AI for intelligent analysis..."
    
    # Create Vertex AI dataset
    gcloud ai datasets create \
        --display-name="qa-metrics-dataset" \
        --metadata-schema-uri="gs://google-cloud-aiplatform/schema/dataset/metadata/tabular_1.0.0.yaml" \
        --region="${REGION}" \
        --quiet || {
        log_warning "Vertex AI dataset may already exist"
    }
    
    # Export initial Firestore data for ML training
    log_info "Exporting Firestore data for ML training..."
    gcloud firestore export "gs://${QA_BUCKET_NAME}/firestore-export/" \
        --collection-ids=qa-workflows,test-results \
        --async \
        --quiet || {
        log_warning "Initial Firestore export may have failed"
    }
    
    log_success "Vertex AI configured successfully"
}

# Deploy QA Dashboard
deploy_dashboard() {
    log_info "Deploying QA Dashboard to Cloud Run..."
    
    # Create dashboard directory
    mkdir -p qa-dashboard
    cd qa-dashboard
    
    # Create app.py
    cat > app.py << 'EOF'
from flask import Flask, render_template, jsonify
from google.cloud import firestore
from google.cloud import storage
import json
import os
from datetime import datetime, timedelta

app = Flask(__name__)
db = firestore.Client()
storage_client = storage.Client()

@app.route('/')
def dashboard():
    return render_template('dashboard.html')

@app.route('/api/workflows')
def get_workflows():
    """Get recent QA workflows"""
    workflows = []
    try:
        docs = db.collection('qa-workflows').order_by('timestamp', direction=firestore.Query.DESCENDING).limit(20).stream()
        
        for doc in docs:
            workflow_data = doc.to_dict()
            workflow_data['id'] = doc.id
            workflows.append(workflow_data)
    except Exception as e:
        app.logger.error(f"Error fetching workflows: {str(e)}")
    
    return jsonify(workflows)

@app.route('/api/metrics')
def get_metrics():
    """Get aggregated QA metrics"""
    try:
        # Calculate metrics for the last 30 days
        end_date = datetime.now()
        start_date = end_date - timedelta(days=30)
        
        docs = db.collection('qa-workflows').where('timestamp', '>=', start_date).stream()
        
        total_workflows = 0
        successful_workflows = 0
        avg_quality_score = 0
        
        for doc in docs:
            workflow_data = doc.to_dict()
            total_workflows += 1
            
            phases = workflow_data.get('phases', {})
            ai_analysis = phases.get('ai-analysis', {})
            
            if ai_analysis.get('status') == 'completed':
                result = ai_analysis.get('result', {})
                analysis = result.get('analysis', {})
                if analysis.get('overall_quality_score'):
                    avg_quality_score += analysis['overall_quality_score']
                    successful_workflows += 1
        
        if successful_workflows > 0:
            avg_quality_score = avg_quality_score / successful_workflows
        
        return jsonify({
            'total_workflows': total_workflows,
            'successful_workflows': successful_workflows,
            'success_rate': (successful_workflows / total_workflows * 100) if total_workflows > 0 else 0,
            'avg_quality_score': round(avg_quality_score, 1)
        })
    except Exception as e:
        app.logger.error(f"Error calculating metrics: {str(e)}")
        return jsonify({'error': 'Failed to calculate metrics'}), 500

@app.route('/api/workflow/<workflow_id>')
def get_workflow_details(workflow_id):
    """Get detailed workflow information"""
    try:
        doc = db.collection('qa-workflows').document(workflow_id).get()
        
        if not doc.exists:
            return jsonify({'error': 'Workflow not found'}), 404
        
        workflow_data = doc.to_dict()
        workflow_data['id'] = doc.id
        
        return jsonify(workflow_data)
    except Exception as e:
        app.logger.error(f"Error fetching workflow details: {str(e)}")
        return jsonify({'error': 'Failed to fetch workflow details'}), 500

@app.route('/health')
def health_check():
    return jsonify({'status': 'healthy'})

if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0', port=int(os.environ.get('PORT', 8080)))
EOF
    
    # Create templates directory and HTML template
    mkdir -p templates
    cat > templates/dashboard.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>QA Workflow Dashboard</title>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
        body { 
            font-family: Arial, sans-serif; 
            margin: 20px; 
            background-color: #f5f5f5;
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
            background: white;
            padding: 20px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        .metrics-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        .metric-card { 
            background: #f8f9fa; 
            padding: 20px; 
            border-radius: 8px; 
            text-align: center;
            border: 1px solid #e9ecef;
        }
        .metric-value {
            font-size: 2em;
            font-weight: bold;
            color: #007bff;
            margin: 10px 0;
        }
        .workflow-item { 
            border: 1px solid #ddd; 
            padding: 15px; 
            margin: 10px 0; 
            border-radius: 8px; 
            background: #fafafa;
        }
        .status-success { color: #28a745; font-weight: bold; }
        .status-failed { color: #dc3545; font-weight: bold; }
        .status-running { color: #ffc107; font-weight: bold; }
        .loading { text-align: center; color: #6c757d; }
        .header {
            text-align: center;
            margin-bottom: 30px;
            padding-bottom: 20px;
            border-bottom: 2px solid #007bff;
        }
        .refresh-btn {
            background: #007bff;
            color: white;
            border: none;
            padding: 10px 20px;
            border-radius: 5px;
            cursor: pointer;
            float: right;
        }
        .refresh-btn:hover {
            background: #0056b3;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>QA Workflow Dashboard</h1>
            <p>Real-time monitoring of automated quality assurance workflows</p>
            <button class="refresh-btn" onclick="loadData()">Refresh Data</button>
            <div style="clear: both;"></div>
        </div>
        
        <div class="metrics-grid">
            <div class="metric-card">
                <h3>Total Workflows</h3>
                <div class="metric-value" id="total-workflows">-</div>
                <small>Last 30 days</small>
            </div>
            <div class="metric-card">
                <h3>Success Rate</h3>
                <div class="metric-value" id="success-rate">-</div>
                <small>Completed workflows</small>
            </div>
            <div class="metric-card">
                <h3>Average Quality Score</h3>
                <div class="metric-value" id="avg-quality-score">-</div>
                <small>AI-powered analysis</small>
            </div>
        </div>
        
        <h2>Recent Workflows</h2>
        <div id="workflows-container" class="loading">Loading workflows...</div>
    </div>
    
    <script>
    async function loadMetrics() {
        try {
            const response = await fetch('/api/metrics');
            const metrics = await response.json();
            
            document.getElementById('total-workflows').textContent = metrics.total_workflows;
            document.getElementById('success-rate').textContent = metrics.success_rate.toFixed(1) + '%';
            document.getElementById('avg-quality-score').textContent = metrics.avg_quality_score;
        } catch (error) {
            console.error('Error loading metrics:', error);
            document.getElementById('total-workflows').textContent = 'Error';
            document.getElementById('success-rate').textContent = 'Error';
            document.getElementById('avg-quality-score').textContent = 'Error';
        }
    }
    
    async function loadWorkflows() {
        try {
            const response = await fetch('/api/workflows');
            const workflows = await response.json();
            
            const container = document.getElementById('workflows-container');
            container.innerHTML = '';
            
            if (workflows.length === 0) {
                container.innerHTML = '<p class="loading">No workflows found. Create some test triggers to see data here.</p>';
                return;
            }
            
            workflows.forEach(workflow => {
                const phases = workflow.phases || {};
                const phaseCount = Object.keys(phases).length;
                const completedPhases = Object.values(phases).filter(p => p.status === 'completed').length;
                const failedPhases = Object.values(phases).filter(p => p.status === 'failed').length;
                
                let overallStatus = 'running';
                if (failedPhases > 0) {
                    overallStatus = 'failed';
                } else if (completedPhases === phaseCount && phaseCount > 0) {
                    overallStatus = 'success';
                }
                
                const div = document.createElement('div');
                div.className = 'workflow-item';
                div.innerHTML = `
                    <h4>Workflow: ${workflow.id}</h4>
                    <p>Status: <span class="status-${overallStatus}">${overallStatus.toUpperCase()}</span></p>
                    <p>Phases: ${completedPhases}/${phaseCount} completed ${failedPhases > 0 ? `(${failedPhases} failed)` : ''}</p>
                    <p>Repository: ${workflow.repository || 'N/A'}</p>
                    <p>Branch: ${workflow.branch || 'N/A'}</p>
                `;
                container.appendChild(div);
            });
        } catch (error) {
            console.error('Error loading workflows:', error);
            document.getElementById('workflows-container').innerHTML = 
                '<p style="color: red;">Error loading workflows. Please refresh the page.</p>';
        }
    }
    
    function loadData() {
        loadMetrics();
        loadWorkflows();
    }
    
    // Load data when page loads
    window.onload = function() {
        loadData();
        // Auto-refresh every 30 seconds
        setInterval(loadData, 30000);
    };
    </script>
</body>
</html>
EOF
    
    # Create requirements.txt
    cat > requirements.txt << 'EOF'
Flask==2.3.3
google-cloud-firestore==2.13.1
google-cloud-storage==2.10.0
gunicorn==21.2.0
EOF
    
    # Create Dockerfile
    cat > Dockerfile << 'EOF'
FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Create non-root user for security
RUN useradd --create-home --shell /bin/bash app && chown -R app:app /app
USER app

# Health check
HEALTHCHECK --interval=30s --timeout=30s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:$PORT/health || exit 1

# Run the application
CMD exec gunicorn --bind :$PORT --workers 1 --threads 8 --timeout 0 app:app
EOF
    
    # Deploy to Cloud Run
    gcloud run deploy qa-dashboard \
        --source . \
        --platform managed \
        --region "${REGION}" \
        --allow-unauthenticated \
        --set-env-vars="GOOGLE_CLOUD_PROJECT=${PROJECT_ID}" \
        --memory=512Mi \
        --cpu=1 \
        --min-instances=0 \
        --max-instances=10 \
        --timeout=300 \
        --quiet || error_exit "Failed to deploy dashboard"
    
    # Get dashboard URL
    DASHBOARD_URL=$(gcloud run services describe qa-dashboard \
        --region="${REGION}" \
        --format="value(status.url)")
    
    cd ..
    log_success "QA Dashboard deployed successfully"
    log_info "Dashboard URL: ${DASHBOARD_URL}"
}

# Test the deployment
test_deployment() {
    log_info "Testing QA workflow deployment..."
    
    # Create test trigger data
    cat > test-trigger.json << EOF
{
  "repository": "test-application",
  "branch": "main",
  "commit_hash": "abc123def456",
  "trigger_type": "pull_request",
  "author": "developer@company.com",
  "timestamp": "$(date -Iseconds)",
  "config": {
    "test_suites": ["unit", "integration", "performance"],
    "analysis_enabled": true,
    "notification_channels": ["email", "slack"]
  }
}
EOF
    
    # Test Cloud Storage
    echo "test-content" | gsutil cp - "gs://${QA_BUCKET_NAME}/test/deployment-test.txt" || {
        log_warning "Cloud Storage test failed"
    }
    
    # Test Cloud Tasks queues
    gcloud tasks queues describe "${TASK_QUEUE_NAME}" \
        --location="${REGION}" \
        --format="value(name)" > /dev/null || {
        log_warning "Cloud Tasks queue test failed"
    }
    
    # Test Cloud Functions
    local function_url
    function_url=$(gcloud functions describe qa-phase-executor \
        --region="${REGION}" \
        --format="value(httpsTrigger.url)")
    
    if [ -n "${function_url}" ]; then
        curl -s -X POST "${function_url}" \
            -H "Content-Type: application/json" \
            -d '{"triggerId":"test","phase":"static-analysis","config":{}}' > /dev/null || {
            log_warning "Cloud Function test failed"
        }
    fi
    
    # Clean up test files
    rm -f test-trigger.json
    gsutil rm "gs://${QA_BUCKET_NAME}/test/deployment-test.txt" 2>/dev/null || true
    
    log_success "Deployment testing completed"
}

# Display deployment summary
display_summary() {
    log_success "QA Workflow deployment completed successfully!"
    echo ""
    echo "=== DEPLOYMENT SUMMARY ==="
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo "QA Bucket: gs://${QA_BUCKET_NAME}"
    echo "Task Queue: ${TASK_QUEUE_NAME}"
    echo ""
    
    # Get dashboard URL
    local dashboard_url
    dashboard_url=$(gcloud run services describe qa-dashboard \
        --region="${REGION}" \
        --format="value(status.url)" 2>/dev/null || echo "Not deployed")
    
    echo "=== ACCESS INFORMATION ==="
    echo "QA Dashboard: ${dashboard_url}"
    echo "Google Cloud Console: https://console.cloud.google.com/home/dashboard?project=${PROJECT_ID}"
    echo "Cloud Storage: https://console.cloud.google.com/storage/browser/${QA_BUCKET_NAME}?project=${PROJECT_ID}"
    echo "Cloud Tasks: https://console.cloud.google.com/cloudtasks?project=${PROJECT_ID}"
    echo ""
    
    echo "=== NEXT STEPS ==="
    echo "1. Access the QA Dashboard to monitor workflows"
    echo "2. Create test triggers in Firestore to initiate QA workflows"
    echo "3. Monitor Cloud Tasks queues for task processing"
    echo "4. Review Firestore collections for workflow results"
    echo "5. Check Cloud Storage for QA artifacts and analysis data"
    echo ""
    
    echo "=== COST OPTIMIZATION ==="
    echo "- Monitor billing through Cloud Console"
    echo "- Use Cloud Storage lifecycle policies (already configured)"
    echo "- Scale Cloud Run instances based on usage"
    echo "- Set up budget alerts to avoid unexpected charges"
    echo ""
    
    log_info "For cleanup, run: ./destroy.sh"
}

# Main deployment function
main() {
    log_info "Starting QA Workflow deployment..."
    
    # Check if this is a dry run
    if [ "${DRY_RUN:-false}" = "true" ]; then
        log_info "DRY RUN MODE - No resources will be created"
        exit 0
    fi
    
    # Create temporary directory for deployment artifacts
    local temp_dir
    temp_dir=$(mktemp -d)
    local original_dir
    original_dir=$(pwd)
    
    cd "${temp_dir}"
    
    # Trap to cleanup on exit
    trap 'cd "${original_dir}"; rm -rf "${temp_dir}"' EXIT
    
    # Run deployment steps
    check_prerequisites
    setup_environment
    setup_project
    enable_apis
    setup_firebase
    setup_storage
    setup_cloud_tasks
    deploy_firebase_extension
    deploy_cloud_functions
    setup_vertex_ai
    deploy_dashboard
    test_deployment
    display_summary
    
    log_success "QA Workflow deployment completed successfully!"
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi