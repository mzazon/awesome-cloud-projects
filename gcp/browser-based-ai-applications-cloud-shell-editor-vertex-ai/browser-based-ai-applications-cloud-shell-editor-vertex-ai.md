---
title: Developing Browser-Based AI Applications with Cloud Shell Editor and Vertex AI
id: f7e8a9b2
category: developer-tools
difficulty: 200
subject: gcp
services: Cloud Shell Editor, Vertex AI, Cloud Build, Cloud Run
estimated-time: 120 minutes
recipe-version: 1.1
requested-by: mzazon
last-updated: 2025-07-12
last-reviewed: 2025-07-23
passed-qa: null
tags: browser-development, ai-applications, serverless, cloud-ide, vertex-ai
recipe-generator-version: 1.3
---

# Developing Browser-Based AI Applications with Cloud Shell Editor and Vertex AI

## Problem

Modern AI application development often requires complex local development environments with GPU resources, multiple AI libraries, and expensive hardware setup. Developers face challenges maintaining consistent development environments across teams, managing AI model dependencies, and accessing powerful compute resources for training and inference. Traditional development workflows create barriers to entry for AI development and slow down the iteration cycle from prototype to production deployment.

## Solution

Create a complete browser-based AI application development workflow using Google Cloud Shell Editor as a zero-setup development environment, integrating Vertex AI for intelligent features, and deploying through Cloud Build to Cloud Run. This approach eliminates local environment setup while providing access to enterprise-grade AI capabilities and scalable deployment infrastructure directly from any web browser.

## Architecture Diagram

```mermaid
graph TB
    subgraph "Development Environment"
        CSE[Cloud Shell Editor]
        CST[Cloud Shell Terminal]
    end
    
    subgraph "AI/ML Services"
        VAI[Vertex AI]
        GEM[Gemini Models]
        MG[Model Garden]
    end
    
    subgraph "CI/CD Pipeline"
        CB[Cloud Build]
        AR[Artifact Registry]
        GCR[GitHub Repository]
    end
    
    subgraph "Production"
        CR[Cloud Run]
        LB[Load Balancer]
        USER[End Users]
    end
    
    CSE --> CST
    CSE --> VAI
    CSE --> GCR
    VAI --> GEM
    VAI --> MG
    GCR --> CB
    CB --> AR
    AR --> CR
    CR --> LB
    LB --> USER
    
    style VAI fill:#4285F4
    style CSE fill:#34A853
    style CR fill:#EA4335
    style CB fill:#FBBC04
```

## Prerequisites

1. Google Cloud account with billing enabled and Vertex AI API access
2. Basic understanding of Python web development and REST APIs
3. Familiarity with AI/ML concepts and prompt engineering
4. Web browser with internet access (Chrome, Firefox, Safari, or Edge)
5. Estimated cost: $5-15 for Cloud Run, Cloud Build, and Vertex AI usage during development

> **Note**: Cloud Shell provides 50 hours of usage per week and 5GB of persistent storage at no additional cost, making it ideal for development workflows without local environment requirements.

## Preparation

```bash
# Set environment variables for project configuration
export PROJECT_ID="ai-app-dev-$(date +%s)"
export REGION="us-central1"
export SERVICE_NAME="ai-chat-assistant"

# Generate unique identifiers for resources
RANDOM_SUFFIX=$(openssl rand -hex 3)
export REPO_NAME="ai-app-repo-${RANDOM_SUFFIX}"

# Create new project for isolated development
gcloud projects create ${PROJECT_ID} \
    --name="AI Application Development" \
    --labels="purpose=ai-development,environment=demo"

# Set project as default
gcloud config set project ${PROJECT_ID}
gcloud config set compute/region ${REGION}

# Enable required Google Cloud APIs
gcloud services enable cloudbuild.googleapis.com
gcloud services enable run.googleapis.com
gcloud services enable aiplatform.googleapis.com
gcloud services enable artifactregistry.googleapis.com

echo "✅ Project ${PROJECT_ID} configured with required APIs enabled"
```

## Steps

1. **Launch Cloud Shell Editor and Initialize Development Environment**:

   Cloud Shell Editor provides a fully-featured, browser-based IDE powered by Visual Studio Code, eliminating the need for local development setup. This managed environment includes pre-installed development tools, Google Cloud CLI, and persistent storage, enabling immediate productivity without configuration overhead.

   ```bash
   # Navigate to Cloud Shell Editor
   # Open https://ide.cloud.google.com in your browser
   
   # Create project directory structure
   mkdir -p ${SERVICE_NAME}/{app,tests,config}
   cd ${SERVICE_NAME}
   
   # Initialize Python virtual environment
   python3 -m venv venv
   source venv/bin/activate
   
   # Create requirements.txt with current stable dependencies
   cat > requirements.txt << 'EOF'
   flask==3.1.1
   google-genai==0.7.0
   vertexai==1.75.0
   gunicorn==23.0.0
   requests==2.32.3
   python-dotenv==1.0.1
   EOF
   
   echo "✅ Development environment initialized in Cloud Shell Editor"
   ```

   The Cloud Shell Editor now provides a complete development workspace with syntax highlighting, debugging capabilities, and integrated terminal access. This browser-based environment scales from simple scripts to complex applications while maintaining consistency across development teams.

2. **Create AI-Powered Web Application Structure**:

   Building a modular application structure enables maintainable AI applications that can evolve with changing requirements. This Flask-based architecture separates concerns between web handling, AI processing, and configuration management, following Google Cloud best practices for microservices development.

   ```bash
   # Create main application file with modern Vertex AI integration
   cat > app/main.py << 'EOF'
   import os
   import logging
   from flask import Flask, request, jsonify, render_template
   
   # Configure logging
   logging.basicConfig(level=logging.INFO)
   logger = logging.getLogger(__name__)
   
   app = Flask(__name__)
   
   # Import AI configuration after Flask app initialization
   from ai_config import VertexAIClient
   
   # Initialize Vertex AI client
   ai_client = VertexAIClient()
   
   @app.route('/')
   def home():
       """Serve main chat interface"""
       return render_template('index.html')
   
   @app.route('/api/chat', methods=['POST'])
   def chat():
       """Handle chat API requests with comprehensive error handling"""
       try:
           data = request.get_json()
           user_message = data.get('message', '').strip()
           
           if not user_message:
               return jsonify({
                   'error': 'Message is required', 
                   'status': 'error'
               }), 400
           
           # Generate AI response with error handling
           ai_response = ai_client.generate_response(user_message)
           
           # Analyze sentiment for additional insights
           sentiment = ai_client.analyze_sentiment(user_message)
           
           return jsonify({
               'response': ai_response,
               'sentiment': sentiment,
               'status': 'success'
           })
           
       except Exception as e:
           logger.error(f"Chat API error: {str(e)}")
           return jsonify({
               'error': 'Failed to process message',
               'status': 'error'
           }), 500
   
   @app.route('/health')
   def health():
       """Health check endpoint for monitoring"""
       return jsonify({
           'status': 'healthy', 
           'service': 'ai-chat-assistant',
           'version': '1.0'
       })
   
   if __name__ == '__main__':
       port = int(os.environ.get('PORT', 8080))
       app.run(host='0.0.0.0', port=port, debug=False)
   EOF
   
   # Create HTML template directory
   mkdir -p app/templates
   
   echo "✅ Application structure created with modern AI integration"
   ```

   The Flask application now includes structured error handling, logging, and modular design patterns that scale from development to production. The updated architecture follows current Flask security best practices and provides comprehensive API response handling.

