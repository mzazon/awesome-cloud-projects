#!/bin/bash

# Real-Time Collaborative Applications with Firebase - Deployment Script
# This script deploys Firebase Realtime Database, Cloud Functions, Authentication, and Hosting
# for a collaborative document editing application

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
    exit 1
}

# Function to check if command exists
check_command() {
    if ! command -v "$1" &> /dev/null; then
        error "$1 is required but not installed. Please install it first."
    fi
}

# Function to check Firebase CLI authentication
check_firebase_auth() {
    log "Checking Firebase CLI authentication..."
    if ! firebase login:list &> /dev/null; then
        warning "Firebase CLI not authenticated. Please run 'firebase login' first."
        firebase login
    fi
    success "Firebase CLI authenticated"
}

# Function to validate project name
validate_project_name() {
    local project_name="$1"
    if [[ ! "$project_name" =~ ^[a-z][a-z0-9-]{5,29}$ ]]; then
        error "Invalid project name. Must be 6-30 characters, start with lowercase letter, contain only lowercase letters, numbers, and hyphens."
    fi
}

# Function to check if project exists
project_exists() {
    local project_id="$1"
    firebase projects:list --json 2>/dev/null | jq -r '.[].projectId' | grep -q "^${project_id}$"
}

# Function to create Firebase project
create_firebase_project() {
    local project_id="$1"
    local display_name="$2"
    
    log "Creating Firebase project: ${project_id}"
    
    if project_exists "$project_id"; then
        warning "Project ${project_id} already exists. Using existing project."
    else
        firebase projects:create "$project_id" --display-name "$display_name"
        success "Firebase project created: ${project_id}"
    fi
}

# Function to initialize Firebase project
init_firebase_project() {
    local project_id="$1"
    
    log "Setting Firebase project: ${project_id}"
    firebase use "$project_id"
    
    log "Initializing Firebase features..."
    
    # Create firebase.json configuration
    cat > firebase.json << 'EOF'
{
  "hosting": {
    "public": "public",
    "ignore": [
      "firebase.json",
      "**/.*",
      "**/node_modules/**"
    ],
    "rewrites": [
      {
        "source": "**",
        "destination": "/index.html"
      }
    ],
    "headers": [
      {
        "source": "**/*.@(js|css)",
        "headers": [
          {
            "key": "Cache-Control",
            "value": "max-age=31536000"
          }
        ]
      }
    ]
  },
  "database": {
    "rules": "database.rules.json"
  },
  "functions": {
    "source": "functions",
    "predeploy": [
      "npm --prefix \"$RESOURCE_DIR\" run build"
    ]
  }
}
EOF
    
    success "Firebase configuration created"
}

# Function to create database security rules
create_database_rules() {
    log "Creating database security rules..."
    
    cat > database.rules.json << 'EOF'
{
  "rules": {
    "documents": {
      "$documentId": {
        ".read": "auth != null && (auth.uid in data.collaborators || data.owner == auth.uid)",
        ".write": "auth != null && (auth.uid in data.collaborators || data.owner == auth.uid)",
        "content": {
          ".validate": "newData.isString() && newData.val().length <= 10000"
        },
        "lastModified": {
          ".write": "auth != null"
        },
        "collaborators": {
          "$uid": {
            ".write": "auth != null && (auth.uid == $uid || data.parent().parent().child('owner').val() == auth.uid)"
          }
        }
      }
    },
    "users": {
      "$uid": {
        ".read": "auth != null && auth.uid == $uid",
        ".write": "auth != null && auth.uid == $uid"
      }
    }
  }
}
EOF
    
    success "Database security rules created"
}

