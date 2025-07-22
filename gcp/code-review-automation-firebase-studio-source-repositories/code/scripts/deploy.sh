#!/bin/bash

# Code Review Automation with Firebase Studio and Cloud Source Repositories
# Deployment Script for GCP
#
# This script deploys an AI-powered code review automation system using:
# - Firebase Studio for AI agent development
# - Cloud Source Repositories for Git hosting
# - Vertex AI for intelligent code analysis
# - Cloud Functions for workflow orchestration

set -euo pipefail

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/deploy.log"
readonly TIMESTAMP="$(date +%Y%m%d_%H%M%S)"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "${LOG_FILE}"
}

info() { log "INFO" "${BLUE}$*${NC}"; }
warn() { log "WARN" "${YELLOW}$*${NC}"; }
error() { log "ERROR" "${RED}$*${NC}"; }
success() { log "SUCCESS" "${GREEN}$*${NC}"; }

# Error handling
cleanup_on_error() {
    error "Deployment failed. Check ${LOG_FILE} for details."
    error "Run destroy.sh to clean up any partially created resources."
    exit 1
}

trap cleanup_on_error ERR

# Display banner
show_banner() {
    echo -e "${BLUE}"
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║              Code Review Automation Deployment            ║"
    echo "║                                                            ║"
    echo "║  Firebase Studio + Cloud Source Repositories + Vertex AI  ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Prerequisites check
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if gcloud is installed and authenticated
    if ! command -v gcloud &> /dev/null; then
        error "Google Cloud CLI (gcloud) is not installed."
        error "Install from: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null; then
        error "No active gcloud authentication found."
        error "Run: gcloud auth login"
        exit 1
    fi
    
    # Check if required commands are available
    local required_commands=("curl" "jq" "git")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            error "Required command '$cmd' is not installed."
            exit 1
        fi
    done
    
    success "Prerequisites check completed"
}

# Project setup and validation
setup_project() {
    info "Setting up Google Cloud project..."
    
    # Get current project or prompt for one
    local current_project
    current_project=$(gcloud config get-value project 2>/dev/null || echo "")
    
    if [[ -z "$current_project" ]]; then
        error "No Google Cloud project is set."
        error "Set a project with: gcloud config set project PROJECT_ID"
        exit 1
    fi
    
    export PROJECT_ID="$current_project"
    export REGION="${REGION:-us-central1}"
    export REPOSITORY_NAME="${REPOSITORY_NAME:-intelligent-review-system-${TIMESTAMP}}"
    
    # Generate unique identifiers
    local random_suffix
    random_suffix=$(openssl rand -hex 3)
    export FUNCTION_NAME="${FUNCTION_NAME:-code-review-trigger-${random_suffix}}"
    export AGENT_NAME="${AGENT_NAME:-code-review-agent-${random_suffix}}"
    
    info "Project ID: ${PROJECT_ID}"
    info "Region: ${REGION}"
    info "Repository: ${REPOSITORY_NAME}"
    info "Function: ${FUNCTION_NAME}"
    
    # Set gcloud defaults
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    
    success "Project configuration completed"
}

# Enable required APIs
enable_apis() {
    info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "sourcerepo.googleapis.com"
        "cloudfunctions.googleapis.com"
        "aiplatform.googleapis.com"
        "cloudbuild.googleapis.com"
        "firebase.googleapis.com"
        "eventarc.googleapis.com"
        "logging.googleapis.com"
        "monitoring.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        info "Enabling ${api}..."
        if gcloud services enable "${api}" --quiet; then
            success "Enabled ${api}"
        else
            error "Failed to enable ${api}"
            exit 1
        fi
    done
    
    info "Waiting for APIs to be fully enabled..."
    sleep 30
    
    success "All required APIs enabled"
}

# Create Cloud Source Repository
create_repository() {
    info "Creating Cloud Source Repository..."
    
    # Check if repository already exists
    if gcloud source repos describe "${REPOSITORY_NAME}" &>/dev/null; then
        warn "Repository ${REPOSITORY_NAME} already exists"
        return 0
    fi
    
    # Create the repository
    if gcloud source repos create "${REPOSITORY_NAME}"; then
        success "Repository ${REPOSITORY_NAME} created"
    else
        error "Failed to create repository"
        exit 1
    fi
    
    # Get repository URL
    local repo_url
    repo_url=$(gcloud source repos describe "${REPOSITORY_NAME}" --format="value(url)")
    export REPO_URL="$repo_url"
    
    info "Repository URL: ${REPO_URL}"
}

