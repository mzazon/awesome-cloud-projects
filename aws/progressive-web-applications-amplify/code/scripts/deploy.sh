#!/bin/bash

# Progressive Web Applications with AWS Amplify - Deployment Script
# This script deploys the complete PWA infrastructure using AWS Amplify

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command_exists aws; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check Node.js
    if ! command_exists node; then
        log_error "Node.js is not installed. Please install Node.js 18+ first."
        exit 1
    fi
    
    # Check npm
    if ! command_exists npm; then
        log_error "npm is not installed. Please install npm first."
        exit 1
    fi
    
    # Check Amplify CLI
    if ! command_exists amplify; then
        log_warning "Amplify CLI not found. Installing globally..."
        npm install -g @aws-amplify/cli
        if [ $? -ne 0 ]; then
            log_error "Failed to install Amplify CLI. Please install manually: npm install -g @aws-amplify/cli"
            exit 1
        fi
    fi
    
    # Check Git
    if ! command_exists git; then
        log_error "Git is not installed. Please install Git first."
        exit 1
    fi
    
    # Verify Node.js version
    NODE_VERSION=$(node --version | cut -d'v' -f2 | cut -d'.' -f1)
    if [ "$NODE_VERSION" -lt 18 ]; then
        log_error "Node.js version 18+ is required. Current version: $(node --version)"
        exit 1
    fi
    
    log_success "All prerequisites met"
}

# Function to initialize environment variables
initialize_environment() {
    log_info "Setting up environment variables..."
    
    # Set AWS region
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        log_error "AWS region not configured. Please set a default region."
        exit 1
    fi
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo $(date +%s | tail -c 6))
    
    export APP_NAME="full-stack-pwa-${RANDOM_SUFFIX}"
    export PROJECT_NAME="fullstack-pwa-${RANDOM_SUFFIX}"
    
    # Save environment variables to file for cleanup script
    cat > .env << EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
APP_NAME=${APP_NAME}
PROJECT_NAME=${PROJECT_NAME}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
EOF
    
    log_success "Environment variables configured"
    log_info "Project Name: ${PROJECT_NAME}"
    log_info "App Name: ${APP_NAME}"
    log_info "AWS Region: ${AWS_REGION}"
}

# Function to create React project
create_react_project() {
    log_info "Creating React TypeScript project..."
    
    # Create project directory
    mkdir -p ~/${PROJECT_NAME}
    cd ~/${PROJECT_NAME}
    
    # Initialize React application
    npx create-react-app . --template typescript
    
    if [ $? -ne 0 ]; then
        log_error "Failed to create React application"
        exit 1
    fi
    
    # Install Amplify and PWA dependencies
    log_info "Installing Amplify and PWA dependencies..."
    npm install aws-amplify @aws-amplify/ui-react \
        workbox-webpack-plugin workbox-precaching \
        workbox-routing workbox-strategies
    
    if [ $? -ne 0 ]; then
        log_error "Failed to install dependencies"
        exit 1
    fi
    
    log_success "React project created successfully"
}

# Function to initialize Amplify backend
initialize_amplify_backend() {
    log_info "Initializing Amplify backend..."
    
    cd ~/${PROJECT_NAME}
    
    # Create amplify init configuration
    cat > amplify-init.json << EOF
{
  "projectName": "${PROJECT_NAME}",
  "appName": "${APP_NAME}",
  "envName": "dev",
  "defaultEditor": "code",
  "appType": "javascript",
  "framework": "react",
  "srcDir": "src",
  "distDir": "build",
  "buildDir": "build",
  "buildCommand": "npm run build",
  "startCommand": "npm start"
}
EOF
    
    # Initialize Amplify with configuration
    amplify init --yes --amplify amplify-init.json
    
    if [ $? -ne 0 ]; then
        log_error "Failed to initialize Amplify backend"
        exit 1
    fi
    
    # Clean up temporary config file
    rm -f amplify-init.json
    
    log_success "Amplify backend initialized"
}

# Function to add authentication
add_authentication() {
    log_info "Adding authentication with Cognito..."
    
    cd ~/${PROJECT_NAME}
    
    # Create auth configuration
    cat > auth-config.json << EOF
{
  "resourceName": "amplifyauth",
  "serviceConfiguration": {
    "serviceName": "Cognito",
    "userPoolConfiguration": {
      "signinMethod": "USERNAME",
      "requiredSignupAttributes": ["EMAIL"]
    }
  }
}
EOF
    
    # Add authentication
    amplify add auth --headless --amplify auth-config.json
    
    if [ $? -ne 0 ]; then
        log_error "Failed to add authentication"
        exit 1
    fi
    
    # Clean up temporary config file
    rm -f auth-config.json
    
    log_success "Authentication configured"
}