# Function to create Cloud Functions
create_functions() {
    log "Creating Cloud Functions..."
    
    # Create functions directory
    mkdir -p functions
    
    # Create package.json for functions
    cat > functions/package.json << 'EOF'
{
  "name": "collaborative-app-functions",
  "description": "Cloud Functions for collaborative document application",
  "scripts": {
    "build": "tsc",
    "serve": "npm run build && firebase emulators:start --only functions",
    "shell": "npm run build && firebase functions:shell",
    "start": "npm run shell",
    "deploy": "firebase deploy --only functions",
    "logs": "firebase functions:log"
  },
  "engines": {
    "node": "18"
  },
  "main": "lib/index.js",
  "dependencies": {
    "firebase-admin": "^11.8.0",
    "firebase-functions": "^4.3.1"
  },
  "devDependencies": {
    "typescript": "^4.9.0"
  },
  "private": true
}
EOF

    # Create TypeScript configuration
    cat > functions/tsconfig.json << 'EOF'
{
  "compilerOptions": {
    "module": "commonjs",
    "noImplicitReturns": true,
    "noUnusedLocals": true,
    "outDir": "lib",
    "sourceMap": true,
    "strict": true,
    "target": "es2017"
  },
  "compileOnSave": true,
  "include": [
    "src"
  ]
}
EOF

    # Create functions source directory
    mkdir -p functions/src
    
    # Create main functions file
    cat > functions/src/index.ts << 'EOF'
import {onCall, onRequest, HttpsError} from 'firebase-functions/v2/https';
import {onValueWritten} from 'firebase-functions/v2/database';
import * as admin from 'firebase-admin';
import {setGlobalOptions} from 'firebase-functions/v2';

// Initialize Firebase Admin SDK
admin.initializeApp();

// Set global options
setGlobalOptions({region: 'us-central1'});

// Create new collaborative document
export const createDocument = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'User must be authenticated');
  }

  const {title, initialContent = ''} = request.data;
  
  if (!title || title.trim().length === 0) {
    throw new HttpsError('invalid-argument', 'Document title is required');
  }

  const documentId = admin.database().ref().push().key;
  const documentData = {
    title: title.trim(),
    content: initialContent,
    owner: request.auth.uid,
    collaborators: {
      [request.auth.uid]: {
        role: 'owner',
        joinedAt: admin.database.ServerValue.TIMESTAMP
      }
    },
    createdAt: admin.database.ServerValue.TIMESTAMP,
    lastModified: admin.database.ServerValue.TIMESTAMP,
    version: 1
  };

  try {
    await admin.database()
      .ref(`documents/${documentId}`)
      .set(documentData);
    
    return { documentId, title };
  } catch (error) {
    console.error('Error creating document:', error);
    throw new HttpsError('internal', 'Failed to create document');
  }
});

// Add collaborator to document
export const addCollaborator = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'User must be authenticated');
  }

  const {documentId, collaboratorEmail} = request.data;
  
  if (!documentId || !collaboratorEmail) {
    throw new HttpsError('invalid-argument', 'Document ID and collaborator email required');
  }

  try {
    // Check if user is owner
    const docSnapshot = await admin.database()
      .ref(`documents/${documentId}`)
      .once('value');
    
    const document = docSnapshot.val();
    if (!document || document.owner !== request.auth.uid) {
      throw new HttpsError('permission-denied', 'Only document owner can add collaborators');
    }

    // Find user by email
    const userRecord = await admin.auth().getUserByEmail(collaboratorEmail);
    
    // Add collaborator
    await admin.database()
      .ref(`documents/${documentId}/collaborators/${userRecord.uid}`)
      .set({
        role: 'collaborator',
        joinedAt: admin.database.ServerValue.TIMESTAMP
      });

    return { success: true, userId: userRecord.uid };
  } catch (error) {
    console.error('Error adding collaborator:', error);
    if (error.code === 'auth/user-not-found') {
      throw new HttpsError('not-found', 'User not found');
    }
    throw new HttpsError('internal', 'Failed to add collaborator');
  }
});

// Track document changes for analytics
export const trackDocumentChange = onValueWritten(
  {ref: '/documents/{documentId}/content'},
  async (event) => {
    const documentId = event.params.documentId;
    const beforeData = event.data.before?.val();
    const afterData = event.data.after?.val();

    if (beforeData !== afterData) {
      // Update last modified timestamp
      await admin.database()
        .ref(`documents/${documentId}/lastModified`)
        .set(admin.database.ServerValue.TIMESTAMP);

      // Increment version
      const versionRef = admin.database().ref(`documents/${documentId}/version`);
      await versionRef.transaction((currentVersion) => {
        return (currentVersion || 0) + 1;
      });

      console.log(`Document ${documentId} modified`);
    }
  }
);

