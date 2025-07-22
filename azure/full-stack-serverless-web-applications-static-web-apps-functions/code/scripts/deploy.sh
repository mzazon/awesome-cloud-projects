#!/bin/bash

# Deploy script for Full-Stack Serverless Web Applications with Azure Static Web Apps and Azure Functions
# This script deploys the complete serverless application infrastructure

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to validate prerequisites
validate_prerequisites() {
    log "Validating prerequisites..."
    
    # Check Azure CLI
    if ! command_exists az; then
        error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check Node.js
    if ! command_exists node; then
        error "Node.js is not installed. Please install Node.js 18.x or later."
        exit 1
    fi
    
    # Check npm
    if ! command_exists npm; then
        error "npm is not installed. Please install npm."
        exit 1
    fi
    
    # Check if logged into Azure
    if ! az account show > /dev/null 2>&1; then
        error "Not logged into Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check Node.js version
    NODE_VERSION=$(node --version | cut -d'v' -f2 | cut -d'.' -f1)
    if [ "$NODE_VERSION" -lt 18 ]; then
        error "Node.js version 18 or higher is required. Current version: $(node --version)"
        exit 1
    fi
    
    success "Prerequisites validation completed"
}

# Function to set environment variables
set_environment_variables() {
    log "Setting environment variables..."
    
    # Set default values if not provided
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-fullstack-serverless-$(date +%s)}"
    export LOCATION="${LOCATION:-eastus}"
    export STORAGE_ACCOUNT_NAME="${STORAGE_ACCOUNT_NAME:-stfullstack$(openssl rand -hex 6)}"
    export STATIC_WEB_APP_NAME="${STATIC_WEB_APP_NAME:-swa-fullstack-app-$(date +%s)}"
    export SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-$(az account show --query id --output tsv)}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    log "Environment variables set:"
    log "  Resource Group: $RESOURCE_GROUP"
    log "  Location: $LOCATION"
    log "  Storage Account: $STORAGE_ACCOUNT_NAME"
    log "  Static Web App: $STATIC_WEB_APP_NAME"
    log "  Subscription ID: $SUBSCRIPTION_ID"
    
    success "Environment variables configured"
}

# Function to create resource group
create_resource_group() {
    log "Creating resource group..."
    
    # Check if resource group already exists
    if az group show --name "$RESOURCE_GROUP" > /dev/null 2>&1; then
        warning "Resource group '$RESOURCE_GROUP' already exists. Skipping creation."
        return 0
    fi
    
    az group create \
        --name "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --tags purpose=recipe environment=demo created_by=azure_recipe_deploy
    
    success "Resource group created: $RESOURCE_GROUP"
}

# Function to create storage account
create_storage_account() {
    log "Creating storage account..."
    
    # Check if storage account already exists
    if az storage account show --name "$STORAGE_ACCOUNT_NAME" --resource-group "$RESOURCE_GROUP" > /dev/null 2>&1; then
        warning "Storage account '$STORAGE_ACCOUNT_NAME' already exists. Skipping creation."
    else
        az storage account create \
            --name "$STORAGE_ACCOUNT_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --sku Standard_LRS \
            --kind StorageV2 \
            --tags purpose=recipe environment=demo created_by=azure_recipe_deploy
        
        success "Storage account created: $STORAGE_ACCOUNT_NAME"
    fi
    
    # Get storage account connection string
    export STORAGE_CONNECTION_STRING=$(az storage account show-connection-string \
        --name "$STORAGE_ACCOUNT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query connectionString --output tsv)
    
    success "Storage connection string retrieved"
}

# Function to create React application
create_react_app() {
    log "Creating React application..."
    
    # Check if application directory already exists
    if [ -d "fullstack-serverless-app" ]; then
        warning "React application directory already exists. Skipping creation."
        cd fullstack-serverless-app
        return 0
    fi
    
    # Create React application
    npx create-react-app fullstack-serverless-app --template typescript
    cd fullstack-serverless-app
    
    # Install additional dependencies
    npm install axios
    
    success "React application created and dependencies installed"
}

# Function to setup frontend components
setup_frontend_components() {
    log "Setting up frontend components..."
    
    # Create directory structure
    mkdir -p src/components src/services
    
    # Create API service
    cat > src/services/api.ts << 'EOF'
import axios from 'axios';

const API_BASE_URL = '/api';

export interface Task {
  id: string;
  title: string;
  description: string;
  completed: boolean;
  createdAt: string;
}

export const taskService = {
  async getTasks(): Promise<Task[]> {
    const response = await axios.get(`${API_BASE_URL}/tasks`);
    return response.data;
  },

  async createTask(task: Omit<Task, 'id' | 'createdAt'>): Promise<Task> {
    const response = await axios.post(`${API_BASE_URL}/tasks`, task);
    return response.data;
  },

  async updateTask(id: string, task: Partial<Task>): Promise<Task> {
    const response = await axios.put(`${API_BASE_URL}/tasks/${id}`, task);
    return response.data;
  },

  async deleteTask(id: string): Promise<void> {
    await axios.delete(`${API_BASE_URL}/tasks/${id}`);
  }
};
EOF
    
    # Create TaskManager component
    cat > src/components/TaskManager.tsx << 'EOF'
import React, { useState, useEffect } from 'react';
import { taskService, Task } from '../services/api';

const TaskManager: React.FC = () => {
  const [tasks, setTasks] = useState<Task[]>([]);
  const [newTask, setNewTask] = useState({ title: '', description: '', completed: false });
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    loadTasks();
  }, []);

  const loadTasks = async () => {
    try {
      setLoading(true);
      setError(null);
      const data = await taskService.getTasks();
      setTasks(data);
    } catch (error) {
      console.error('Error loading tasks:', error);
      setError('Failed to load tasks');
    } finally {
      setLoading(false);
    }
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!newTask.title.trim()) return;
    
    try {
      setError(null);
      await taskService.createTask(newTask);
      setNewTask({ title: '', description: '', completed: false });
      await loadTasks();
    } catch (error) {
      console.error('Error creating task:', error);
      setError('Failed to create task');
    }
  };

  const handleToggle = async (id: string) => {
    try {
      setError(null);
      const task = tasks.find(t => t.id === id);
      if (task) {
        await taskService.updateTask(id, { ...task, completed: !task.completed });
        await loadTasks();
      }
    } catch (error) {
      console.error('Error updating task:', error);
      setError('Failed to update task');
    }
  };

  const handleDelete = async (id: string) => {
    try {
      setError(null);
      await taskService.deleteTask(id);
      await loadTasks();
    } catch (error) {
      console.error('Error deleting task:', error);
      setError('Failed to delete task');
    }
  };

  return (
    <div className="task-manager">
      <h1>Serverless Task Manager</h1>
      
      {error && (
        <div className="error-message">
          {error}
        </div>
      )}
      
      <form onSubmit={handleSubmit} className="task-form">
        <input
          type="text"
          placeholder="Task title"
          value={newTask.title}
          onChange={(e) => setNewTask({ ...newTask, title: e.target.value })}
          required
        />
        <textarea
          placeholder="Task description"
          value={newTask.description}
          onChange={(e) => setNewTask({ ...newTask, description: e.target.value })}
        />
        <button type="submit" disabled={loading}>
          {loading ? 'Adding...' : 'Add Task'}
        </button>
      </form>

      {loading && <p>Loading tasks...</p>}
      
      <div className="task-list">
        {tasks.map(task => (
          <div key={task.id} className={`task-item ${task.completed ? 'completed' : ''}`}>
            <h3>{task.title}</h3>
            <p>{task.description}</p>
            <div className="task-actions">
              <button onClick={() => handleToggle(task.id)}>
                {task.completed ? 'Mark Incomplete' : 'Mark Complete'}
              </button>
              <button onClick={() => handleDelete(task.id)} className="delete-btn">
                Delete
              </button>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
};

export default TaskManager;
EOF
    
    # Update App.tsx
    cat > src/App.tsx << 'EOF'
import React from 'react';
import TaskManager from './components/TaskManager';
import './App.css';

function App() {
  return (
    <div className="App">
      <TaskManager />
    </div>
  );
}

export default App;
EOF
    
    # Update CSS
    cat > src/App.css << 'EOF'
.App {
  text-align: center;
  padding: 20px;
  max-width: 1200px;
  margin: 0 auto;
}

.task-manager {
  max-width: 800px;
  margin: 0 auto;
}

.task-form {
  margin-bottom: 30px;
  padding: 20px;
  border: 1px solid #ddd;
  border-radius: 8px;
  background-color: #f9f9f9;
}

.task-form input,
.task-form textarea,
.task-form button {
  margin: 5px;
  padding: 12px;
  border: 1px solid #ddd;
  border-radius: 4px;
  font-size: 14px;
}

.task-form input {
  width: 100%;
  max-width: 400px;
}

.task-form textarea {
  width: 100%;
  max-width: 400px;
  min-height: 80px;
  resize: vertical;
}

.task-form button {
  background-color: #0078d4;
  color: white;
  cursor: pointer;
  font-weight: bold;
  transition: background-color 0.2s;
}

.task-form button:hover {
  background-color: #106ebe;
}

.task-form button:disabled {
  background-color: #ccc;
  cursor: not-allowed;
}

.error-message {
  color: #d13438;
  background-color: #fdf0f0;
  border: 1px solid #d13438;
  padding: 10px;
  border-radius: 4px;
  margin-bottom: 20px;
}

.task-list {
  display: flex;
  flex-direction: column;
  gap: 15px;
}

.task-item {
  padding: 20px;
  border: 1px solid #ddd;
  border-radius: 8px;
  text-align: left;
  background-color: #fff;
  box-shadow: 0 2px 4px rgba(0,0,0,0.1);
  transition: box-shadow 0.2s;
}

.task-item:hover {
  box-shadow: 0 4px 8px rgba(0,0,0,0.15);
}

.task-item.completed {
  background-color: #f0f8f0;
  opacity: 0.8;
}

.task-item.completed h3 {
  text-decoration: line-through;
  color: #666;
}

.task-item h3 {
  margin: 0 0 10px 0;
  color: #333;
}

.task-item p {
  margin: 0 0 15px 0;
  color: #666;
  line-height: 1.4;
}

.task-actions {
  display: flex;
  gap: 10px;
}

.task-actions button {
  padding: 8px 16px;
  border: none;
  border-radius: 4px;
  cursor: pointer;
  font-size: 14px;
  transition: background-color 0.2s;
}

.task-actions button:first-child {
  background-color: #107c10;
  color: white;
}

.task-actions button:first-child:hover {
  background-color: #0e6e0e;
}

.task-actions .delete-btn {
  background-color: #d13438;
  color: white;
}

.task-actions .delete-btn:hover {
  background-color: #a4262c;
}

@media (max-width: 768px) {
  .App {
    padding: 10px;
  }
  
  .task-form input,
  .task-form textarea {
    max-width: 100%;
  }
  
  .task-actions {
    flex-direction: column;
  }
}
EOF
    
    success "Frontend components created successfully"
}

# Function to setup Azure Functions
setup_azure_functions() {
    log "Setting up Azure Functions..."
    
    # Create api directory
    mkdir -p api
    cd api
    
    # Check if Azure Functions Core Tools is installed
    if ! command_exists func; then
        warning "Azure Functions Core Tools not found. Installing via npm..."
        npm install -g azure-functions-core-tools@4 --unsafe-perm true
    fi
    
    # Initialize Functions project
    func init --worker-runtime node --language javascript
    
    # Create HTTP trigger function
    func new --name tasks --template "HTTP trigger" --authlevel anonymous
    
    # Install Azure Storage SDK
    npm install @azure/data-tables
    
    # Create tasks function implementation
    cat > tasks/index.js << 'EOF'
const { TableClient } = require('@azure/data-tables');

// Initialize table client
const tableClient = TableClient.fromConnectionString(
  process.env.STORAGE_CONNECTION_STRING,
  'tasks'
);

async function ensureTableExists() {
  try {
    await tableClient.createTable();
  } catch (error) {
    // Table might already exist
    if (error.statusCode !== 409) {
      throw error;
    }
  }
}

module.exports = async function (context, req) {
  context.log('Tasks API function processed a request.');
  
  // Set CORS headers
  context.res = {
    headers: {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization'
    }
  };
  
  // Handle preflight requests
  if (req.method === 'OPTIONS') {
    context.res.status = 200;
    return;
  }
  
  // Ensure table exists
  await ensureTableExists();
  
  const method = req.method;
  const taskId = req.params.id;
  
  try {
    switch (method) {
      case 'GET':
        if (taskId) {
          // Get specific task
          const task = await tableClient.getEntity('tasks', taskId);
          context.res.status = 200;
          context.res.body = {
            id: task.rowKey,
            title: task.title,
            description: task.description,
            completed: task.completed,
            createdAt: task.createdAt
          };
        } else {
          // Get all tasks
          const tasks = [];
          const entities = tableClient.listEntities();
          for await (const entity of entities) {
            tasks.push({
              id: entity.rowKey,
              title: entity.title,
              description: entity.description,
              completed: entity.completed,
              createdAt: entity.createdAt
            });
          }
          context.res.status = 200;
          context.res.body = tasks;
        }
        break;

      case 'POST':
        // Create new task
        const newTask = req.body;
        if (!newTask.title) {
          context.res.status = 400;
          context.res.body = { error: 'Title is required' };
          return;
        }
        
        const taskEntity = {
          partitionKey: 'tasks',
          rowKey: Date.now().toString(),
          title: newTask.title,
          description: newTask.description || '',
          completed: newTask.completed || false,
          createdAt: new Date().toISOString()
        };
        
        await tableClient.createEntity(taskEntity);
        
        context.res.status = 201;
        context.res.body = {
          id: taskEntity.rowKey,
          title: taskEntity.title,
          description: taskEntity.description,
          completed: taskEntity.completed,
          createdAt: taskEntity.createdAt
        };
        break;

      case 'PUT':
        // Update existing task
        if (!taskId) {
          context.res.status = 400;
          context.res.body = { error: 'Task ID is required' };
          return;
        }
        
        const updateTask = req.body;
        const existingTask = await tableClient.getEntity('tasks', taskId);
        
        const updatedEntity = {
          ...existingTask,
          title: updateTask.title || existingTask.title,
          description: updateTask.description !== undefined ? updateTask.description : existingTask.description,
          completed: updateTask.completed !== undefined ? updateTask.completed : existingTask.completed,
          updatedAt: new Date().toISOString()
        };
        
        await tableClient.updateEntity(updatedEntity);
        
        context.res.status = 200;
        context.res.body = {
          id: updatedEntity.rowKey,
          title: updatedEntity.title,
          description: updatedEntity.description,
          completed: updatedEntity.completed,
          createdAt: updatedEntity.createdAt
        };
        break;

      case 'DELETE':
        // Delete task
        if (!taskId) {
          context.res.status = 400;
          context.res.body = { error: 'Task ID is required' };
          return;
        }
        
        await tableClient.deleteEntity('tasks', taskId);
        context.res.status = 204;
        break;

      default:
        context.res.status = 405;
        context.res.body = { error: 'Method not allowed' };
    }
  } catch (error) {
    context.log.error('Error in tasks API:', error);
    if (error.statusCode === 404) {
      context.res.status = 404;
      context.res.body = { error: 'Task not found' };
    } else {
      context.res.status = 500;
      context.res.body = { error: 'Internal server error' };
    }
  }
};
EOF
    
    # Update function.json
    cat > tasks/function.json << 'EOF'
{
  "bindings": [
    {
      "authLevel": "anonymous",
      "type": "httpTrigger",
      "direction": "in",
      "name": "req",
      "methods": ["get", "post", "put", "delete", "options"],
      "route": "tasks/{id?}"
    },
    {
      "type": "http",
      "direction": "out",
      "name": "res"
    }
  ]
}
EOF
    
    cd ..
    success "Azure Functions setup completed"
}

# Function to configure Static Web Apps
configure_static_web_apps() {
    log "Configuring Static Web Apps..."
    
    # Create Static Web Apps configuration
    cat > staticwebapp.config.json << 'EOF'
{
  "routes": [
    {
      "route": "/api/*",
      "allowedRoles": ["anonymous"]
    },
    {
      "route": "/*",
      "serve": "/index.html",
      "statusCode": 200
    }
  ],
  "navigationFallback": {
    "rewrite": "/index.html",
    "exclude": ["/api/*"]
  },
  "mimeTypes": {
    ".json": "application/json",
    ".js": "application/javascript",
    ".css": "text/css"
  },
  "globalHeaders": {
    "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "DENY",
    "X-XSS-Protection": "1; mode=block"
  }
}
EOF
    
    success "Static Web Apps configuration created"
}

# Function to create and deploy Static Web App
deploy_static_web_app() {
    log "Creating and deploying Static Web App..."
    
    # Check if Static Web App already exists
    if az staticwebapp show --name "$STATIC_WEB_APP_NAME" --resource-group "$RESOURCE_GROUP" > /dev/null 2>&1; then
        warning "Static Web App '$STATIC_WEB_APP_NAME' already exists. Skipping creation."
    else
        # Create Static Web App
        az staticwebapp create \
            --name "$STATIC_WEB_APP_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --source "." \
            --branch "main" \
            --app-location "/" \
            --api-location "api" \
            --output-location "build" \
            --sku Free
        
        success "Static Web App created: $STATIC_WEB_APP_NAME"
    fi
    
    # Configure application settings
    az staticwebapp appsettings set \
        --name "$STATIC_WEB_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --setting-names "STORAGE_CONNECTION_STRING=$STORAGE_CONNECTION_STRING" \
                       "NODE_VERSION=18" \
                       "FUNCTIONS_WORKER_RUNTIME=node"
    
    # Get Static Web App URL
    export STATIC_WEB_APP_URL=$(az staticwebapp show \
        --name "$STATIC_WEB_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query "defaultHostname" --output tsv)
    
    # Build and deploy application
    log "Building React application..."
    npm run build
    
    log "Deploying to Static Web App..."
    az staticwebapp deploy \
        --name "$STATIC_WEB_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --source . \
        --app-location "/" \
        --api-location "api" \
        --output-location "build"
    
    success "Application deployed successfully"
    success "Application URL: https://$STATIC_WEB_APP_URL"
}

# Function to validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    # Wait for deployment to complete
    sleep 30
    
    # Test web app accessibility
    if curl -f -s "https://$STATIC_WEB_APP_URL" > /dev/null; then
        success "Web application is accessible"
    else
        warning "Web application may not be fully deployed yet"
    fi
    
    # Test API endpoint
    if curl -f -s "https://$STATIC_WEB_APP_URL/api/tasks" > /dev/null; then
        success "API endpoint is accessible"
    else
        warning "API endpoint may not be fully deployed yet"
    fi
    
    # Verify storage table
    if az storage table exists --name tasks --connection-string "$STORAGE_CONNECTION_STRING" --query exists --output tsv | grep -q "true"; then
        success "Storage table exists"
    else
        warning "Storage table may not be created yet"
    fi
    
    success "Deployment validation completed"
}

# Main deployment function
main() {
    echo "============================================="
    echo "Azure Static Web Apps Deployment Script"
    echo "============================================="
    echo
    
    validate_prerequisites
    set_environment_variables
    create_resource_group
    create_storage_account
    create_react_app
    setup_frontend_components
    setup_azure_functions
    configure_static_web_apps
    deploy_static_web_app
    validate_deployment
    
    echo
    echo "============================================="
    echo "Deployment completed successfully!"
    echo "============================================="
    echo
    echo "📋 Deployment Summary:"
    echo "  Resource Group: $RESOURCE_GROUP"
    echo "  Storage Account: $STORAGE_ACCOUNT_NAME"
    echo "  Static Web App: $STATIC_WEB_APP_NAME"
    echo "  Application URL: https://$STATIC_WEB_APP_URL"
    echo
    echo "🚀 Next Steps:"
    echo "  1. Open https://$STATIC_WEB_APP_URL in your browser"
    echo "  2. Test the task management functionality"
    echo "  3. Monitor the application in Azure Portal"
    echo
    echo "📖 Cleanup:"
    echo "  Run './destroy.sh' to remove all resources"
    echo
}

# Run main function
main "$@"