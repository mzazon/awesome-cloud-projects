#!/bin/bash

# Deploy script for Serverless Web Applications with Amplify and Lambda
# This script automates the deployment of a complete serverless web application
# using AWS Amplify, Lambda, API Gateway, Cognito, and DynamoDB

set -e

# Color codes for output
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

# Check if running in dry-run mode
DRY_RUN=${DRY_RUN:-false}

if [ "$DRY_RUN" = "true" ]; then
    warning "Running in DRY-RUN mode. No resources will be created."
fi

# Function to execute commands with dry-run support
execute() {
    if [ "$DRY_RUN" = "true" ]; then
        echo "[DRY-RUN] Would execute: $*"
    else
        "$@"
    fi
}

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Run 'aws configure' first."
        exit 1
    fi
    
    # Check Node.js
    if ! command -v node &> /dev/null; then
        error "Node.js is not installed. Please install Node.js v14 or later."
        exit 1
    fi
    
    # Check npm
    if ! command -v npm &> /dev/null; then
        error "npm is not installed. Please install npm."
        exit 1
    fi
    
    # Check Git
    if ! command -v git &> /dev/null; then
        error "Git is not installed. Please install Git."
        exit 1
    fi
    
    # Check Amplify CLI
    if ! command -v amplify &> /dev/null; then
        warning "Amplify CLI not found. Installing globally..."
        execute npm install -g @aws-amplify/cli
    fi
    
    success "All prerequisites satisfied"
}

# Environment setup
setup_environment() {
    log "Setting up environment variables..."
    
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        error "AWS region not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    export APP_NAME="serverless-web-app-${RANDOM_SUFFIX}"
    export STACK_NAME="amplify-${APP_NAME}"
    export LAMBDA_FUNCTION_NAME="api-${APP_NAME}"
    
    # Save environment variables to file for cleanup script
    cat > .env << EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
APP_NAME=${APP_NAME}
STACK_NAME=${STACK_NAME}
LAMBDA_FUNCTION_NAME=${LAMBDA_FUNCTION_NAME}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
EOF
    
    log "Environment configured:"
    log "  AWS Region: ${AWS_REGION}"
    log "  AWS Account: ${AWS_ACCOUNT_ID}"
    log "  App Name: ${APP_NAME}"
    
    success "Environment setup completed"
}

# Create project structure
create_project() {
    log "Creating project structure..."
    
    # Create project directory
    PROJECT_DIR="${HOME}/amplify-projects/${APP_NAME}"
    execute mkdir -p "${PROJECT_DIR}"
    cd "${PROJECT_DIR}"
    
    # Initialize React application
    log "Creating React application..."
    if [ "$DRY_RUN" != "true" ]; then
        npx create-react-app frontend --template typescript
        cd frontend
        
        # Install Amplify dependencies
        npm install aws-amplify @aws-amplify/ui-react
    else
        echo "[DRY-RUN] Would create React app and install dependencies"
    fi
    
    success "Project structure created"
}

# Initialize Amplify project
initialize_amplify() {
    log "Initializing Amplify project..."
    
    if [ "$DRY_RUN" != "true" ]; then
        cd "${HOME}/amplify-projects/${APP_NAME}/frontend"
        
        # Initialize Amplify project
        amplify init --yes \
            --name "${APP_NAME}" \
            --region "${AWS_REGION}" \
            --profile default
        
        # Add Amplify categories
        amplify add auth --defaults
        amplify add api --defaults
        amplify add storage --defaults
    else
        echo "[DRY-RUN] Would initialize Amplify project with auth, API, and storage"
    fi
    
    success "Amplify project initialized"
}

# Create Lambda function
create_lambda_function() {
    log "Creating Lambda function..."
    
    if [ "$DRY_RUN" != "true" ]; then
        cd "${HOME}/amplify-projects/${APP_NAME}/frontend"
        
        # Create Lambda function directory
        mkdir -p "amplify/backend/function/${LAMBDA_FUNCTION_NAME}/src"
        
        # Create Lambda function code
        cat > "amplify/backend/function/${LAMBDA_FUNCTION_NAME}/src/index.js" << 'EOF'
const AWS = require('aws-sdk');
const dynamodb = new AWS.DynamoDB.DocumentClient();

exports.handler = async (event) => {
    console.log('Event:', JSON.stringify(event, null, 2));
    
    const { httpMethod, path, body } = event;
    const tableName = process.env.STORAGE_TODOLIST_NAME;
    
    try {
        switch (httpMethod) {
            case 'GET':
                return await getTodos(tableName);
            case 'POST':
                return await createTodo(tableName, JSON.parse(body));
            case 'PUT':
                return await updateTodo(tableName, JSON.parse(body));
            case 'DELETE':
                return await deleteTodo(tableName, event.pathParameters.id);
            default:
                return {
                    statusCode: 405,
                    body: JSON.stringify({ error: 'Method not allowed' })
                };
        }
    } catch (error) {
        console.error('Error:', error);
        return {
            statusCode: 500,
            body: JSON.stringify({ error: 'Internal server error' })
        };
    }
};

async function getTodos(tableName) {
    const result = await dynamodb.scan({
        TableName: tableName
    }).promise();
    
    return {
        statusCode: 200,
        headers: {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        body: JSON.stringify(result.Items)
    };
}

async function createTodo(tableName, todo) {
    const item = {
        id: AWS.util.uuid.v4(),
        ...todo,
        createdAt: new Date().toISOString()
    };
    
    await dynamodb.put({
        TableName: tableName,
        Item: item
    }).promise();
    
    return {
        statusCode: 201,
        headers: {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        body: JSON.stringify(item)
    };
}

async function updateTodo(tableName, todo) {
    await dynamodb.update({
        TableName: tableName,
        Key: { id: todo.id },
        UpdateExpression: 'SET #title = :title, #completed = :completed',
        ExpressionAttributeNames: {
            '#title': 'title',
            '#completed': 'completed'
        },
        ExpressionAttributeValues: {
            ':title': todo.title,
            ':completed': todo.completed
        }
    }).promise();
    
    return {
        statusCode: 200,
        headers: {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        body: JSON.stringify(todo)
    };
}

async function deleteTodo(tableName, id) {
    await dynamodb.delete({
        TableName: tableName,
        Key: { id }
    }).promise();
    
    return {
        statusCode: 204,
        headers: {
            'Access-Control-Allow-Origin': '*'
        }
    };
}
EOF
    else
        echo "[DRY-RUN] Would create Lambda function code"
    fi
    
    success "Lambda function created"
}

# Create React components
create_react_components() {
    log "Creating React components..."
    
    if [ "$DRY_RUN" != "true" ]; then
        cd "${HOME}/amplify-projects/${APP_NAME}/frontend"
        
        # Create main App component
        cat > src/App.tsx << 'EOF'
import React, { useState, useEffect } from 'react';
import { Amplify } from 'aws-amplify';
import { withAuthenticator } from '@aws-amplify/ui-react';
import '@aws-amplify/ui-react/styles.css';
import awsExports from './aws-exports';
import TodoList from './components/TodoList';
import './App.css';

Amplify.configure(awsExports);

interface Todo {
    id: string;
    title: string;
    completed: boolean;
    createdAt: string;
}

function App({ signOut, user }: any) {
    const [todos, setTodos] = useState<Todo[]>([]);
    const [loading, setLoading] = useState(true);

    useEffect(() => {
        fetchTodos();
    }, []);

    const fetchTodos = async () => {
        try {
            const response = await fetch('/api/todos');
            const data = await response.json();
            setTodos(data);
        } catch (error) {
            console.error('Error fetching todos:', error);
        } finally {
            setLoading(false);
        }
    };

    const createTodo = async (title: string) => {
        try {
            const response = await fetch('/api/todos', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify({ title, completed: false }),
            });
            const newTodo = await response.json();
            setTodos([...todos, newTodo]);
        } catch (error) {
            console.error('Error creating todo:', error);
        }
    };

    const updateTodo = async (id: string, updates: Partial<Todo>) => {
        try {
            const todo = todos.find(t => t.id === id);
            if (!todo) return;

            const response = await fetch(`/api/todos/${id}`, {
                method: 'PUT',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify({ ...todo, ...updates }),
            });
            const updatedTodo = await response.json();
            setTodos(todos.map(t => t.id === id ? updatedTodo : t));
        } catch (error) {
            console.error('Error updating todo:', error);
        }
    };

    const deleteTodo = async (id: string) => {
        try {
            await fetch(`/api/todos/${id}`, {
                method: 'DELETE',
            });
            setTodos(todos.filter(t => t.id !== id));
        } catch (error) {
            console.error('Error deleting todo:', error);
        }
    };

    if (loading) {
        return <div className="loading">Loading...</div>;
    }

    return (
        <div className="App">
            <header className="App-header">
                <h1>Serverless Todo App</h1>
                <p>Welcome, {user.username}!</p>
                <button onClick={signOut}>Sign Out</button>
            </header>
            <main>
                <TodoList
                    todos={todos}
                    onCreateTodo={createTodo}
                    onUpdateTodo={updateTodo}
                    onDeleteTodo={deleteTodo}
                />
            </main>
        </div>
    );
}

export default withAuthenticator(App);
EOF

        # Create components directory and TodoList component
        mkdir -p src/components
        cat > src/components/TodoList.tsx << 'EOF'
import React, { useState } from 'react';

interface Todo {
    id: string;
    title: string;
    completed: boolean;
    createdAt: string;
}

interface TodoListProps {
    todos: Todo[];
    onCreateTodo: (title: string) => void;
    onUpdateTodo: (id: string, updates: Partial<Todo>) => void;
    onDeleteTodo: (id: string) => void;
}

const TodoList: React.FC<TodoListProps> = ({
    todos,
    onCreateTodo,
    onUpdateTodo,
    onDeleteTodo,
}) => {
    const [newTodoTitle, setNewTodoTitle] = useState('');

    const handleSubmit = (e: React.FormEvent) => {
        e.preventDefault();
        if (newTodoTitle.trim()) {
            onCreateTodo(newTodoTitle.trim());
            setNewTodoTitle('');
        }
    };

    return (
        <div className="todo-list">
            <form onSubmit={handleSubmit} className="todo-form">
                <input
                    type="text"
                    value={newTodoTitle}
                    onChange={(e) => setNewTodoTitle(e.target.value)}
                    placeholder="Add a new todo..."
                    className="todo-input"
                />
                <button type="submit" className="todo-submit">
                    Add Todo
                </button>
            </form>

            <div className="todos">
                {todos.map((todo) => (
                    <div key={todo.id} className="todo-item">
                        <input
                            type="checkbox"
                            checked={todo.completed}
                            onChange={(e) =>
                                onUpdateTodo(todo.id, {
                                    completed: e.target.checked,
                                })
                            }
                        />
                        <span
                            className={`todo-title ${
                                todo.completed ? 'completed' : ''
                            }`}
                        >
                            {todo.title}
                        </span>
                        <button
                            onClick={() => onDeleteTodo(todo.id)}
                            className="todo-delete"
                        >
                            Delete
                        </button>
                    </div>
                ))}
            </div>

            {todos.length === 0 && (
                <div className="no-todos">
                    No todos yet. Add one above!
                </div>
            )}
        </div>
    );
};

export default TodoList;
EOF

        # Create CSS styles
        cat > src/App.css << 'EOF'
.App {
    text-align: center;
    min-height: 100vh;
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
}

.App-header {
    background-color: rgba(255, 255, 255, 0.1);
    padding: 2rem;
    color: white;
    box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
}

.App-header h1 {
    margin: 0 0 1rem 0;
    font-size: 2.5rem;
    font-weight: 300;
}

.App-header p {
    margin: 0 0 1rem 0;
    font-size: 1.2rem;
}

.App-header button {
    background-color: #ff4757;
    color: white;
    border: none;
    padding: 0.5rem 1rem;
    border-radius: 4px;
    cursor: pointer;
    font-size: 1rem;
    transition: background-color 0.3s;
}

.App-header button:hover {
    background-color: #ff3838;
}

main {
    max-width: 600px;
    margin: 2rem auto;
    padding: 0 1rem;
}

.loading {
    display: flex;
    justify-content: center;
    align-items: center;
    height: 100vh;
    font-size: 1.5rem;
    color: white;
}

.todo-list {
    background: white;
    border-radius: 8px;
    box-shadow: 0 10px 30px rgba(0, 0, 0, 0.2);
    overflow: hidden;
}

.todo-form {
    display: flex;
    padding: 1rem;
    background-color: #f8f9fa;
    border-bottom: 1px solid #e9ecef;
}

.todo-input {
    flex: 1;
    padding: 0.75rem;
    border: 1px solid #dee2e6;
    border-radius: 4px 0 0 4px;
    font-size: 1rem;
    outline: none;
}

.todo-input:focus {
    border-color: #667eea;
    box-shadow: 0 0 0 2px rgba(102, 126, 234, 0.2);
}

.todo-submit {
    padding: 0.75rem 1.5rem;
    background-color: #667eea;
    color: white;
    border: none;
    border-radius: 0 4px 4px 0;
    cursor: pointer;
    font-size: 1rem;
    transition: background-color 0.3s;
}

.todo-submit:hover {
    background-color: #5a67d8;
}

.todos {
    min-height: 200px;
}

.todo-item {
    display: flex;
    align-items: center;
    padding: 1rem;
    border-bottom: 1px solid #e9ecef;
    transition: background-color 0.3s;
}

.todo-item:hover {
    background-color: #f8f9fa;
}

.todo-item:last-child {
    border-bottom: none;
}

.todo-item input[type="checkbox"] {
    margin-right: 1rem;
    transform: scale(1.2);
}

.todo-title {
    flex: 1;
    text-align: left;
    font-size: 1.1rem;
    transition: all 0.3s;
}

.todo-title.completed {
    text-decoration: line-through;
    color: #6c757d;
}

.todo-delete {
    background-color: #ff4757;
    color: white;
    border: none;
    padding: 0.5rem 1rem;
    border-radius: 4px;
    cursor: pointer;
    font-size: 0.9rem;
    transition: background-color 0.3s;
}

.todo-delete:hover {
    background-color: #ff3838;
}

.no-todos {
    padding: 3rem;
    color: #6c757d;
    font-size: 1.1rem;
}
EOF
    else
        echo "[DRY-RUN] Would create React components and styles"
    fi
    
    success "React components created"
}

# Deploy backend resources
deploy_backend() {
    log "Deploying backend resources..."
    
    if [ "$DRY_RUN" != "true" ]; then
        cd "${HOME}/amplify-projects/${APP_NAME}/frontend"
        
        # Deploy Amplify backend
        amplify push --yes
        
        # Wait for deployment to complete
        log "Waiting for backend deployment to complete..."
        sleep 30
        
        # Verify backend deployment
        amplify status
    else
        echo "[DRY-RUN] Would deploy Amplify backend with auth, API, and storage"
    fi
    
    success "Backend resources deployed"
}

# Configure hosting and deploy frontend
deploy_frontend() {
    log "Configuring hosting and deploying frontend..."
    
    if [ "$DRY_RUN" != "true" ]; then
        cd "${HOME}/amplify-projects/${APP_NAME}/frontend"
        
        # Add Amplify hosting
        amplify add hosting
        
        # Build the React application
        npm run build
        
        # Deploy to Amplify hosting
        amplify publish --yes
    else
        echo "[DRY-RUN] Would add hosting and deploy frontend to Amplify"
    fi
    
    success "Frontend deployed to Amplify hosting"
}

# Configure monitoring
setup_monitoring() {
    log "Setting up monitoring and logging..."
    
    if [ "$DRY_RUN" != "true" ]; then
        # Create CloudWatch Log Group for Lambda
        aws logs create-log-group \
            --log-group-name "/aws/lambda/${LAMBDA_FUNCTION_NAME}" \
            --region "${AWS_REGION}" 2>/dev/null || true
        
        # Create CloudWatch Dashboard
        aws cloudwatch put-dashboard \
            --dashboard-name "${APP_NAME}-dashboard" \
            --dashboard-body "{
                \"widgets\": [
                    {
                        \"type\": \"metric\",
                        \"properties\": {
                            \"metrics\": [
                                [\"AWS/Lambda\", \"Duration\", \"FunctionName\", \"${LAMBDA_FUNCTION_NAME}\"],
                                [\"AWS/Lambda\", \"Errors\", \"FunctionName\", \"${LAMBDA_FUNCTION_NAME}\"],
                                [\"AWS/Lambda\", \"Invocations\", \"FunctionName\", \"${LAMBDA_FUNCTION_NAME}\"]
                            ],
                            \"period\": 300,
                            \"stat\": \"Average\",
                            \"region\": \"${AWS_REGION}\",
                            \"title\": \"Lambda Metrics\"
                        }
                    }
                ]
            }" --region "${AWS_REGION}" 2>/dev/null || true
    else
        echo "[DRY-RUN] Would create CloudWatch log group and dashboard"
    fi
    
    success "Monitoring and logging configured"
}

# Get deployment information
get_deployment_info() {
    log "Getting deployment information..."
    
    if [ "$DRY_RUN" != "true" ]; then
        cd "${HOME}/amplify-projects/${APP_NAME}/frontend"
        
        # Get Amplify app URL
        APP_URL=$(amplify status | grep "Hosting endpoint" | awk '{print $3}' 2>/dev/null || echo "Not available yet")
        
        # Get API Gateway endpoint
        API_ENDPOINT=$(aws apigateway get-rest-apis \
            --query "items[?name=='${APP_NAME}-api'].id" \
            --output text 2>/dev/null || echo "Not available yet")
        
        echo ""
        success "Deployment completed successfully!"
        echo ""
        echo "=== Deployment Information ==="
        echo "App Name: ${APP_NAME}"
        echo "AWS Region: ${AWS_REGION}"
        echo "App URL: ${APP_URL}"
        echo "API Endpoint: https://${API_ENDPOINT}.execute-api.${AWS_REGION}.amazonaws.com/dev"
        echo "CloudWatch Dashboard: https://${AWS_REGION}.console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=${APP_NAME}-dashboard"
        echo ""
        echo "=== Next Steps ==="
        echo "1. Access your app at: ${APP_URL}"
        echo "2. Sign up for a new account or sign in"
        echo "3. Create, update, and delete todos"
        echo "4. Monitor performance in CloudWatch"
        echo ""
        echo "=== Cleanup ==="
        echo "To remove all resources, run: ./destroy.sh"
        echo ""
    else
        echo "[DRY-RUN] Would display deployment information"
    fi
}

# Cleanup function for errors
cleanup_on_error() {
    error "Deployment failed. Running cleanup..."
    if [ -f .env ]; then
        source .env
        # Basic cleanup - full cleanup available in destroy.sh
        if [ "$DRY_RUN" != "true" ]; then
            cd "${HOME}/amplify-projects/${APP_NAME}/frontend" 2>/dev/null && amplify delete --yes 2>/dev/null || true
        fi
    fi
}

# Trap errors
trap cleanup_on_error ERR

# Main deployment function
main() {
    log "Starting deployment of Serverless Web Application with Amplify and Lambda"
    log "========================================================================="
    
    check_prerequisites
    setup_environment
    create_project
    initialize_amplify
    create_lambda_function
    create_react_components
    deploy_backend
    deploy_frontend
    setup_monitoring
    get_deployment_info
    
    success "All deployment steps completed successfully!"
}

# Run main function
main "$@"