3. **Build Interactive Frontend with AI Chat Interface**:

   Modern web applications require responsive interfaces that provide real-time feedback during AI processing. This HTML/JavaScript frontend implements best practices for user experience during asynchronous AI operations, including loading states and error handling.

   ```bash
   # Create responsive HTML interface with modern design
   cat > app/templates/index.html << 'EOF'
   <!DOCTYPE html>
   <html lang="en">
   <head>
       <meta charset="UTF-8">
       <meta name="viewport" content="width=device-width, initial-scale=1.0">
       <title>AI Chat Assistant</title>
       <style>
           * { margin: 0; padding: 0; box-sizing: border-box; }
           body { 
               font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
               background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
               height: 100vh; display: flex; align-items: center; 
               justify-content: center;
           }
           .chat-container {
               background: white; border-radius: 15px; 
               box-shadow: 0 20px 40px rgba(0,0,0,0.1);
               width: 90%; max-width: 600px; height: 80vh; 
               display: flex; flex-direction: column;
           }
           .chat-header {
               background: #4285f4; color: white; padding: 20px; 
               border-radius: 15px 15px 0 0;
               text-align: center; font-size: 1.2em; font-weight: bold;
           }
           .chat-messages {
               flex: 1; padding: 20px; overflow-y: auto; 
               background: #f8f9fa;
           }
           .message {
               margin: 10px 0; padding: 12px 16px; border-radius: 18px; 
               max-width: 80%; word-wrap: break-word;
           }
           .user-message {
               background: #e3f2fd; margin-left: auto; text-align: right;
           }
           .ai-message {
               background: #f1f3f4; margin-right: auto;
           }
           .chat-input {
               display: flex; padding: 20px; border-top: 1px solid #e0e0e0;
           }
           .chat-input input {
               flex: 1; padding: 12px; border: 1px solid #ddd; 
               border-radius: 25px; outline: none; font-size: 16px;
           }
           .chat-input button {
               margin-left: 10px; padding: 12px 24px; background: #4285f4;
               color: white; border: none; border-radius: 25px; 
               cursor: pointer; transition: background-color 0.3s;
           }
           .chat-input button:hover { background: #3367d6; }
           .loading { opacity: 0.7; pointer-events: none; }
           .error-message { color: #d32f2f; font-style: italic; }
       </style>
   </head>
   <body>
       <div class="chat-container">
           <div class="chat-header">
               🤖 AI Chat Assistant - Powered by Vertex AI
           </div>
           <div id="chat-messages" class="chat-messages">
               <div class="message ai-message">
                   Hello! I'm your AI assistant powered by Google's Vertex AI. 
                   How can I help you today?
               </div>
           </div>
           <div class="chat-input">
               <input type="text" id="user-input" 
                      placeholder="Type your message here..." />
               <button onclick="sendMessage()">Send</button>
           </div>
       </div>
   
       <script>
           async function sendMessage() {
               const input = document.getElementById('user-input');
               const message = input.value.trim();
               if (!message) return;
   
               // Add user message to chat
               addMessage(message, 'user');
               input.value = '';
   
               // Show loading state
               const chatContainer = document.querySelector('.chat-container');
               chatContainer.classList.add('loading');
   
               try {
                   const response = await fetch('/api/chat', {
                       method: 'POST',
                       headers: { 'Content-Type': 'application/json' },
                       body: JSON.stringify({ message: message })
                   });
   
                   const data = await response.json();
                   
                   if (data.status === 'success') {
                       addMessage(data.response, 'ai');
                   } else {
                       addMessage('Sorry, I encountered an error. Please try again.', 
                                'ai', true);
                   }
               } catch (error) {
                   console.error('Network error:', error);
                   addMessage('Connection error. Please check your internet connection.', 
                            'ai', true);
               }
   
               chatContainer.classList.remove('loading');
           }
   
           function addMessage(text, sender, isError = false) {
               const messagesDiv = document.getElementById('chat-messages');
               const messageDiv = document.createElement('div');
               messageDiv.className = `message ${sender}-message`;
               if (isError) messageDiv.classList.add('error-message');
               messageDiv.textContent = text;
               messagesDiv.appendChild(messageDiv);
               messagesDiv.scrollTop = messagesDiv.scrollHeight;
           }
   
           // Enable Enter key to send messages
           document.getElementById('user-input').addEventListener('keypress', 
               function(e) {
                   if (e.key === 'Enter') sendMessage();
               });
       </script>
   </body>
   </html>
   EOF
   
   echo "✅ Interactive frontend created with modern UI/UX patterns"
   ```

   The frontend now provides a professional chat interface with responsive design, loading states, and comprehensive error handling. This implementation follows Google's Material Design principles and provides optimal user experience across devices.

4. **Configure Vertex AI Integration with Modern Gen AI SDK**:

   Vertex AI provides enterprise-grade machine learning capabilities through managed APIs, eliminating the complexity of model deployment and scaling. The new Gen AI SDK offers improved performance and simplified authentication for production applications.

   ```bash
   # Create modern Vertex AI configuration with Gen AI SDK
   cat > app/ai_config.py << 'EOF'
   import os
   import logging
   from google import genai
   from google.genai.types import GenerateContentConfig
   
   logger = logging.getLogger(__name__)
   
   class VertexAIClient:
       def __init__(self):
           self.project_id = os.getenv('GOOGLE_CLOUD_PROJECT')
           self.region = os.getenv('GOOGLE_CLOUD_REGION', 'us-central1')
           
           # Initialize Gen AI client for Vertex AI
           self.client = genai.Client(
               vertexai=True, 
               project=self.project_id, 
               location=self.region
           )
           
           # Configure generation settings for optimal performance
           self.generation_config = GenerateContentConfig(
               temperature=0.7,
               top_p=0.8,
               max_output_tokens=1000,
               response_modalities=["TEXT"]
           )
           
           logger.info(f"Vertex AI client initialized for project: {self.project_id}")
   
       def generate_response(self, prompt, max_tokens=1000):
           """Generate AI response with modern Gen AI SDK"""
           try:
               # Update config for this request if needed
               config = GenerateContentConfig(
                   temperature=0.7,
                   top_p=0.8,
                   max_output_tokens=max_tokens,
                   response_modalities=["TEXT"]
               )
               
               # Generate content using Gemini model
               response = self.client.models.generate_content(
                   model='gemini-2.0-flash',
                   contents=f"You are a helpful AI assistant. Respond to: {prompt}",
                   config=config
               )
               
               return response.text
               
           except Exception as e:
               logger.error(f"Vertex AI generation error: {str(e)}")
               return ("I apologize, but I'm having trouble processing your "
                      "request right now. Please try again.")
   
       def analyze_sentiment(self, text):
           """Analyze sentiment using Vertex AI with simplified prompt"""
           try:
               config = GenerateContentConfig(
                   temperature=0.1,
                   max_output_tokens=10,
                   response_modalities=["TEXT"]
               )
               
               prompt = (f"Analyze the sentiment of this text and respond with "
                        f"just one word - positive, negative, or neutral: {text}")
               
               response = self.client.models.generate_content(
                   model='gemini-2.0-flash',
                   contents=prompt,
                   config=config
               )
               
               return response.text.strip().lower()
               
           except Exception as e:
               logger.error(f"Sentiment analysis error: {str(e)}")
               return "neutral"
   EOF
   
   echo "✅ Modern Vertex AI integration configured with Gen AI SDK"
   ```

   The application now leverages the latest Gen AI SDK for improved performance and reliability. The modular design enables easy model switching and supports advanced features like sentiment analysis while maintaining production-ready error handling.

5. **Set Up Cloud Build for Automated Deployment**:

   Cloud Build provides fully managed CI/CD capabilities that integrate seamlessly with Google Cloud services. This configuration creates automated build and deployment pipelines triggered by code changes, following DevOps best practices for AI applications.

   ```bash
   # Create optimized Dockerfile for containerized deployment
   cat > Dockerfile << 'EOF'
   FROM python:3.11-slim
   
   # Set working directory
   WORKDIR /app
   
   # Install system dependencies for security and performance
   RUN apt-get update && apt-get install -y \
       gcc \
       && rm -rf /var/lib/apt/lists/* \
       && apt-get clean
   
   # Copy requirements and install Python dependencies
   COPY requirements.txt .
   RUN pip install --no-cache-dir --upgrade pip \
       && pip install --no-cache-dir -r requirements.txt
   
   # Copy application code
   COPY app/ ./app/
   
   # Set environment variables for production
   ENV FLASK_APP=app.main:app
   ENV PYTHONPATH=/app
   ENV PYTHONUNBUFFERED=1
   
   # Create non-root user for security
   RUN useradd --create-home --shell /bin/bash app \
       && chown -R app:app /app
   USER app
   
   # Expose port
   EXPOSE 8080
   
   # Run application with Gunicorn for production
   CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", \
        "--timeout", "120", "--preload", "app.main:app"]
   EOF
   
   # Create Cloud Build configuration with security best practices
   cat > cloudbuild.yaml << 'EOF'
   steps:
     # Build the container image
     - name: 'gcr.io/cloud-builders/docker'
       args: ['build', '-t', 'gcr.io/$PROJECT_ID/${_SERVICE_NAME}:$COMMIT_SHA', '.']
   
     # Push the container image to Container Registry
     - name: 'gcr.io/cloud-builders/docker'
       args: ['push', 'gcr.io/$PROJECT_ID/${_SERVICE_NAME}:$COMMIT_SHA']
   
     # Deploy to Cloud Run with security configurations
     - name: 'gcr.io/cloud-builders/gcloud'
       args:
         - 'run'
         - 'deploy'
         - '${_SERVICE_NAME}'
         - '--image=gcr.io/$PROJECT_ID/${_SERVICE_NAME}:$COMMIT_SHA'
         - '--region=${_REGION}'
         - '--platform=managed'
         - '--allow-unauthenticated'
         - '--memory=1Gi'
         - '--cpu=1'
         - '--max-instances=10'
         - '--min-instances=0'
         - '--concurrency=80'
         - '--cpu-throttling'
         - '--set-env-vars=GOOGLE_CLOUD_PROJECT=$PROJECT_ID,GOOGLE_CLOUD_REGION=${_REGION}'
   
   substitutions:
     _SERVICE_NAME: 'ai-chat-assistant'
     _REGION: 'us-central1'
   
   options:
     logging: CLOUD_LOGGING_ONLY
     substitution_option: 'ALLOW_LOOSE'
   EOF
   
   echo "✅ Cloud Build configuration created with security best practices"
   ```

   The containerized deployment approach ensures consistency across development and production environments. Cloud Build's managed infrastructure handles scaling, security updates, and integration with Google Cloud services automatically.

6. **Deploy Application Using Cloud Run**:

   Cloud Run provides serverless container hosting that scales from zero to handle traffic spikes automatically. This deployment model is ideal for AI applications with variable workloads, offering pay-per-use pricing and built-in security features.

   ```bash
   # Install dependencies in Cloud Shell
   pip install -r requirements.txt
   
   # Test application locally first
   export GOOGLE_CLOUD_PROJECT=${PROJECT_ID}
   export GOOGLE_CLOUD_REGION=${REGION}
   
   # Run local development server
   cd app && python main.py &
   LOCAL_PID=$!
   
   # Wait for application startup
   sleep 5
   
   # Test local endpoints
   curl -s http://localhost:8080/health | jq '.'
   
   curl -X POST http://localhost:8080/api/chat \
       -H "Content-Type: application/json" \
       -d '{"message": "Hello, can you help me with Google Cloud?"}' | jq '.'
   
   # Stop local server
   kill $LOCAL_PID 2>/dev/null || true
   cd ..
   
   # Build and deploy to Cloud Run
   gcloud builds submit \
       --config cloudbuild.yaml \
       --substitutions _SERVICE_NAME=${SERVICE_NAME},_REGION=${REGION}
   
   # Get service URL and verify deployment
   SERVICE_URL=$(gcloud run services describe ${SERVICE_NAME} \
       --region=${REGION} \
       --format="value(status.url)")
   
   echo "✅ Application deployed to Cloud Run: ${SERVICE_URL}"
   echo "🔗 Access your AI application at: ${SERVICE_URL}"
   ```

   The application is now running on Google's managed infrastructure with automatic scaling, HTTPS termination, and global load balancing. Cloud Run's serverless model eliminates server management while providing enterprise-grade reliability.

7. **Configure Advanced AI Features and Monitoring**:

   Production AI applications require comprehensive monitoring, error tracking, and performance optimization. Cloud Shell Editor enables advanced configuration through its integrated terminal and file management capabilities.

   ```bash
   # Create advanced AI configuration with intelligent routing
   cat > app/advanced_ai.py << 'EOF'
   import logging
   import time
   from google import genai
   from google.genai.types import GenerateContentConfig
   
   logger = logging.getLogger(__name__)
   
   class AdvancedAIService:
       def __init__(self, project_id, region):
           self.project_id = project_id
           self.region = region
           
           # Initialize Gen AI client
           self.client = genai.Client(
               vertexai=True, 
               project=project_id, 
               location=region
           )
           
           # Configure different models for different use cases
           self.chat_config = GenerateContentConfig(
               temperature=0.7,
               top_p=0.8,
               max_output_tokens=1000,
               response_modalities=["TEXT"]
           )
           
           self.code_config = GenerateContentConfig(
               temperature=0.3,
               top_p=0.9,
               max_output_tokens=1500,
               response_modalities=["TEXT"]
           )
           
           logger.info("Advanced AI service initialized with intelligent routing")
   
       def intelligent_routing(self, message):
           """Route messages to appropriate AI model based on content analysis"""
           code_keywords = ['code', 'programming', 'function', 'debug', 'script', 
                           'python', 'javascript', 'sql', 'error']
           
           if any(keyword in message.lower() for keyword in code_keywords):
               return self.generate_code_response(message)
           else:
               return self.generate_chat_response(message)
   
       def generate_chat_response(self, message):
           """Generate conversational response optimized for general queries"""
           try:
               start_time = time.time()
               
               prompt = f"""You are a helpful AI assistant. Provide a clear, 
               informative response to: {message}
               
               Keep responses concise but complete and engaging."""
               
               response = self.client.models.generate_content(
                   model='gemini-2.0-flash',
                   contents=prompt,
                   config=self.chat_config
               )
               
               processing_time = time.time() - start_time
               logger.info(f"Chat response generated in {processing_time:.2f}s")
               
               return response.text
               
           except Exception as e:
               logger.error(f"Chat generation error: {str(e)}")
               return "I apologize, but I'm having trouble with that request."
   
       def generate_code_response(self, message):
           """Generate code-focused response with technical accuracy"""
           try:
               start_time = time.time()
               
               prompt = f"""You are a coding assistant and technical expert. 
               Help with this request: {message}
               
               Provide accurate code examples when relevant and explain 
               your solutions clearly with best practices."""
               
               response = self.client.models.generate_content(
                   model='gemini-2.0-flash',
                   contents=prompt,
                   config=self.code_config
               )
               
               processing_time = time.time() - start_time
               logger.info(f"Code response generated in {processing_time:.2f}s")
               
               return response.text
               
           except Exception as e:
               logger.error(f"Code generation error: {str(e)}")
               return "I'm having trouble with that coding request. Please try rephrasing."
   EOF
   
   # Update main application to use advanced features
   sed -i 's/from ai_config import VertexAIClient/from advanced_ai import AdvancedAIService/' app/main.py
   sed -i 's/ai_client = VertexAIClient()/ai_client = AdvancedAIService(os.environ.get("GOOGLE_CLOUD_PROJECT"), os.environ.get("GOOGLE_CLOUD_REGION", "us-central1"))/' app/main.py
   sed -i 's/ai_response = ai_client.generate_response(user_message)/ai_response = ai_client.intelligent_routing(user_message)/' app/main.py
   
   echo "✅ Advanced AI features configured with intelligent routing"
   ```

   The application now includes intelligent message routing, performance monitoring, and optimized model selection. These enterprise features improve response quality while maintaining cost efficiency through appropriate model usage.

## Validation & Testing

1. **Verify Cloud Shell Editor Environment Setup**:

   ```bash
   # Check development environment
   pwd
   ls -la ${SERVICE_NAME}/
   source ${SERVICE_NAME}/venv/bin/activate
   python --version
   pip list | grep -E "(flask|genai|vertexai)"
   ```

   Expected output: Python 3.11+ with Flask, Gen AI SDK, and Vertex AI libraries installed

2. **Test Local AI Application Functionality**:

   ```bash
   # Navigate to application directory
   cd ${SERVICE_NAME}
   
   # Set required environment variables
   export GOOGLE_CLOUD_PROJECT=${PROJECT_ID}
   export GOOGLE_CLOUD_REGION=${REGION}
   
   # Test application locally
   python app/main.py &
   APP_PID=$!
   sleep 5
   
   # Test health endpoint
   curl -s http://localhost:8080/health | jq '.'
   
   # Test AI chat endpoint
   curl -X POST http://localhost:8080/api/chat \
       -H "Content-Type: application/json" \
       -d '{"message": "Explain cloud computing in simple terms"}' | jq '.'
   
   # Test code-related query
   curl -X POST http://localhost:8080/api/chat \
       -H "Content-Type: application/json" \
       -d '{"message": "Write a Python function to reverse a string"}' | jq '.'
   
   # Clean up
   kill $APP_PID 2>/dev/null || true
   cd ..
   ```

   Expected output: JSON responses with successful AI-generated content and sentiment analysis

3. **Validate Cloud Run Deployment and Performance**:

   ```bash
   # Check service status and configuration
   gcloud run services describe ${SERVICE_NAME} \
       --region=${REGION} \
       --format="table(metadata.name,status.url,status.conditions[0].type,spec.template.spec.containers[0].resources.limits)"
   
   # Test deployed service endpoints
   SERVICE_URL=$(gcloud run services describe ${SERVICE_NAME} \
       --region=${REGION} \
       --format="value(status.url)")
   
   # Health check
   curl -s "${SERVICE_URL}/health" | jq '.'
   
   # Test AI functionality on deployed service
   curl -X POST "${SERVICE_URL}/api/chat" \
       -H "Content-Type: application/json" \
       -d '{"message": "What are the benefits of serverless computing?"}' | jq '.'
   
   # Performance test with multiple requests
   for i in {1..3}; do
     echo "Request $i:"
     time curl -s -X POST "${SERVICE_URL}/api/chat" \
         -H "Content-Type: application/json" \
         -d '{"message": "Hello AI assistant"}' | jq '.status'
   done
   ```

   Expected output: Service running with HTTPS URL, functional AI responses, and consistent performance

## Cleanup

1. **Remove Cloud Run Service and Container Images**:

   ```bash
   # Delete Cloud Run service
   gcloud run services delete ${SERVICE_NAME} \
       --region=${REGION} \
       --quiet
   
   # List and delete container images
   gcloud container images list --repository=gcr.io/${PROJECT_ID}
   
   gcloud container images delete gcr.io/${PROJECT_ID}/${SERVICE_NAME} \
       --force-delete-tags \
       --quiet
   
   echo "✅ Cloud Run service and container images cleaned up"
   ```

2. **Remove Project Resources**:

   ```bash
   # Delete the entire project to ensure complete cleanup
   gcloud projects delete ${PROJECT_ID} --quiet
   
   # Confirm deletion
   echo "✅ Project ${PROJECT_ID} scheduled for deletion"
   echo "📋 Note: Project deletion completes in approximately 30 days"
   echo "💰 All resources will be removed to prevent ongoing charges"
   ```

## Discussion

This recipe demonstrates the power of browser-based AI application development using Google Cloud's managed services. Cloud Shell Editor eliminates the traditional barriers to AI development by providing a zero-setup environment with pre-configured tools, persistent storage, and seamless integration with Google Cloud services. This approach democratizes AI development, making it accessible to developers regardless of their local hardware capabilities or operating system. The browser-based workflow is particularly valuable for teams working across different environments or developers who need to quickly prototype AI solutions without complex local setup.

The integration with Vertex AI showcases Google's commitment to making enterprise-grade AI accessible through simple APIs. By leveraging the modern Gen AI SDK and Gemini models through Vertex AI, developers can build sophisticated AI applications without managing model infrastructure, handling scaling concerns, or maintaining security updates. The intelligent routing system demonstrates how multiple AI models can be orchestrated to provide specialized responses based on content analysis, optimizing both cost and quality. This approach enables applications to automatically select the most appropriate model configuration for different types of queries, improving response relevance while maintaining cost efficiency.

The serverless deployment model using Cloud Run represents the evolution of application hosting, where infrastructure scales automatically based on demand. This approach is particularly valuable for AI applications that may experience unpredictable traffic patterns or require burst capacity for processing intensive requests. The pay-per-use pricing model ensures cost efficiency while maintaining enterprise-grade reliability and security. For comprehensive guidance on Cloud Run best practices, see the [Cloud Run documentation](https://cloud.google.com/run/docs/overview) and [serverless best practices guide](https://cloud.google.com/architecture/serverless-best-practices).

The Cloud Build integration creates a complete CI/CD pipeline that enables rapid iteration from development to production. This automated deployment approach reduces human error, ensures consistency across environments, and enables teams to focus on feature development rather than infrastructure management. The containerized deployment strategy provides portability and consistency while leveraging Google's global infrastructure for optimal performance. The security-focused container configuration follows current best practices including non-root user execution and minimal base images for reduced attack surface.

> **Tip**: Use Cloud Shell Editor's built-in terminal and file management features to experiment with different AI models and configurations. The persistent storage ensures your development work is preserved across sessions, enabling long-term project development directly in the browser without local environment dependencies.

## Challenge

Extend this browser-based AI application development workflow by implementing these enhancements:

1. **Multi-Modal AI Integration**: Add support for image and video processing using Vertex AI's vision models, enabling users to upload and analyze media content through the browser interface. Implement [Document AI](https://cloud.google.com/document-ai/docs) for processing PDF documents and extracting structured data from various document formats.

2. **Real-Time Collaboration Features**: Integrate [Pub/Sub](https://cloud.google.com/pubsub/docs) and WebSocket connections to enable real-time collaborative AI sessions where multiple users can interact with the same AI context. Add session management and conversation threading capabilities with persistent storage.

3. **Advanced AI Orchestration**: Implement [Vertex AI Pipelines](https://cloud.google.com/vertex-ai/docs/pipelines/introduction) to create complex AI workflows that chain multiple models together, such as sentiment analysis followed by content generation based on emotional context, or multi-step reasoning processes.

4. **Production Monitoring and Analytics**: Add comprehensive monitoring using [Cloud Monitoring](https://cloud.google.com/monitoring/docs) and [Cloud Logging](https://cloud.google.com/logging/docs) to track AI model performance, user engagement metrics, and cost optimization opportunities. Implement alerting for service degradation or cost thresholds.

5. **Enterprise Security and Compliance**: Enhance the application with [Identity-Aware Proxy](https://cloud.google.com/iap/docs) for advanced authentication, [Cloud Armor](https://cloud.google.com/armor/docs) for DDoS protection, and data encryption using [Cloud KMS](https://cloud.google.com/kms/docs) for handling sensitive information in AI workflows.

## Infrastructure Code

### Available Infrastructure as Code:

- [Infrastructure Code Overview](code/README.md) - Detailed description of all infrastructure components
- [Infrastructure Manager](code/infrastructure-manager/) - GCP Infrastructure Manager templates
- [Bash CLI Scripts](code/scripts/) - Example bash scripts using gcloud CLI commands to deploy infrastructure
- [Terraform](code/terraform/) - Terraform configuration files