# Initialize repository with sample code
initialize_repository() {
    info "Initializing repository with sample code..."
    
    local temp_dir="/tmp/code-review-repo-${TIMESTAMP}"
    
    # Clone repository
    gcloud source repos clone "${REPOSITORY_NAME}" "${temp_dir}" --project="${PROJECT_ID}"
    
    cd "${temp_dir}"
    
    # Create sample application structure
    mkdir -p src/{components,services,utils,tests}
    mkdir -p docs config
    
    # Create sample JavaScript file with code quality issues
    cat > src/components/UserManager.js << 'EOF'
// Sample component with intentional code quality issues for AI review testing
function UserManager() {
    var users = [];
    
    function addUser(name, email) {
        // Missing validation - security issue
        users.push({name: name, email: email, id: Math.random()});
    }
    
    function getUser(id) {
        // Inefficient search algorithm - performance issue
        for (var i = 0; i < users.length; i++) {
            if (users[i].id == id) {
                return users[i];
            }
        }
    }
    
    // Missing return statement - code quality issue
    function deleteUser(id) {
        users = users.filter(user => user.id !== id);
    }
    
    return {
        addUser: addUser,
        getUser: getUser,
        deleteUser: deleteUser
    };
}

module.exports = UserManager;
EOF
    
    # Create package.json
    cat > package.json << 'EOF'
{
  "name": "intelligent-review-demo",
  "version": "1.0.0",
  "description": "Demo application for AI-powered code review automation",
  "main": "src/components/UserManager.js",
  "scripts": {
    "test": "jest",
    "lint": "eslint src/",
    "start": "node src/components/UserManager.js"
  },
  "dependencies": {
    "express": "^4.18.0"
  },
  "devDependencies": {
    "jest": "^29.0.0",
    "eslint": "^8.0.0"
  },
  "keywords": ["ai", "code-review", "automation", "firebase-studio"],
  "author": "Code Review Automation System",
  "license": "MIT"
}
EOF
    
    # Create README for the sample project
    cat > README.md << 'EOF'
# Intelligent Code Review Demo

This repository demonstrates an AI-powered code review automation system using Firebase Studio and Google Cloud services.

## Features

- Automated code quality analysis
- Security vulnerability detection
- Performance optimization suggestions
- Best practices enforcement

## Sample Files

- `src/components/UserManager.js` - Contains intentional code issues for testing AI review capabilities
- `package.json` - Project configuration and dependencies

## AI Review System

The integrated AI review system analyzes code for:

1. Security vulnerabilities
2. Performance issues
3. Code quality and maintainability
4. Best practices adherence
5. Documentation needs

Changes to this repository automatically trigger intelligent analysis and feedback.
EOF
    
    # Commit initial structure
    git add .
    git commit -m "Initial project structure for AI code review automation testing

- Added sample UserManager component with various code quality issues
- Configured package.json with testing and linting setup
- Created project documentation

This commit provides test cases for AI analysis including:
- Security issues (missing validation)
- Performance problems (inefficient algorithms)
- Code quality concerns (missing return statements)
- Documentation gaps"
    
    # Push to repository
    if git push origin main; then
        success "Sample code structure committed and pushed"
    else
        error "Failed to push initial code structure"
        exit 1
    fi
    
    cd - > /dev/null
    rm -rf "${temp_dir}"
}

# Create Cloud Function for code review automation
create_cloud_function() {
    info "Creating Cloud Function for code review automation..."
    
    local function_dir="${SCRIPT_DIR}/../function-source"
    mkdir -p "${function_dir}"
    
    # Create package.json for Cloud Function
    cat > "${function_dir}/package.json" << 'EOF'
{
  "name": "code-review-trigger",
  "version": "1.0.0",
  "description": "AI-powered code review automation trigger",
  "main": "index.js",
  "scripts": {
    "start": "functions-framework --target=codeReviewTrigger"
  },
  "dependencies": {
    "@google-cloud/functions-framework": "^3.3.0",
    "@google-cloud/vertexai": "^1.4.0",
    "@google-cloud/storage": "^7.6.0",
    "express": "^4.18.2"
  },
  "engines": {
    "node": ">=18.0.0"
  }
}
EOF
    
    # Create the Cloud Function implementation
    cat > "${function_dir}/index.js" << 'EOF'
const functions = require('@google-cloud/functions-framework');
const { VertexAI } = require('@google-cloud/vertexai');

// Initialize Vertex AI client
const vertexAI = new VertexAI({
  project: process.env.PROJECT_ID,
  location: 'us-central1'
});

const model = vertexAI.getGenerativeModel({
  model: 'gemini-1.5-flash-001'
});

// Cloud Function to handle repository events
functions.http('codeReviewTrigger', async (req, res) => {
  const startTime = Date.now();
  console.log(`[${new Date().toISOString()}] Code review trigger activated`);
  
  try {
    console.log('Repository event received:', JSON.stringify(req.body, null, 2));
    
    const eventData = req.body;
    
    // Process different event types
    if (eventData.eventType === 'push') {
      await handlePushEvent(eventData);
    } else if (eventData.eventType === 'pull_request') {
      await handlePullRequestEvent(eventData);
    } else {
      console.log('Unknown event type:', eventData.eventType);
    }
    
    const duration = Date.now() - startTime;
    console.log(`Code review analysis completed in ${duration}ms`);
    
    res.status(200).json({ 
      message: 'Code review analysis initiated successfully',
      timestamp: new Date().toISOString(),
      processingTime: `${duration}ms`
    });
    
  } catch (error) {
    console.error('Function execution error:', error);
    res.status(500).json({ 
      error: error.message,
      timestamp: new Date().toISOString()
    });
  }
});

async function handlePushEvent(eventData) {
  console.log('Processing push event for intelligent code review');
  
  // Extract changed files from event data
  const changedFiles = eventData.changedFiles || [];
  console.log(`Analyzing ${changedFiles.length} changed files`);
  
  for (const file of changedFiles) {
    if (file.path.match(/\.(js|ts|jsx|tsx|py|java|go)$/)) {
      await analyzeCodeFile(file);
    } else {
      console.log(`Skipping non-code file: ${file.path}`);
    }
  }
}

async function handlePullRequestEvent(eventData) {
  console.log('Processing pull request for comprehensive review');
  
  // Analyze all files in the pull request
  const pullRequestFiles = eventData.files || [];
  const analysisResults = [];
  
  console.log(`Analyzing ${pullRequestFiles.length} files in pull request`);
  
  for (const file of pullRequestFiles) {
    if (file.path.match(/\.(js|ts|jsx|tsx|py|java|go)$/)) {
      const analysis = await analyzeCodeFile(file);
      if (analysis) {
        analysisResults.push(analysis);
      }
    }
  }
  
  // Generate comprehensive review summary
  if (analysisResults.length > 0) {
    await generatePullRequestSummary(analysisResults, eventData);
  }
}

async function analyzeCodeFile(fileData) {
  const analysisPrompt = `
As an expert code reviewer and security analyst, perform a comprehensive analysis of this code file:

File: ${fileData.path}
Content:
${fileData.content}

Please analyze the code for:

1. **Security Vulnerabilities**:
   - Potential injection attacks (SQL, XSS, etc.)
   - Unsafe use of eval() or similar functions
   - Missing input validation
   - Authentication/authorization issues
   - Cryptographic problems

2. **Performance Issues**:
   - Inefficient algorithms or data structures
   - Memory leaks or excessive memory usage
   - Unnecessary computations or loops
   - Database query optimization opportunities

3. **Code Quality & Maintainability**:
   - Code complexity and readability
   - Proper error handling
   - Consistent naming conventions
   - Function/method size and responsibility
   - Code duplication

4. **Best Practices**:
   - Language-specific conventions
   - Design pattern usage
   - Documentation quality
   - Testing considerations

Provide specific, actionable feedback with:
- Line numbers where applicable
- Concrete examples of improvements
- Explanation of why each issue matters
- Suggested fixes or alternatives

Format your response as a structured analysis with clear categories and specific recommendations.
  `;
  
  try {
    console.log(`Starting AI analysis for file: ${fileData.path}`);
    
    const result = await model.generateContent(analysisPrompt);
    const analysis = result.response.text();
    
    console.log(`AI analysis completed for ${fileData.path}`);
    console.log('Analysis result:', analysis);
    
    return {
      file: fileData.path,
      analysis: analysis,
      timestamp: new Date().toISOString(),
      analysisType: 'comprehensive'
    };
  } catch (error) {
    console.error(`Analysis failed for ${fileData.path}:`, error);
    return {
      file: fileData.path,
      error: error.message,
      timestamp: new Date().toISOString(),
      analysisType: 'failed'
    };
  }
}

async function generatePullRequestSummary(analysisResults, eventData) {
  const summaryPrompt = `
Generate a comprehensive code review summary based on these individual file analyses:

${JSON.stringify(analysisResults, null, 2)}

Provide a professional code review summary that includes:

1. **Overall Assessment**:
   - Code quality rating (1-10 scale)
   - Major strengths of the code
   - Critical issues that need immediate attention

2. **Priority Issues**:
   - Security vulnerabilities (high priority)
   - Performance bottlenecks (medium priority)
   - Code quality improvements (lower priority)

3. **Recommendations**:
   - Specific next steps for the developer
   - Best practices to implement
   - Additional tools or testing needed

4. **Positive Feedback**:
   - Good practices already implemented
   - Well-written sections of code
   - Improvements from previous versions

Format the summary as a clear, constructive code review that helps the developer improve their code while maintaining a positive, educational tone.
  `;
  
  try {
    console.log('Generating comprehensive pull request summary');
    
    const result = await model.generateContent(summaryPrompt);
    const summary = result.response.text();
    
    console.log('Pull request summary generated successfully');
    console.log('Summary:', summary);
    
    // In a production system, this would post the summary as a PR comment
    // For now, we'll log it for demonstration
    return {
      summary: summary,
      analysisCount: analysisResults.length,
      timestamp: new Date().toISOString()
    };
  } catch (error) {
    console.error('Summary generation failed:', error);
    return null;
  }
}
EOF
    
    # Deploy the Cloud Function
    info "Deploying Cloud Function..."
    
    cd "${function_dir}"
    
    if gcloud functions deploy "${FUNCTION_NAME}" \
        --gen2 \
        --runtime=nodejs20 \
        --region="${REGION}" \
        --source=. \
        --entry-point=codeReviewTrigger \
        --trigger=http \
        --allow-unauthenticated \
        --timeout=540s \
        --memory=1Gi \
        --set-env-vars=PROJECT_ID="${PROJECT_ID}" \
        --quiet; then
        success "Cloud Function deployed successfully"
    else
        error "Failed to deploy Cloud Function"
        exit 1
    fi
    
    # Get function URL
    local function_url
    function_url=$(gcloud functions describe "${FUNCTION_NAME}" \
        --region="${REGION}" \
        --format="value(serviceConfig.uri)")
    export FUNCTION_URL="$function_url"
    
    info "Function URL: ${FUNCTION_URL}"
    
    cd - > /dev/null
}

# Create Firebase Studio configuration
create_firebase_studio_config() {
    info "Creating Firebase Studio agent configuration..."
    
    # Create agent configuration file
    cat > "${SCRIPT_DIR}/../code-review-agent-config.json" << EOF
{
  "agent_name": "IntelligentCodeReviewer",
  "description": "AI agent for automated code quality analysis and security review",
  "capabilities": [
    "code_analysis",
    "security_review",
    "performance_optimization",
    "best_practices_enforcement",
    "documentation_review"
  ],
  "model_config": {
    "model": "gemini-1.5-flash-001",
    "temperature": 0.3,
    "max_tokens": 4096,
    "top_p": 0.8
  },
  "analysis_patterns": [
    "security_vulnerabilities",
    "performance_issues",
    "code_smells",
    "documentation_gaps",
    "testing_coverage",
    "maintainability_issues"
  ],
  "supported_languages": [
    "javascript",
    "typescript",
    "python",
    "java",
    "go"
  ],
  "integration": {
    "source_repository": "${REPOSITORY_NAME}",
    "trigger_function": "${FUNCTION_NAME}",
    "project_id": "${PROJECT_ID}"
  }
}
EOF
    
    # Create Firebase Studio agent template
    cat > "${SCRIPT_DIR}/../firebase-studio-agent.js" << 'EOF'
// Intelligent Code Review Agent Implementation for Firebase Studio
// This template demonstrates the agent structure for Firebase Studio

import { VertexAI } from '@google-cloud/vertexai';

class IntelligentCodeReviewer {
  constructor() {
    this.vertexAI = new VertexAI({
      project: process.env.PROJECT_ID,
      location: 'us-central1'
    });
    
    this.model = this.vertexAI.getGenerativeModel({
      model: 'gemini-1.5-flash-001',
      generationConfig: {
        temperature: 0.3,
        maxOutputTokens: 4096,
        topP: 0.8
      }
    });
  }

  async analyzeCode(codeContent, fileName, changeType) {
    const analysisPrompt = `
      As an expert code reviewer, analyze the following code for:
      1. Security vulnerabilities and potential risks
      2. Performance optimization opportunities
      3. Code quality and maintainability issues
      4. Adherence to best practices for the detected language
      5. Documentation and testing recommendations
      
      File: ${fileName}
      Change Type: ${changeType}
      
      Code:
      ${codeContent}
      
      Provide specific, actionable feedback with line numbers and examples.
      Format your response as structured analysis with clear recommendations.
    `;
    
    try {
      const result = await this.model.generateContent(analysisPrompt);
      return this.parseAnalysisResult(result.response.text());
    } catch (error) {
      console.error('Analysis error:', error);
      throw error;
    }
  }
  
  parseAnalysisResult(rawResult) {
    // Structure the AI analysis result
    return {
      analysis: rawResult,
      timestamp: new Date().toISOString(),
      reviewer: 'AI Code Review Agent',
      confidence: 'high'
    };
  }
  
  async generateReviewComment(analysis, pullRequestContext) {
    const commentPrompt = `
      Based on this code analysis, generate a professional, constructive 
      code review comment that helps the developer improve their code:
      
      Analysis: ${JSON.stringify(analysis)}
      Context: ${pullRequestContext}
      
      Make the feedback specific, educational, and encouraging.
      Focus on helping the developer learn and improve.
    `;
    
    try {
      const result = await this.model.generateContent(commentPrompt);
      return result.response.text();
    } catch (error) {
      console.error('Comment generation error:', error);
      throw error;
    }
  }
}

export default IntelligentCodeReviewer;
EOF
    
    success "Firebase Studio configuration created"
    
    # Display Firebase Studio setup instructions
    info "Firebase Studio Setup Instructions:"
    echo -e "${YELLOW}"
    echo "1. Open Firebase Studio: https://studio.firebase.google.com"
    echo "2. Create new workspace or import project: ${PROJECT_ID}"
    echo "3. Use the agent configuration file: code-review-agent-config.json"
    echo "4. Implement the agent using: firebase-studio-agent.js"
    echo "5. Configure integration with Cloud Function: ${FUNCTION_NAME}"
    echo -e "${NC}"
}

# Create test webhook script
create_test_scripts() {
    info "Creating test and validation scripts..."
    
    # Create webhook test script
    cat > "${SCRIPT_DIR}/test-webhook.sh" << EOF
#!/bin/bash

# Test script for code review automation webhook
set -euo pipefail

FUNCTION_URL="\${1:-${FUNCTION_URL}}"

if [[ -z "\$FUNCTION_URL" ]]; then
    echo "Error: Function URL not provided"
    echo "Usage: \$0 <FUNCTION_URL>"
    exit 1
fi

echo "Testing code review automation webhook..."
echo "Function URL: \$FUNCTION_URL"

# Test with sample push event
echo "Sending test push event..."
curl -X POST "\$FUNCTION_URL" \\
  -H "Content-Type: application/json" \\
  -d '{
    "eventType": "push",
    "repository": "${REPOSITORY_NAME}",
    "changedFiles": [
      {
        "path": "src/components/UserManager.js",
        "content": "function UserManager() { var users = []; function addUser(name, email) { users.push({name: name, email: email, id: Math.random()}); } return { addUser: addUser }; }"
      }
    ]
  }'

echo -e "\\n\\nTest webhook event sent successfully!"
echo "Check Cloud Function logs for analysis results:"
echo "gcloud functions logs read ${FUNCTION_NAME} --region=${REGION} --limit=10"
EOF
    
    chmod +x "${SCRIPT_DIR}/test-webhook.sh"
    
    # Create validation script
    cat > "${SCRIPT_DIR}/validate-deployment.sh" << EOF
#!/bin/bash

# Validation script for code review automation deployment
set -euo pipefail

echo "Validating code review automation deployment..."

# Check Cloud Function status
echo "Checking Cloud Function status..."
if gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" --quiet > /dev/null 2>&1; then
    echo "✅ Cloud Function ${FUNCTION_NAME} is deployed"
    
    # Get function URL and test
    FUNCTION_URL=\$(gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" --format="value(serviceConfig.uri)")
    echo "Function URL: \$FUNCTION_URL"
    
    # Test function accessibility
    if curl -s -o /dev/null -w "%{http_code}" "\$FUNCTION_URL" | grep -q "200\\|405"; then
        echo "✅ Cloud Function is accessible"
    else
        echo "❌ Cloud Function is not accessible"
    fi
else
    echo "❌ Cloud Function ${FUNCTION_NAME} not found"
fi

# Check Cloud Source Repository
echo "Checking Cloud Source Repository..."
if gcloud source repos describe "${REPOSITORY_NAME}" --quiet > /dev/null 2>&1; then
    echo "✅ Repository ${REPOSITORY_NAME} exists"
    
    # Check repository contents
    REPO_URL=\$(gcloud source repos describe "${REPOSITORY_NAME}" --format="value(url)")
    echo "Repository URL: \$REPO_URL"
else
    echo "❌ Repository ${REPOSITORY_NAME} not found"
fi

# Check required APIs
echo "Checking required APIs..."
required_apis=(
    "sourcerepo.googleapis.com"
    "cloudfunctions.googleapis.com"
    "aiplatform.googleapis.com"
    "firebase.googleapis.com"
)

for api in "\${required_apis[@]}"; do
    if gcloud services list --enabled --filter="name:\$api" --quiet | grep -q "\$api"; then
        echo "✅ \$api is enabled"
    else
        echo "❌ \$api is not enabled"
    fi
done

echo "Validation completed!"
EOF
    
    chmod +x "${SCRIPT_DIR}/validate-deployment.sh"
    
    success "Test and validation scripts created"
}

# Display deployment summary
show_deployment_summary() {
    echo -e "\n${GREEN}"
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║                   Deployment Completed!                   ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    echo -e "${BLUE}Deployment Summary:${NC}"
    echo "• Project ID: ${PROJECT_ID}"
    echo "• Region: ${REGION}"
    echo "• Repository: ${REPOSITORY_NAME}"
    echo "• Cloud Function: ${FUNCTION_NAME}"
    echo "• Function URL: ${FUNCTION_URL}"
    echo ""
    
    echo -e "${BLUE}Next Steps:${NC}"
    echo "1. Access Firebase Studio: https://studio.firebase.google.com"
    echo "2. Create workspace for project: ${PROJECT_ID}"
    echo "3. Use agent configuration: code-review-agent-config.json"
    echo "4. Test the system: ./test-webhook.sh"
    echo "5. Validate deployment: ./validate-deployment.sh"
    echo ""
    
    echo -e "${BLUE}Repository URLs:${NC}"
    echo "• Clone URL: ${REPO_URL}"
    echo "• Console: https://console.cloud.google.com/source/repos"
    echo ""
    
    echo -e "${BLUE}Monitoring:${NC}"
    echo "• Function logs: gcloud functions logs read ${FUNCTION_NAME} --region=${REGION}"
    echo "• Cloud Console: https://console.cloud.google.com/functions"
    echo ""
    
    echo -e "${YELLOW}Important Notes:${NC}"
    echo "• Firebase Studio is in preview - features may change"
    echo "• Review the generated configuration files before production use"
    echo "• Configure repository webhooks for automatic triggers"
    echo "• Monitor Vertex AI usage for cost optimization"
    echo ""
    
    echo "Deployment log saved to: ${LOG_FILE}"
}

# Main deployment flow
main() {
    show_banner
    
    info "Starting deployment at $(date)"
    info "Log file: ${LOG_FILE}"
    
    check_prerequisites
    setup_project
    enable_apis
    create_repository
    initialize_repository
    create_cloud_function
    create_firebase_studio_config
    create_test_scripts
    
    show_deployment_summary
    
    success "Code review automation system deployed successfully!"
}

# Execute main function
main "$@"