# Function to add GraphQL API
add_graphql_api() {
    log_info "Adding GraphQL API with AppSync..."
    
    cd ~/${PROJECT_NAME}
    
    # Create API configuration
    cat > api-config.json << EOF
{
  "serviceConfiguration": {
    "serviceName": "AppSync",
    "apiName": "${PROJECT_NAME}api",
    "transformSchema": "amplify/backend/api/${PROJECT_NAME}api/schema.graphql",
    "defaultAuthType": {
      "mode": "AMAZON_COGNITO_USER_POOLS"
    }
  }
}
EOF
    
    # Add API
    amplify add api --headless --amplify api-config.json
    
    if [ $? -ne 0 ]; then
        log_error "Failed to add GraphQL API"
        exit 1
    fi
    
    # Create GraphQL schema
    mkdir -p amplify/backend/api/${PROJECT_NAME}api
    cat > amplify/backend/api/${PROJECT_NAME}api/schema.graphql << 'EOF'
type Task @model @auth(rules: [{allow: owner}]) {
  id: ID!
  title: String!
  description: String
  completed: Boolean!
  priority: Priority!
  dueDate: AWSDate
  createdAt: AWSDateTime!
  updatedAt: AWSDateTime!
}

enum Priority {
  LOW
  MEDIUM
  HIGH
}

type Subscription {
  onTaskUpdate: Task @aws_subscribe(mutations: ["updateTask"])
}
EOF
    
    # Clean up temporary config file
    rm -f api-config.json
    
    log_success "GraphQL API configured"
}

# Function to add S3 storage
add_s3_storage() {
    log_info "Adding S3 storage..."
    
    cd ~/${PROJECT_NAME}
    
    # Create storage configuration
    cat > storage-config.json << EOF
{
  "resourceName": "TaskAttachments",
  "serviceConfiguration": {
    "serviceName": "S3",
    "bucketName": "${PROJECT_NAME}-attachments-${RANDOM_SUFFIX}",
    "authAccess": ["CREATE_AND_UPDATE", "READ", "DELETE"],
    "guestAccess": ["READ"]
  }
}
EOF
    
    # Add storage
    amplify add storage --headless --amplify storage-config.json
    
    if [ $? -ne 0 ]; then
        log_error "Failed to add S3 storage"
        exit 1
    fi
    
    # Clean up temporary config file
    rm -f storage-config.json
    
    log_success "S3 storage configured"
}

# Function to deploy backend services
deploy_backend_services() {
    log_info "Deploying backend services..."
    
    cd ~/${PROJECT_NAME}
    
    # Deploy all backend resources
    amplify push --yes --codegen --frontend javascript
    
    if [ $? -ne 0 ]; then
        log_error "Failed to deploy backend services"
        exit 1
    fi
    
    log_success "Backend services deployed"
}

# Function to create application components
create_application_components() {
    log_info "Creating application components..."
    
    cd ~/${PROJECT_NAME}
    
    # Configure Amplify in src/index.tsx
    cat > src/index.tsx << 'EOF'
import React from 'react';
import ReactDOM from 'react-dom/client';
import './index.css';
import App from './App';
import reportWebVitals from './reportWebVitals';
import { Amplify } from 'aws-amplify';
import awsExports from './aws-exports';

// Configure Amplify
Amplify.configure(awsExports);

const root = ReactDOM.createRoot(
  document.getElementById('root') as HTMLElement
);
root.render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
);

reportWebVitals();
EOF
    
    # Create components directory
    mkdir -p src/components
    
    # Create main App component
    cat > src/App.tsx << 'EOF'
import React, { useState, useEffect } from 'react';
import { withAuthenticator } from '@aws-amplify/ui-react';
import { Auth, DataStore } from 'aws-amplify';
import { Task, Priority } from './models';
import TaskList from './components/TaskList';
import TaskForm from './components/TaskForm';
import NetworkStatus from './components/NetworkStatus';
import '@aws-amplify/ui-react/styles.css';
import './App.css';

function App({ signOut, user }: any) {
  const [tasks, setTasks] = useState<Task[]>([]);
  const [isOnline, setIsOnline] = useState(navigator.onLine);
  const [syncStatus, setSyncStatus] = useState<string>('synced');

  useEffect(() => {
    // Listen for network status changes
    const handleOnline = () => setIsOnline(true);
    const handleOffline = () => setIsOnline(false);
    
    window.addEventListener('online', handleOnline);
    window.addEventListener('offline', handleOffline);
    
    return () => {
      window.removeEventListener('online', handleOnline);
      window.removeEventListener('offline', handleOffline);
    };
  }, []);

  useEffect(() => {
    // Subscribe to DataStore changes
    const subscription = DataStore.observe(Task).subscribe(msg => {
      console.log('Task updated:', msg.model, msg.opType, msg.element);
      fetchTasks();
    });

    // Start DataStore and sync
    DataStore.start().then(() => {
      setSyncStatus('synced');
      fetchTasks();
    });

    return () => subscription.unsubscribe();
  }, []);

  const fetchTasks = async () => {
    try {
      const taskList = await DataStore.query(Task);
      setTasks(taskList.sort((a, b) => 
        new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime()
      ));
    } catch (error) {
      console.error('Error fetching tasks:', error);
    }
  };

  const handleTaskCreate = async (taskData: any) => {
    try {
      setSyncStatus('syncing');
      await DataStore.save(new Task(taskData));
      setSyncStatus('synced');
    } catch (error) {
      console.error('Error creating task:', error);
      setSyncStatus('error');
    }
  };

  const handleTaskUpdate = async (task: Task) => {
    try {
      setSyncStatus('syncing');
      await DataStore.save(Task.copyOf(task, updated => {
        updated.completed = !updated.completed;
      }));
      setSyncStatus('synced');
    } catch (error) {
      console.error('Error updating task:', error);
      setSyncStatus('error');
    }
  };

  const handleTaskDelete = async (task: Task) => {
    try {
      setSyncStatus('syncing');
      await DataStore.delete(task);
      setSyncStatus('synced');
    } catch (error) {
      console.error('Error deleting task:', error);
      setSyncStatus('error');
    }
  };

  return (
    <div className="App">
      <header className="App-header">
        <h1>Full-Stack PWA Task Manager</h1>
        <div className="user-info">
          <span>Welcome, {user.username}!</span>
          <button onClick={signOut} className="sign-out-button">
            Sign Out
          </button>
        </div>
      </header>
      
      <NetworkStatus isOnline={isOnline} syncStatus={syncStatus} />
      
      <main className="App-main">
        <TaskForm onTaskCreate={handleTaskCreate} />
        <TaskList 
          tasks={tasks} 
          onTaskUpdate={handleTaskUpdate}
          onTaskDelete={handleTaskDelete}
        />
      </main>
    </div>
  );
}

export default withAuthenticator(App);
EOF
    
    log_success "Application components created"
}

# Function to create React components
create_react_components() {
    log_info "Creating React components..."
    
    cd ~/${PROJECT_NAME}
    
    # Create TaskList component
    cat > src/components/TaskList.tsx << 'EOF'
import React from 'react';
import { Task } from '../models';
import './TaskList.css';

interface TaskListProps {
  tasks: Task[];
  onTaskUpdate: (task: Task) => void;
  onTaskDelete: (task: Task) => void;
}

const TaskList: React.FC<TaskListProps> = ({ 
  tasks, 
  onTaskUpdate, 
  onTaskDelete 
}) => {
  const getPriorityColor = (priority: string) => {
    switch (priority) {
      case 'HIGH': return '#ff4444';
      case 'MEDIUM': return '#ffaa00';
      case 'LOW': return '#00aa00';
      default: return '#666666';
    }
  };

  return (
    <div className="task-list">
      <h2>Tasks ({tasks.length})</h2>
      {tasks.length === 0 ? (
        <p className="no-tasks">No tasks yet. Create your first task!</p>
      ) : (
        tasks.map((task) => (
          <div key={task.id} className={`task-item ${task.completed ? 'completed' : ''}`}>
            <div className="task-content">
              <div className="task-header">
                <h3 className="task-title">{task.title}</h3>
                <div 
                  className="task-priority"
                  style={{ backgroundColor: getPriorityColor(task.priority) }}
                >
                  {task.priority}
                </div>
              </div>
              {task.description && (
                <p className="task-description">{task.description}</p>
              )}
              {task.dueDate && (
                <p className="task-due-date">Due: {task.dueDate}</p>
              )}
            </div>
            <div className="task-actions">
              <button 
                onClick={() => onTaskUpdate(task)}
                className={`toggle-button ${task.completed ? 'completed' : ''}`}
              >
                {task.completed ? '✓' : '○'}
              </button>
              <button 
                onClick={() => onTaskDelete(task)}
                className="delete-button"
              >
                ×
              </button>
            </div>
          </div>
        ))
      )}
    </div>
  );
};

export default TaskList;
EOF
    
    # Create TaskForm component
    cat > src/components/TaskForm.tsx << 'EOF'
import React, { useState } from 'react';
import { Priority } from '../models';
import './TaskForm.css';

interface TaskFormProps {
  onTaskCreate: (task: any) => void;
}

const TaskForm: React.FC<TaskFormProps> = ({ onTaskCreate }) => {
  const [title, setTitle] = useState('');
  const [description, setDescription] = useState('');
  const [priority, setPriority] = useState<Priority>(Priority.MEDIUM);
  const [dueDate, setDueDate] = useState('');

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!title.trim()) return;

    onTaskCreate({
      title: title.trim(),
      description: description.trim(),
      priority,
      dueDate: dueDate || undefined,
      completed: false,
    });

    // Reset form
    setTitle('');
    setDescription('');
    setPriority(Priority.MEDIUM);
    setDueDate('');
  };

  return (
    <form onSubmit={handleSubmit} className="task-form">
      <h2>Create New Task</h2>
      <div className="form-group">
        <label htmlFor="title">Title *</label>
        <input
          type="text"
          id="title"
          value={title}
          onChange={(e) => setTitle(e.target.value)}
          placeholder="Enter task title"
          required
        />
      </div>
      
      <div className="form-group">
        <label htmlFor="description">Description</label>
        <textarea
          id="description"
          value={description}
          onChange={(e) => setDescription(e.target.value)}
          placeholder="Enter task description"
          rows={3}
        />
      </div>
      
      <div className="form-row">
        <div className="form-group">
          <label htmlFor="priority">Priority</label>
          <select
            id="priority"
            value={priority}
            onChange={(e) => setPriority(e.target.value as Priority)}
          >
            <option value={Priority.LOW}>Low</option>
            <option value={Priority.MEDIUM}>Medium</option>
            <option value={Priority.HIGH}>High</option>
          </select>
        </div>
        
        <div className="form-group">
          <label htmlFor="dueDate">Due Date</label>
          <input
            type="date"
            id="dueDate"
            value={dueDate}
            onChange={(e) => setDueDate(e.target.value)}
          />
        </div>
      </div>
      
      <button type="submit" className="submit-button">
        Create Task
      </button>
    </form>
  );
};

export default TaskForm;
EOF
    
    # Create NetworkStatus component
    cat > src/components/NetworkStatus.tsx << 'EOF'
import React from 'react';
import './NetworkStatus.css';

interface NetworkStatusProps {
  isOnline: boolean;
  syncStatus: string;
}

const NetworkStatus: React.FC<NetworkStatusProps> = ({ isOnline, syncStatus }) => {
  const getStatusMessage = () => {
    if (!isOnline) return 'Offline - Changes saved locally';
    if (syncStatus === 'syncing') return 'Syncing...';
    if (syncStatus === 'error') return 'Sync error - Will retry';
    return 'Online - All changes synced';
  };

  const getStatusClass = () => {
    if (!isOnline) return 'offline';
    if (syncStatus === 'syncing') return 'syncing';
    if (syncStatus === 'error') return 'error';
    return 'online';
  };

  return (
    <div className={`network-status ${getStatusClass()}`}>
      <div className="status-indicator"></div>
      <span>{getStatusMessage()}</span>
    </div>
  );
};

export default NetworkStatus;
EOF
    
    log_success "React components created"
}

# Function to create PWA configuration
create_pwa_configuration() {
    log_info "Creating PWA configuration..."
    
    cd ~/${PROJECT_NAME}
    
    # Create PWA manifest
    cat > public/manifest.json << 'EOF'
{
  "short_name": "Task Manager",
  "name": "Full-Stack PWA Task Manager",
  "icons": [
    {
      "src": "favicon.ico",
      "sizes": "64x64 32x32 24x24 16x16",
      "type": "image/x-icon"
    },
    {
      "src": "logo192.png",
      "type": "image/png",
      "sizes": "192x192"
    },
    {
      "src": "logo512.png",
      "type": "image/png",
      "sizes": "512x512"
    }
  ],
  "start_url": ".",
  "display": "standalone",
  "theme_color": "#000000",
  "background_color": "#ffffff",
  "categories": ["productivity", "utilities"]
}
EOF
    
    # Create service worker
    cat > public/sw.js << 'EOF'
const CACHE_NAME = 'task-manager-v1';
const urlsToCache = [
  '/',
  '/static/js/bundle.js',
  '/static/css/main.css',
  '/manifest.json'
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then((cache) => cache.addAll(urlsToCache))
  );
});

self.addEventListener('fetch', (event) => {
  event.respondWith(
    caches.match(event.request)
      .then((response) => {
        if (response) {
          return response;
        }
        return fetch(event.request);
      })
  );
});
EOF
    
    log_success "PWA configuration created"
}

# Function to create CSS styling
create_css_styling() {
    log_info "Creating CSS styling..."
    
    cd ~/${PROJECT_NAME}
    
    # Create TaskList CSS
    cat > src/components/TaskList.css << 'EOF'
.task-list {
  margin: 20px 0;
}

.task-list h2 {
  color: #333;
  margin-bottom: 20px;
}

.no-tasks {
  text-align: center;
  color: #666;
  font-style: italic;
  margin: 40px 0;
}

.task-item {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 15px;
  margin-bottom: 10px;
  background: #f8f9fa;
  border-radius: 8px;
  border-left: 4px solid #007bff;
  transition: all 0.2s ease;
}

.task-item:hover {
  background: #e9ecef;
  transform: translateX(5px);
}

.task-item.completed {
  opacity: 0.7;
  border-left-color: #28a745;
}

.task-content {
  flex: 1;
}

.task-header {
  display: flex;
  align-items: center;
  gap: 10px;
  margin-bottom: 8px;
}

.task-title {
  margin: 0;
  font-size: 16px;
  color: #333;
}

.task-priority {
  padding: 4px 8px;
  border-radius: 4px;
  color: white;
  font-size: 12px;
  font-weight: bold;
}

.task-description {
  margin: 5px 0;
  color: #666;
  font-size: 14px;
}

.task-due-date {
  margin: 5px 0;
  color: #666;
  font-size: 12px;
}

.task-actions {
  display: flex;
  gap: 10px;
}

.toggle-button, .delete-button {
  border: none;
  border-radius: 50%;
  width: 35px;
  height: 35px;
  cursor: pointer;
  font-size: 16px;
  transition: all 0.2s ease;
}

.toggle-button {
  background: #007bff;
  color: white;
}

.toggle-button.completed {
  background: #28a745;
}

.delete-button {
  background: #dc3545;
  color: white;
}

.toggle-button:hover, .delete-button:hover {
  transform: scale(1.1);
}
EOF
    
    # Create TaskForm CSS
    cat > src/components/TaskForm.css << 'EOF'
.task-form {
  background: #f8f9fa;
  padding: 20px;
  border-radius: 8px;
  margin-bottom: 30px;
}

.task-form h2 {
  margin-top: 0;
  color: #333;
}

.form-group {
  margin-bottom: 15px;
}

.form-row {
  display: flex;
  gap: 15px;
}

.form-row .form-group {
  flex: 1;
}

.form-group label {
  display: block;
  margin-bottom: 5px;
  color: #333;
  font-weight: 500;
}

.form-group input,
.form-group textarea,
.form-group select {
  width: 100%;
  padding: 8px 12px;
  border: 1px solid #ddd;
  border-radius: 4px;
  font-size: 14px;
  box-sizing: border-box;
}

.form-group textarea {
  resize: vertical;
}

.submit-button {
  background: #007bff;
  color: white;
  border: none;
  padding: 12px 24px;
  border-radius: 4px;
  cursor: pointer;
  font-size: 16px;
  transition: background 0.2s ease;
}

.submit-button:hover {
  background: #0056b3;
}
EOF
    
    # Create NetworkStatus CSS
    cat > src/components/NetworkStatus.css << 'EOF'
.network-status {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 10px 15px;
  border-radius: 4px;
  margin-bottom: 20px;
  font-size: 14px;
}

.status-indicator {
  width: 8px;
  height: 8px;
  border-radius: 50%;
}

.network-status.online .status-indicator {
  background: #28a745;
}

.network-status.offline .status-indicator {
  background: #dc3545;
}

.network-status.syncing .status-indicator {
  background: #ffc107;
  animation: pulse 1s infinite;
}

.network-status.error .status-indicator {
  background: #dc3545;
}

.network-status.online {
  background: #d4edda;
  color: #155724;
}

.network-status.offline {
  background: #f8d7da;
  color: #721c24;
}

.network-status.syncing {
  background: #fff3cd;
  color: #856404;
}

.network-status.error {
  background: #f8d7da;
  color: #721c24;
}

@keyframes pulse {
  0% { opacity: 1; }
  50% { opacity: 0.5; }
  100% { opacity: 1; }
}
EOF
    
    # Update main App.css
    cat > src/App.css << 'EOF'
.App {
  max-width: 800px;
  margin: 0 auto;
  padding: 20px;
}

.App-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 30px;
  padding-bottom: 20px;
  border-bottom: 2px solid #e9ecef;
}

.App-header h1 {
  margin: 0;
  color: #333;
}

.user-info {
  display: flex;
  align-items: center;
  gap: 15px;
}

.sign-out-button {
  background: #dc3545;
  color: white;
  border: none;
  padding: 8px 16px;
  border-radius: 4px;
  cursor: pointer;
  font-size: 14px;
  transition: background 0.2s ease;
}

.sign-out-button:hover {
  background: #c82333;
}

.App-main {
  padding: 20px 0;
}

@media (max-width: 768px) {
  .App {
    padding: 10px;
  }
  
  .App-header {
    flex-direction: column;
    gap: 15px;
    text-align: center;
  }
  
  .user-info {
    flex-direction: column;
    gap: 10px;
  }
}
EOF
    
    log_success "CSS styling created"
}

# Function to build and test the application
build_and_test() {
    log_info "Building and testing the application..."
    
    cd ~/${PROJECT_NAME}
    
    # Build the application
    npm run build
    
    if [ $? -ne 0 ]; then
        log_error "Failed to build application"
        exit 1
    fi
    
    log_success "Application built successfully"
    
    # Start the development server in background for testing
    log_info "Starting development server for testing..."
    npm start &
    SERVER_PID=$!
    
    # Wait for server to start
    sleep 10
    
    # Test if server is running
    if curl -s http://localhost:3000 > /dev/null; then
        log_success "Development server is running at http://localhost:3000"
    else
        log_warning "Development server might not be running correctly"
    fi
    
    # Kill the test server
    kill $SERVER_PID 2>/dev/null
    
    log_success "Build and test completed"
}

# Function to display deployment summary
display_summary() {
    log_info "Deployment Summary"
    echo "=========================================="
    echo "Project Name: ${PROJECT_NAME}"
    echo "App Name: ${APP_NAME}"
    echo "AWS Region: ${AWS_REGION}"
    echo "Project Directory: ~/${PROJECT_NAME}"
    echo "=========================================="
    echo ""
    echo "Next Steps:"
    echo "1. Navigate to project directory: cd ~/${PROJECT_NAME}"
    echo "2. Start development server: npm start"
    echo "3. Open http://localhost:3000 in your browser"
    echo "4. Sign up/sign in to test the application"
    echo "5. Test offline functionality by disabling network"
    echo ""
    echo "To deploy to production:"
    echo "1. Run: amplify add hosting"
    echo "2. Choose: Hosting with Amplify Console"
    echo "3. Run: amplify publish"
    echo ""
    echo "Environment file saved to: $(pwd)/.env"
    echo "Use this file for cleanup: ./destroy.sh"
    echo ""
    log_success "Deployment completed successfully!"
}

# Main execution
main() {
    log_info "Starting Progressive Web Applications with AWS Amplify deployment..."
    
    # Check if running from correct directory
    if [ ! -f "deploy.sh" ]; then
        log_error "This script must be run from the scripts directory"
        exit 1
    fi
    
    # Make script idempotent - check if already deployed
    if [ -f ".env" ]; then
        log_warning "Previous deployment detected. Loading existing environment..."
        source .env
        log_info "Using existing project: ${PROJECT_NAME}"
        
        # Check if project directory exists
        if [ ! -d "~/${PROJECT_NAME}" ]; then
            log_error "Project directory not found. Please run cleanup first: ./destroy.sh"
            exit 1
        fi
    else
        check_prerequisites
        initialize_environment
        create_react_project
        initialize_amplify_backend
        add_authentication
        add_graphql_api
        add_s3_storage
        deploy_backend_services
        create_application_components
        create_react_components
        create_pwa_configuration
        create_css_styling
        build_and_test
    fi
    
    display_summary
}

# Run main function
main "$@"