// Get user's documents
export const getUserDocuments = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'User must be authenticated');
  }

  try {
    const snapshot = await admin.database()
      .ref('documents')
      .orderByChild(`collaborators/${request.auth.uid}`)
      .once('value');

    const documents: any[] = [];
    snapshot.forEach((child) => {
      const doc = child.val();
      if (doc && doc.collaborators && doc.collaborators[request.auth.uid]) {
        documents.push({
          id: child.key,
          title: doc.title,
          lastModified: doc.lastModified,
          role: doc.collaborators[request.auth.uid]?.role || 'viewer'
        });
      }
    });

    return { documents };
  } catch (error) {
    console.error('Error fetching documents:', error);
    throw new HttpsError('internal', 'Failed to fetch documents');
  }
});
EOF
    
    success "Cloud Functions created"
}

# Function to create frontend application
create_frontend() {
    log "Creating frontend application..."
    
    # Create public directory structure
    mkdir -p public/{js,css}
    
    # Create main HTML file
    cat > public/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Collaborative Document Editor</title>
    <link rel="stylesheet" href="css/style.css">
</head>
<body>
    <div id="app">
        <header>
            <h1>Collaborative Editor</h1>
            <div id="user-info" style="display: none;">
                <span id="user-email"></span>
                <button id="logout-btn">Logout</button>
            </div>
        </header>

        <!-- Authentication Form -->
        <div id="auth-container">
            <h2>Sign In</h2>
            <form id="auth-form">
                <input type="email" id="email" placeholder="Email" required>
                <input type="password" id="password" placeholder="Password" required>
                <button type="submit" id="signin-btn">Sign In</button>
                <button type="button" id="signup-btn">Sign Up</button>
            </form>
        </div>

        <!-- Document List -->
        <div id="documents-container" style="display: none;">
            <div class="documents-header">
                <h2>Your Documents</h2>
                <button id="create-doc-btn">Create New Document</button>
            </div>
            <div id="documents-list"></div>
        </div>

        <!-- Document Editor -->
        <div id="editor-container" style="display: none;">
            <div class="editor-header">
                <input type="text" id="document-title" placeholder="Document Title">
                <div class="collaborators">
                    <span>Collaborators:</span>
                    <div id="collaborators-list"></div>
                    <button id="add-collaborator-btn">Add Collaborator</button>
                </div>
                <button id="back-to-documents">Back to Documents</button>
            </div>
            <textarea id="document-content" placeholder="Start typing..."></textarea>
            <div class="editor-status">
                <span id="save-status">Saved</span>
                <span id="collaborator-count">1 user online</span>
            </div>
        </div>
    </div>

    <!-- Firebase SDKs -->
    <script src="https://www.gstatic.com/firebasejs/10.7.1/firebase-app-compat.js"></script>
    <script src="https://www.gstatic.com/firebasejs/10.7.1/firebase-auth-compat.js"></script>
    <script src="https://www.gstatic.com/firebasejs/10.7.1/firebase-database-compat.js"></script>
    <script src="https://www.gstatic.com/firebasejs/10.7.1/firebase-functions-compat.js"></script>
    <script src="js/config.js"></script>
    <script src="js/app.js"></script>
</body>
</html>
EOF

    # Create CSS styles
    cat > public/css/style.css << 'EOF'
* {
    margin: 0;
    padding: 0;
    box-sizing: border-box;
}

body {
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
    background-color: #f5f5f5;
    color: #333;
}

header {
    background: #4285F4;
    color: white;
    padding: 1rem 2rem;
    display: flex;
    justify-content: space-between;
    align-items: center;
}

#user-info {
    display: flex;
    align-items: center;
    gap: 1rem;
}

#auth-container {
    max-width: 400px;
    margin: 4rem auto;
    padding: 2rem;
    background: white;
    border-radius: 8px;
    box-shadow: 0 2px 10px rgba(0,0,0,0.1);
}

#auth-form {
    display: flex;
    flex-direction: column;
    gap: 1rem;
}

input, button, textarea {
    padding: 0.75rem;
    border: 1px solid #ddd;
    border-radius: 4px;
    font-size: 1rem;
}

button {
    background: #4285F4;
    color: white;
    border: none;
    cursor: pointer;
    transition: background 0.2s;
}

button:hover {
    background: #3367D6;
}

#documents-container {
    max-width: 800px;
    margin: 2rem auto;
    padding: 0 2rem;
}

.documents-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 2rem;
}

.document-item {
    background: white;
    padding: 1.5rem;
    margin-bottom: 1rem;
    border-radius: 8px;
    box-shadow: 0 2px 4px rgba(0,0,0,0.1);
    cursor: pointer;
    transition: transform 0.2s, box-shadow 0.2s;
}

.document-item:hover {
    transform: translateY(-2px);
    box-shadow: 0 4px 12px rgba(0,0,0,0.15);
}

#editor-container {
    max-width: 1000px;
    margin: 2rem auto;
    padding: 0 2rem;
}

.editor-header {
    background: white;
    padding: 1rem;
    border-radius: 8px 8px 0 0;
    display: flex;
    align-items: center;
    gap: 1rem;
    box-shadow: 0 2px 4px rgba(0,0,0,0.1);
}

#document-title {
    flex: 1;
    font-size: 1.2rem;
    font-weight: bold;
}

.collaborators {
    display: flex;
    align-items: center;
    gap: 0.5rem;
}

#collaborators-list {
    display: flex;
    gap: 0.5rem;
}

#collaborators-list span {
    background: #E8F0FE;
    color: #1967D2;
    padding: 0.25rem 0.5rem;
    border-radius: 12px;
    font-size: 0.8rem;
}

#document-content {
    width: 100%;
    height: 500px;
    border: none;
    border-radius: 0 0 8px 8px;
    padding: 2rem;
    font-size: 1rem;
    line-height: 1.6;
    resize: vertical;
    background: white;
    box-shadow: 0 2px 4px rgba(0,0,0,0.1);
}

.editor-status {
    display: flex;
    justify-content: space-between;
    padding: 0.5rem 1rem;
    background: #f8f9fa;
    border-radius: 0 0 8px 8px;
    font-size: 0.9rem;
    color: #666;
}

#save-status {
    color: #0F9D58;
}

@media (max-width: 768px) {
    .editor-header {
        flex-direction: column;
        align-items: stretch;
        gap: 0.5rem;
    }
    
    .collaborators {
        justify-content: space-between;
    }
}
EOF

    success "Frontend application created"
}

# Function to create Firebase configuration
create_firebase_config() {
    local project_id="$1"
    
    log "Creating Firebase configuration..."
    
    # Get Firebase config
    local firebase_config
    firebase_config=$(firebase apps:sdkconfig web --project "$project_id" 2>/dev/null | grep -A 20 "const firebaseConfig" | head -n 15 || echo "")
    
    if [[ -z "$firebase_config" ]]; then
        warning "Could not retrieve Firebase config automatically. Creating placeholder config."
        cat > public/js/config.js << EOF
// Firebase configuration - Replace with your actual config
const firebaseConfig = {
  apiKey: "your-api-key",
  authDomain: "${project_id}.firebaseapp.com",
  databaseURL: "https://${project_id}-default-rtdb.firebaseio.com/",
  projectId: "${project_id}",
  storageBucket: "${project_id}.appspot.com",
  messagingSenderId: "your-sender-id",
  appId: "your-app-id"
};

// Initialize Firebase
firebase.initializeApp(firebaseConfig);
EOF
        warning "Please update public/js/config.js with your actual Firebase configuration"
    else
        echo "$firebase_config" > public/js/config.js
        success "Firebase configuration created"
    fi
}

# Function to create JavaScript application
create_javascript_app() {
    log "Creating JavaScript application logic..."
    
    cat > public/js/app.js << 'EOF'
// Initialize Firebase services
const auth = firebase.auth();
const database = firebase.database();
const functions = firebase.functions();

// Global variables
let currentUser = null;
let currentDocument = null;
let documentRef = null;
let isUpdating = false;

// UI elements
const authContainer = document.getElementById('auth-container');
const documentsContainer = document.getElementById('documents-container');
const editorContainer = document.getElementById('editor-container');
const userInfo = document.getElementById('user-info');
const userEmail = document.getElementById('user-email');

// Authentication state observer
auth.onAuthStateChanged((user) => {
  if (user) {
    currentUser = user;
    userEmail.textContent = user.email;
    showDocuments();
  } else {
    currentUser = null;
    showAuth();
  }
});

// Authentication functions
document.getElementById('auth-form').addEventListener('submit', async (e) => {
  e.preventDefault();
  const email = document.getElementById('email').value;
  const password = document.getElementById('password').value;

  try {
    await auth.signInWithEmailAndPassword(email, password);
  } catch (error) {
    console.error('Sign in error:', error);
    alert('Sign in failed: ' + error.message);
  }
});

document.getElementById('signup-btn').addEventListener('click', async () => {
  const email = document.getElementById('email').value;
  const password = document.getElementById('password').value;

  if (!email || !password) {
    alert('Please enter email and password');
    return;
  }

  try {
    await auth.createUserWithEmailAndPassword(email, password);
  } catch (error) {
    console.error('Sign up error:', error);
    alert('Sign up failed: ' + error.message);
  }
});

document.getElementById('logout-btn').addEventListener('click', () => {
  auth.signOut();
});

// Document management
document.getElementById('create-doc-btn').addEventListener('click', async () => {
  const title = prompt('Document title:');
  if (!title) return;

  try {
    const createDocument = functions.httpsCallable('createDocument');
    const result = await createDocument({ title });
    loadDocuments();
    openDocument(result.data.documentId);
  } catch (error) {
    console.error('Create document error:', error);
    alert('Failed to create document: ' + error.message);
  }
});

document.getElementById('back-to-documents').addEventListener('click', () => {
  if (documentRef) {
    documentRef.off();
    documentRef = null;
  }
  currentDocument = null;
  showDocuments();
});

// Real-time document editing
const documentContent = document.getElementById('document-content');
let debounceTimer;

documentContent.addEventListener('input', () => {
  if (isUpdating) return;

  clearTimeout(debounceTimer);
  document.getElementById('save-status').textContent = 'Saving...';
  
  debounceTimer = setTimeout(() => {
    if (documentRef) {
      documentRef.child('content').set(documentContent.value);
    }
  }, 500);
});

// UI state management
function showAuth() {
  authContainer.style.display = 'block';
  documentsContainer.style.display = 'none';
  editorContainer.style.display = 'none';
  userInfo.style.display = 'none';
}

function showDocuments() {
  authContainer.style.display = 'none';
  documentsContainer.style.display = 'block';
  editorContainer.style.display = 'none';
  userInfo.style.display = 'flex';
  loadDocuments();
}

function showEditor() {
  authContainer.style.display = 'none';
  documentsContainer.style.display = 'none';
  editorContainer.style.display = 'block';
  userInfo.style.display = 'flex';
}

// Load user documents
async function loadDocuments() {
  try {
    const getUserDocuments = functions.httpsCallable('getUserDocuments');
    const result = await getUserDocuments();
    
    const documentsList = document.getElementById('documents-list');
    documentsList.innerHTML = '';

    if (result.data.documents.length === 0) {
      documentsList.innerHTML = '<p>No documents yet. Create your first document!</p>';
      return;
    }

    result.data.documents.forEach(doc => {
      const docElement = document.createElement('div');
      docElement.className = 'document-item';
      docElement.innerHTML = `
        <h3>${doc.title}</h3>
        <p>Role: ${doc.role}</p>
        <p>Last modified: ${new Date(doc.lastModified).toLocaleString()}</p>
      `;
      docElement.addEventListener('click', () => openDocument(doc.id));
      documentsList.appendChild(docElement);
    });
  } catch (error) {
    console.error('Load documents error:', error);
    document.getElementById('documents-list').innerHTML = '<p>Error loading documents. Please try again.</p>';
  }
}

// Open document for editing
function openDocument(documentId) {
  currentDocument = documentId;
  documentRef = database.ref(`documents/${documentId}`);
  
  // Listen for real-time changes
  documentRef.on('value', (snapshot) => {
    const doc = snapshot.val();
    if (!doc) return;

    isUpdating = true;
    document.getElementById('document-title').value = doc.title;
    document.getElementById('document-content').value = doc.content || '';
    document.getElementById('save-status').textContent = 'Saved';
    
    // Update collaborators list
    const collaboratorsList = document.getElementById('collaborators-list');
    collaboratorsList.innerHTML = '';
    Object.keys(doc.collaborators || {}).forEach(uid => {
      const span = document.createElement('span');
      span.textContent = doc.collaborators[uid].role;
      collaboratorsList.appendChild(span);
    });
    
    isUpdating = false;
  });

  showEditor();
}

// Add collaborator
document.getElementById('add-collaborator-btn').addEventListener('click', async () => {
  const email = prompt('Collaborator email:');
  if (!email || !currentDocument) return;

  try {
    const addCollaborator = functions.httpsCallable('addCollaborator');
    await addCollaborator({ 
      documentId: currentDocument, 
      collaboratorEmail: email 
    });
    alert('Collaborator added successfully!');
  } catch (error) {
    console.error('Add collaborator error:', error);
    alert('Failed to add collaborator: ' + error.message);
  }
});
EOF
    
    success "JavaScript application logic created"
}

# Function to deploy Firebase services
deploy_firebase() {
    local project_id="$1"
    
    log "Installing Function dependencies..."
    cd functions
    npm install
    cd ..
    
    log "Deploying Firebase services..."
    
    # Deploy database rules first
    firebase deploy --only database --project "$project_id"
    success "Database rules deployed"
    
    # Deploy functions
    firebase deploy --only functions --project "$project_id"
    success "Cloud Functions deployed"
    
    # Deploy hosting
    firebase deploy --only hosting --project "$project_id"
    success "Firebase Hosting deployed"
    
    # Get hosting URL
    local hosting_url="https://${project_id}.web.app"
    success "Application deployed successfully!"
    echo -e "${GREEN}🌐 Your collaborative application is available at: ${hosting_url}${NC}"
}

# Function to enable required APIs
enable_apis() {
    local project_id="$1"
    
    log "Enabling required Google Cloud APIs..."
    
    # Enable Firebase APIs
    gcloud services enable firebase.googleapis.com --project="$project_id" 2>/dev/null || true
    gcloud services enable firebasehosting.googleapis.com --project="$project_id" 2>/dev/null || true
    gcloud services enable firebasedatabase.googleapis.com --project="$project_id" 2>/dev/null || true
    gcloud services enable cloudfunctions.googleapis.com --project="$project_id" 2>/dev/null || true
    
    success "Required APIs enabled"
}

# Main deployment function
main() {
    echo -e "${BLUE}"
    echo "================================================"
    echo "  Firebase Collaborative App Deployment Script"
    echo "================================================"
    echo -e "${NC}"
    
    # Check prerequisites
    log "Checking prerequisites..."
    check_command "firebase"
    check_command "node"
    check_command "npm"
    check_command "jq"
    
    # Check if gcloud is available (optional but recommended)
    if command -v gcloud &> /dev/null; then
        log "Google Cloud CLI detected - will enable APIs if needed"
        GCLOUD_AVAILABLE=true
    else
        warning "Google Cloud CLI not found - skipping API enablement"
        GCLOUD_AVAILABLE=false
    fi
    
    success "Prerequisites check completed"
    
    # Check Firebase authentication
    check_firebase_auth
    
    # Get project configuration
    if [[ -n "${PROJECT_ID:-}" ]]; then
        PROJECT_ID="${PROJECT_ID}"
        log "Using PROJECT_ID from environment: ${PROJECT_ID}"
    else
        PROJECT_ID="collab-app-$(date +%s)"
        log "Generated PROJECT_ID: ${PROJECT_ID}"
    fi
    
    if [[ -n "${DISPLAY_NAME:-}" ]]; then
        DISPLAY_NAME="${DISPLAY_NAME}"
    else
        DISPLAY_NAME="Collaborative Document Editor"
    fi
    
    validate_project_name "$PROJECT_ID"
    
    # Create and configure Firebase project
    create_firebase_project "$PROJECT_ID" "$DISPLAY_NAME"
    
    # Enable APIs if gcloud is available
    if [[ "$GCLOUD_AVAILABLE" == "true" ]]; then
        enable_apis "$PROJECT_ID"
    fi
    
    # Initialize Firebase project
    init_firebase_project "$PROJECT_ID"
    
    # Create application components
    create_database_rules
    create_functions
    create_frontend
    create_firebase_config "$PROJECT_ID"
    create_javascript_app
    
    # Deploy everything
    deploy_firebase "$PROJECT_ID"
    
    # Final success message
    echo -e "${GREEN}"
    echo "================================================"
    echo "            Deployment Completed! 🎉"
    echo "================================================"
    echo -e "${NC}"
    echo "Project ID: ${PROJECT_ID}"
    echo "Application URL: https://${PROJECT_ID}.web.app"
    echo ""
    echo "Next steps:"
    echo "1. Open the application URL in your browser"
    echo "2. Create a user account"
    echo "3. Start creating collaborative documents"
    echo "4. Share documents with other users via email"
    echo ""
    echo "To manage your Firebase project:"
    echo "- Firebase Console: https://console.firebase.google.com/project/${PROJECT_ID}"
    echo "- View functions logs: firebase functions:log --project ${PROJECT_ID}"
    echo ""
    success "Deployment completed successfully!"
}

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi