#!/bin/bash

# AWS Amplify DataStore Offline-First Mobile Application Deployment Script
# This script deploys the complete infrastructure for an offline-first mobile application
# using AWS Amplify DataStore with AppSync, DynamoDB, and Cognito

set -e
set -o pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_FILE="/tmp/amplify-datastore-deploy-$(date +%Y%m%d_%H%M%S).log"
DEPLOYMENT_STATE_FILE="/tmp/amplify-datastore-state.json"

# Function to log messages
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}[INFO] $1${NC}" | tee -a "$LOG_FILE"
}

log_warn() {
    echo -e "${YELLOW}[WARN] $1${NC}" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR] $1${NC}" | tee -a "$LOG_FILE"
}

# Error handling function
error_exit() {
    log_error "$1"
    log_error "Check the log file for details: $LOG_FILE"
    cleanup_on_error
    exit 1
}

# Cleanup function for error scenarios
cleanup_on_error() {
    log_warn "Performing cleanup due to error..."
    
    # Clean up any temporary files created
    if [[ -f "$DEPLOYMENT_STATE_FILE" ]]; then
        rm -f "$DEPLOYMENT_STATE_FILE"
    fi
    
    # If project was created but deployment failed, offer to clean up
    if [[ -n "$APP_NAME" && -d "$PROJECT_DIR" ]]; then
        log_warn "Project directory exists at: $PROJECT_DIR"
        log_warn "You may want to run './destroy.sh' to clean up resources."
    fi
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed and configured
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI is not installed. Please install it first."
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS credentials are not configured. Please configure them first."
    fi
    
    # Check if Node.js is installed
    if ! command -v node &> /dev/null; then
        error_exit "Node.js is not installed. Please install Node.js 18+ first."
    fi
    
    # Check Node.js version
    NODE_VERSION=$(node --version | cut -d'.' -f1 | sed 's/v//')
    if [[ $NODE_VERSION -lt 18 ]]; then
        error_exit "Node.js version 18+ is required. Current version: $(node --version)"
    fi
    
    # Check if npm is installed
    if ! command -v npm &> /dev/null; then
        error_exit "npm is not installed. Please install npm first."
    fi
    
    # Check if Amplify CLI is installed
    if ! command -v amplify &> /dev/null; then
        log_warn "Amplify CLI is not installed. Installing it now..."
        npm install -g @aws-amplify/cli || error_exit "Failed to install Amplify CLI"
    fi
    
    # Check if React Native CLI is installed
    if ! command -v react-native &> /dev/null; then
        log_warn "React Native CLI is not installed. Installing it now..."
        npm install -g react-native-cli || error_exit "Failed to install React Native CLI"
    fi
    
    log "✅ Prerequisites check completed successfully"
}

# Function to initialize environment variables
initialize_environment() {
    log "Initializing environment variables..."
    
    # Set AWS region
    export AWS_REGION=$(aws configure get region)
    if [[ -z "$AWS_REGION" ]]; then
        export AWS_REGION="us-east-1"
        log_warn "AWS region not configured, defaulting to us-east-1"
    fi
    
    # Get AWS Account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    if [[ -z "$AWS_ACCOUNT_ID" ]]; then
        error_exit "Failed to get AWS Account ID"
    fi
    
    # Generate unique identifiers
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    export APP_NAME="offline-tasks-${RANDOM_SUFFIX}"
    export PROJECT_DIR="${HOME}/amplify-offline-app"
    
    # Store deployment state
    cat > "$DEPLOYMENT_STATE_FILE" << EOF
{
    "app_name": "$APP_NAME",
    "project_dir": "$PROJECT_DIR",
    "aws_region": "$AWS_REGION",
    "aws_account_id": "$AWS_ACCOUNT_ID",
    "random_suffix": "$RANDOM_SUFFIX"
}
EOF
    
    log_info "App Name: $APP_NAME"
    log_info "Project Directory: $PROJECT_DIR"
    log_info "AWS Region: $AWS_REGION"
    log_info "AWS Account ID: $AWS_ACCOUNT_ID"
    log "✅ Environment variables initialized successfully"
}

# Function to create React Native project
create_react_native_project() {
    log "Creating React Native project..."
    
    # Clean up existing project directory if it exists
    if [[ -d "$PROJECT_DIR" ]]; then
        log_warn "Project directory already exists. Removing it..."
        rm -rf "$PROJECT_DIR"
    fi
    
    # Create the project directory
    mkdir -p "$(dirname "$PROJECT_DIR")"
    
    # Initialize React Native project
    log_info "Initializing React Native project with TypeScript template..."
    npx react-native init "$APP_NAME" --template react-native-template-typescript >> "$LOG_FILE" 2>&1 || {
        error_exit "Failed to create React Native project"
    }
    
    # Move to project directory
    mv "${HOME}/${APP_NAME}" "$PROJECT_DIR"
    cd "$PROJECT_DIR"
    
    log "✅ React Native project created successfully"
}

# Function to initialize Amplify
initialize_amplify() {
    log "Initializing Amplify..."
    
    cd "$PROJECT_DIR"
    
    # Initialize Amplify with default configuration
    log_info "Running amplify init..."
    amplify init --yes >> "$LOG_FILE" 2>&1 || {
        error_exit "Failed to initialize Amplify"
    }
    
    log "✅ Amplify initialized successfully"
}

# Function to configure authentication
configure_authentication() {
    log "Configuring authentication..."
    
    cd "$PROJECT_DIR"
    
    # Add authentication with default configuration
    log_info "Adding Cognito authentication..."
    amplify add auth << EOF >> "$LOG_FILE" 2>&1 || {
        error_exit "Failed to configure authentication"
    }
EOF
    
    log "✅ Authentication configured successfully"
}

# Function to configure API and DataStore
configure_api_datastore() {
    log "Configuring API and DataStore..."
    
    cd "$PROJECT_DIR"
    
    # Add API with DataStore configuration
    log_info "Adding AppSync API with DataStore..."
    amplify add api << EOF >> "$LOG_FILE" 2>&1 || {
        error_exit "Failed to configure API and DataStore"
    }
? Select from one of the below mentioned services: GraphQL
? Here is the GraphQL API that we will create. Select a setting to edit or continue Continue
? Choose a schema template: Single object with fields (e.g., "Todo" with ID, name, description)
? Do you want to edit the schema now? Yes
EOF
    
    log "✅ API and DataStore configured successfully"
}

# Function to create GraphQL schema
create_graphql_schema() {
    log "Creating GraphQL schema..."
    
    cd "$PROJECT_DIR"
    
    # Find the schema file
    SCHEMA_FILE=$(find amplify/backend/api -name "schema.graphql" | head -1)
    if [[ -z "$SCHEMA_FILE" ]]; then
        error_exit "Could not find schema.graphql file"
    fi
    
    # Create comprehensive schema
    cat > "$SCHEMA_FILE" << 'EOF'
type Task @model @auth(rules: [{ allow: owner }]) {
  id: ID!
  title: String!
  description: String
  priority: Priority!
  status: Status!
  dueDate: AWSDateTime
  tags: [String]
  createdAt: AWSDateTime
  updatedAt: AWSDateTime
  owner: String @auth(rules: [{ allow: owner, operations: [read] }])
}

type Project @model @auth(rules: [{ allow: owner }]) {
  id: ID!
  name: String!
  description: String
  color: String
  tasks: [Task] @hasMany(indexName: "byProject", fields: ["id"])
  createdAt: AWSDateTime
  updatedAt: AWSDateTime
  owner: String @auth(rules: [{ allow: owner, operations: [read] }])
}

enum Priority {
  LOW
  MEDIUM
  HIGH
  URGENT
}

enum Status {
  PENDING
  IN_PROGRESS
  COMPLETED
  CANCELLED
}
EOF
    
    log "✅ GraphQL schema created successfully"
}

# Function to deploy backend resources
deploy_backend() {
    log "Deploying backend resources..."
    
    cd "$PROJECT_DIR"
    
    # Deploy the backend
    log_info "Pushing changes to AWS (this may take several minutes)..."
    amplify push --yes >> "$LOG_FILE" 2>&1 || {
        error_exit "Failed to deploy backend resources"
    }
    
    log "✅ Backend resources deployed successfully"
}

# Function to install dependencies
install_dependencies() {
    log "Installing project dependencies..."
    
    cd "$PROJECT_DIR"
    
    # Install Amplify dependencies
    log_info "Installing AWS Amplify dependencies..."
    npm install aws-amplify @aws-amplify/datastore >> "$LOG_FILE" 2>&1 || {
        error_exit "Failed to install Amplify dependencies"
    }
    
    # Install React Native specific dependencies
    log_info "Installing React Native dependencies..."
    npm install react-native-get-random-values @react-native-async-storage/async-storage >> "$LOG_FILE" 2>&1 || {
        error_exit "Failed to install React Native dependencies"
    }
    
    # Install iOS pods if on macOS
    if [[ "$OSTYPE" == "darwin"* ]]; then
        log_info "Installing iOS pods..."
        cd ios && pod install >> "$LOG_FILE" 2>&1 && cd .. || {
            log_warn "Failed to install iOS pods. This is expected on non-macOS systems."
        }
    fi
    
    log "✅ Dependencies installed successfully"
}

# Function to create DataStore configuration
create_datastore_config() {
    log "Creating DataStore configuration..."
    
    cd "$PROJECT_DIR"
    
    # Create src directory if it doesn't exist
    mkdir -p src
    
    # Create DataStore configuration
    cat > src/datastore-config.js << 'EOF'
import { DataStore, syncExpression } from 'aws-amplify/datastore';
import { Task, Project } from '../models';

// Configure selective sync based on user preferences
const configureSyncExpressions = (userPreferences) => {
  return [
    syncExpression(Task, () => {
      const thirtyDaysAgo = new Date();
      thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);
      
      return (task) => task.and(taskFilters => [
        taskFilters.createdAt.gt(thirtyDaysAgo.toISOString()),
        taskFilters.status.ne('CANCELLED')
      ]);
    }),
    syncExpression(Project, () => {
      return (project) => project.name.ne('Archived');
    })
  ];
};

export const configureDataStore = (userPreferences = {}) => {
  DataStore.configure({
    syncExpressions: configureSyncExpressions(userPreferences),
    maxRecordsToSync: 10000,
    syncPageSize: 1000,
    fullSyncInterval: 24 * 60 * 60 * 1000, // 24 hours
    errorHandler: (error) => {
      console.warn('DataStore sync error:', error);
    }
  });
};
EOF
    
    log "✅ DataStore configuration created successfully"
}

# Function to create data service layer
create_data_service() {
    log "Creating data service layer..."
    
    cd "$PROJECT_DIR"
    
    # Create services directory
    mkdir -p src/services
    
    # Create data service
    cat > src/services/DataService.js << 'EOF'
import { DataStore, Predicates } from 'aws-amplify/datastore';
import { Task, Project, Priority, Status } from '../models';

export class DataService {
  // Task operations
  static async createTask(taskData) {
    try {
      const task = await DataStore.save(new Task({
        title: taskData.title,
        description: taskData.description,
        priority: taskData.priority || Priority.MEDIUM,
        status: Status.PENDING,
        dueDate: taskData.dueDate,
        tags: taskData.tags || [],
        projectId: taskData.projectId
      }));
      return task;
    } catch (error) {
      console.error('Error creating task:', error);
      throw error;
    }
  }

  static async getTasks(filters = {}) {
    try {
      let predicate = Predicates.ALL;
      
      if (filters.status) {
        predicate = (task) => task.status.eq(filters.status);
      }
      
      if (filters.priority) {
        predicate = predicate === Predicates.ALL 
          ? (task) => task.priority.eq(filters.priority)
          : (task) => task.and(t => [
              t.status.eq(filters.status),
              t.priority.eq(filters.priority)
            ]);
      }
      
      return await DataStore.query(Task, predicate);
    } catch (error) {
      console.error('Error fetching tasks:', error);
      throw error;
    }
  }

  static async updateTask(taskId, updates) {
    try {
      const original = await DataStore.query(Task, taskId);
      if (!original) {
        throw new Error('Task not found');
      }
      
      const updated = await DataStore.save(
        Task.copyOf(original, updated => {
          Object.assign(updated, updates);
        })
      );
      return updated;
    } catch (error) {
      console.error('Error updating task:', error);
      throw error;
    }
  }

  static async deleteTask(taskId) {
    try {
      const task = await DataStore.query(Task, taskId);
      if (task) {
        await DataStore.delete(task);
      }
    } catch (error) {
      console.error('Error deleting task:', error);
      throw error;
    }
  }

  // Project operations
  static async createProject(projectData) {
    try {
      const project = await DataStore.save(new Project({
        name: projectData.name,
        description: projectData.description,
        color: projectData.color || '#007AFF'
      }));
      return project;
    } catch (error) {
      console.error('Error creating project:', error);
      throw error;
    }
  }

  static async getProjects() {
    try {
      return await DataStore.query(Project);
    } catch (error) {
      console.error('Error fetching projects:', error);
      throw error;
    }
  }

  // Sync management
  static async forceSyncNow() {
    try {
      await DataStore.stop();
      await DataStore.start();
    } catch (error) {
      console.error('Error forcing sync:', error);
      throw error;
    }
  }

  static async clearLocalData() {
    try {
      await DataStore.clear();
    } catch (error) {
      console.error('Error clearing local data:', error);
      throw error;
    }
  }
}
EOF
    
    log "✅ Data service layer created successfully"
}

# Function to verify deployment
verify_deployment() {
    log "Verifying deployment..."
    
    cd "$PROJECT_DIR"
    
    # Check Amplify status
    log_info "Checking Amplify status..."
    amplify status >> "$LOG_FILE" 2>&1 || {
        error_exit "Failed to get Amplify status"
    }
    
    # Check if GraphQL API was created
    log_info "Verifying GraphQL API..."
    APPSYNC_APIS=$(aws appsync list-graphql-apis --region "$AWS_REGION" --query 'graphqlApis[?contains(name, `'"$APP_NAME"'`)].{Name:name,ApiId:apiId}' --output table)
    if [[ -n "$APPSYNC_APIS" ]]; then
        log_info "GraphQL API created successfully"
        echo "$APPSYNC_APIS" | tee -a "$LOG_FILE"
    else
        log_warn "No GraphQL API found with name containing: $APP_NAME"
    fi
    
    # Check if DynamoDB tables were created
    log_info "Verifying DynamoDB tables..."
    DYNAMODB_TABLES=$(aws dynamodb list-tables --region "$AWS_REGION" --query 'TableNames[?contains(@, `Task`) || contains(@, `Project`)]' --output table)
    if [[ -n "$DYNAMODB_TABLES" ]]; then
        log_info "DynamoDB tables created successfully"
        echo "$DYNAMODB_TABLES" | tee -a "$LOG_FILE"
    else
        log_warn "No DynamoDB tables found for Task or Project"
    fi
    
    # Check if Cognito User Pool was created
    log_info "Verifying Cognito User Pool..."
    COGNITO_POOLS=$(aws cognito-idp list-user-pools --region "$AWS_REGION" --max-results 10 --query 'UserPools[?contains(Name, `'"$APP_NAME"'`)].{Name:Name,Id:Id}' --output table)
    if [[ -n "$COGNITO_POOLS" ]]; then
        log_info "Cognito User Pool created successfully"
        echo "$COGNITO_POOLS" | tee -a "$LOG_FILE"
    else
        log_warn "No Cognito User Pool found with name containing: $APP_NAME"
    fi
    
    log "✅ Deployment verification completed"
}

# Function to display deployment summary
display_summary() {
    log "Deployment Summary"
    log "=================="
    log_info "App Name: $APP_NAME"
    log_info "Project Directory: $PROJECT_DIR"
    log_info "AWS Region: $AWS_REGION"
    log_info "AWS Account ID: $AWS_ACCOUNT_ID"
    log_info "Log File: $LOG_FILE"
    log_info "Deployment State: $DEPLOYMENT_STATE_FILE"
    log ""
    log "Next Steps:"
    log "1. Navigate to the project directory: cd $PROJECT_DIR"
    log "2. Start the React Native development server: npm start"
    log "3. Run the app on iOS: npx react-native run-ios"
    log "4. Run the app on Android: npx react-native run-android"
    log ""
    log "To clean up resources, run: ./destroy.sh"
    log ""
    log "✅ Deployment completed successfully!"
}

# Main execution function
main() {
    log "Starting AWS Amplify DataStore Offline-First Mobile Application deployment..."
    log "Log file: $LOG_FILE"
    
    # Set up signal handlers for cleanup
    trap cleanup_on_error ERR
    trap cleanup_on_error INT
    
    # Execute deployment steps
    check_prerequisites
    initialize_environment
    create_react_native_project
    initialize_amplify
    configure_authentication
    configure_api_datastore
    create_graphql_schema
    deploy_backend
    install_dependencies
    create_datastore_config
    create_data_service
    verify_deployment
    display_summary
    
    log "Deployment completed successfully!"
}

# Execute main function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi