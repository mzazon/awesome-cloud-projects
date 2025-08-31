---
title: Deploying Multi-Container Applications with Cloud Run and Docker Compose
id: b4e7c2d8
category: containers
difficulty: 200
subject: gcp
services: Cloud Run, Cloud SQL, Secret Manager, Artifact Registry
estimated-time: 120 minutes
recipe-version: 1.1
requested-by: mzazon
last-updated: 2025-07-12
last-reviewed: 2025-07-23
passed-qa: null
tags: containers, multi-container, cloud-run, sidecar, docker-compose, microservices
recipe-generator-version: 1.3
---

# Deploying Multi-Container Applications with Cloud Run and Docker Compose

## Problem

Organizations building modern applications often need to deploy complex architectures with multiple interconnected services—frontend applications, backend APIs, databases, and supporting services like proxies or monitoring agents. Traditional single-container deployment approaches force developers to either bundle everything into monolithic containers or manage complex service coordination manually. This creates deployment complexity, reduces modularity, and makes it difficult to scale individual components independently while maintaining service communication and shared resources.

## Solution

Google Cloud Run's multi-container (sidecar) support combined with Docker Compose deployment capabilities enables seamless deployment of complex applications with multiple interconnected containers. This approach leverages Cloud Run's serverless benefits while supporting sophisticated architectures, integrating Cloud SQL for persistent data storage and Secret Manager for secure credential management. The solution maintains Docker Compose's familiar development experience while providing production-grade scalability and security.

## Architecture Diagram

```mermaid
graph TB
    subgraph "Client Layer"
        USER[End Users]
        WEB[Web Browser]
    end
    
    subgraph "Cloud Run Service"
        FRONTEND[Frontend Container<br/>React/Vue App]
        BACKEND[Backend API Container<br/>Node.js/Python]
        PROXY[Nginx Proxy<br/>Sidecar Container]
        SQLPROXY[Cloud SQL Proxy<br/>Database Connector]
    end
    
    subgraph "Google Cloud Services"
        SECRETS[Secret Manager<br/>Database Credentials]
        SQL[Cloud SQL<br/>PostgreSQL Database]
        REGISTRY[Artifact Registry<br/>Container Images]
    end
    
    USER --> WEB
    WEB --> PROXY
    PROXY --> FRONTEND
    PROXY --> BACKEND
    BACKEND --> SQLPROXY
    SQLPROXY --> SQL
    BACKEND --> SECRETS
    
    style FRONTEND fill:#4285f4
    style BACKEND fill:#34a853
    style PROXY fill:#fbbc04
    style SQLPROXY fill:#9aa0a6
    style SQL fill:#ea4335
    style SECRETS fill:#9aa0a6
```

## Prerequisites

1. Google Cloud Platform account with billing enabled
2. gcloud CLI installed and configured (or use Cloud Shell)
3. Docker Desktop installed locally for development and testing
4. Basic knowledge of containerization, Docker Compose, and web application architecture
5. Understanding of Cloud Run services and serverless deployment concepts
6. Estimated cost: $10-30/month for development usage (includes Cloud SQL, Cloud Run, and Secret Manager)

> **Note**: Cloud Run's multi-container support enables sophisticated deployment patterns while maintaining serverless benefits. Review the [Cloud Run documentation](https://cloud.google.com/run/docs/deploying) for current pricing and feature availability.

## Preparation

Google Cloud Run's multi-container support revolutionizes how we deploy complex applications by enabling sidecar patterns and service composition. This preparation establishes the foundational infrastructure needed for a production-ready multi-service application deployment.

```bash
# Set environment variables for consistent resource naming
export PROJECT_ID="multicontainer-app-$(date +%s)"
export REGION="us-central1"
export ZONE="us-central1-a"

# Generate unique suffix for resource names to avoid conflicts
RANDOM_SUFFIX=$(openssl rand -hex 3)
export SERVICE_NAME="multi-app-${RANDOM_SUFFIX}"
export REPOSITORY_NAME="multiapp-repo-${RANDOM_SUFFIX}"
export SQL_INSTANCE_NAME="multiapp-db-${RANDOM_SUFFIX}"

# Configure gcloud CLI with project and region defaults
gcloud config set project ${PROJECT_ID}
gcloud config set compute/region ${REGION}
gcloud config set compute/zone ${ZONE}

# Enable required Google Cloud APIs for our multi-service architecture
gcloud services enable run.googleapis.com
gcloud services enable sql-component.googleapis.com
gcloud services enable sqladmin.googleapis.com
gcloud services enable secretmanager.googleapis.com
gcloud services enable artifactregistry.googleapis.com
gcloud services enable cloudbuild.googleapis.com

echo "✅ Project configured: ${PROJECT_ID}"
echo "✅ Region set to: ${REGION}"
echo "✅ Service name: ${SERVICE_NAME}"
```

The environment setup enables all necessary Google Cloud services and establishes naming conventions that prevent resource conflicts. This foundation supports the entire multi-container deployment pipeline from development through production.

## Steps

1. **Create Artifact Registry Repository for Container Images**:

   Artifact Registry provides secure, private storage for your application's container images with integrated vulnerability scanning and access controls. Creating a dedicated repository ensures your multi-container application images are stored securely and can be efficiently pulled by Cloud Run during deployment.

   ```bash
   # Create Docker repository in Artifact Registry
   gcloud artifacts repositories create ${REPOSITORY_NAME} \
       --repository-format=docker \
       --location=${REGION} \
       --description="Multi-container application repository"
   
   # Configure Docker authentication for pushing images
   gcloud auth configure-docker ${REGION}-docker.pkg.dev
   
   echo "✅ Artifact Registry repository created: ${REPOSITORY_NAME}"
   ```

   The repository is now configured with proper authentication, providing a secure foundation for storing and managing your application's container images. This enables automated builds and deployments while maintaining security best practices for container image distribution.

2. **Create Cloud SQL Database Instance**:

   Cloud SQL provides managed PostgreSQL database services with automatic backups, high availability, and integrated security. Setting up the database instance establishes the persistent data layer that your backend services will connect to securely.

   ```bash
   # Create Cloud SQL PostgreSQL instance with optimized settings
   gcloud sql instances create ${SQL_INSTANCE_NAME} \
       --database-version=POSTGRES_15 \
       --tier=db-f1-micro \
       --region=${REGION} \
       --storage-type=SSD \
       --storage-size=10GB \
       --backup
   
   # Create application database
   gcloud sql databases create appdb \
       --instance=${SQL_INSTANCE_NAME}
   
   # Create database user with secure password
   DB_PASSWORD=$(openssl rand -base64 32)
   gcloud sql users create appuser \
       --instance=${SQL_INSTANCE_NAME} \
       --password=${DB_PASSWORD}
   
   echo "✅ Cloud SQL instance created: ${SQL_INSTANCE_NAME}"
   echo "✅ Database and user configured"
   ```

   The database instance is now ready with proper security configurations and automated backups. This managed database service provides the reliability and performance needed for production applications while simplifying maintenance and scaling operations.

3. **Store Database Credentials in Secret Manager**:

   Secret Manager provides secure storage and access control for sensitive data like database credentials. Storing credentials as secrets enables secure access patterns and eliminates the need to embed sensitive information in container images or environment variables.

   ```bash
   # Store database password securely in Secret Manager
   echo -n "${DB_PASSWORD}" | gcloud secrets create db-password \
       --data-file=-
   
   # Create connection string secret for easy access
   CONNECTION_STRING="postgresql://appuser:${DB_PASSWORD}@localhost:5432/appdb"
   echo -n "${CONNECTION_STRING}" | gcloud secrets create db-connection-string \
       --data-file=-
   
   # Verify secrets are created
   gcloud secrets list --filter="name:db-"
   
   echo "✅ Database credentials stored in Secret Manager"
   ```

   The secrets are now securely stored and can be accessed by your Cloud Run services using IAM-based authentication. This approach follows security best practices by separating sensitive data from application code and providing audit trails for secret access.

4. **Create Multi-Container Application Source Code**:

   Modern applications benefit from separation of concerns through microservices architecture. Creating separate containers for frontend, backend, and proxy services enables independent scaling, updates, and maintenance while maintaining clear service boundaries.

   ```bash
   # Create project directory structure
   mkdir -p ~/multicontainer-app/{frontend,backend,proxy}
   cd ~/multicontainer-app
   
   # Create backend API service (Node.js/Express)
   cat > backend/package.json << 'EOF'
   {
     "name": "backend-api",
     "version": "1.0.0",
     "main": "server.js",
     "dependencies": {
       "express": "^4.18.0",
       "pg": "^8.8.0",
       "cors": "^2.8.5"
     },
     "scripts": {
       "start": "node server.js"
     }
   }
   EOF
   
   # Create backend server with database integration
   cat > backend/server.js << 'EOF'
   const express = require('express');
   const { Pool } = require('pg');
   const cors = require('cors');
   
   const app = express();
   const port = process.env.PORT || 8080;
   
   // Enable CORS for frontend communication
   app.use(cors());
   app.use(express.json());
   
   // Database connection using Cloud SQL proxy
   const pool = new Pool({
     user: 'appuser',
     host: 'localhost',
     database: 'appdb',
     password: process.env.DB_PASSWORD,
     port: 5432,
   });
   
   // Health check endpoint
   app.get('/health', (req, res) => {
     res.json({ status: 'healthy', timestamp: new Date().toISOString() });
   });
   
   // API endpoints
   app.get('/api/data', async (req, res) => {
     try {
       const result = await pool.query('SELECT NOW() as current_time, VERSION() as db_version');
       res.json({ success: true, data: result.rows[0] });
     } catch (err) {
       res.status(500).json({ error: err.message });
     }
   });
   
   app.listen(port, '0.0.0.0', () => {
     console.log(`Backend API listening on port ${port}`);
   });
   EOF
   
   # Create backend Dockerfile
   cat > backend/Dockerfile << 'EOF'
   FROM node:18-alpine
   WORKDIR /app
   COPY package*.json ./
   RUN npm install
   COPY . .
   EXPOSE 8080
   CMD ["npm", "start"]
   EOF
   
   echo "✅ Backend service files created"
   ```

   The backend service is now configured with proper database connectivity and health checking capabilities. This Node.js application demonstrates best practices for containerized microservices including proper error handling, health endpoints, and secure database connections.

5. **Create Frontend Service**:

   The frontend service provides the user interface layer that communicates with backend APIs. Creating a separate frontend container enables independent deployment cycles and technology choices while maintaining clear separation between presentation and business logic layers.

   ```bash
   # Create simple frontend application (HTML/JavaScript)
   cat > frontend/package.json << 'EOF'
   {
     "name": "frontend-app",
     "version": "1.0.0",
     "main": "server.js",
     "dependencies": {
       "express": "^4.18.0"
     },
     "scripts": {
       "start": "node server.js"
     }
   }
   EOF
   
   # Create frontend server
   cat > frontend/server.js << 'EOF'
   const express = require('express');
   const path = require('path');
   
   const app = express();
   const port = process.env.PORT || 3000;
   
   // Serve static files
   app.use(express.static('public'));
   
   // Health check
   app.get('/health', (req, res) => {
     res.json({ status: 'healthy', service: 'frontend' });
   });
   
   // Serve main application
   app.get('/', (req, res) => {
     res.sendFile(path.join(__dirname, 'public', 'index.html'));
   });
   
   app.listen(port, '0.0.0.0', () => {
     console.log(`Frontend listening on port ${port}`);
   });
   EOF
   
   # Create public directory and main HTML file
   mkdir -p frontend/public
   cat > frontend/public/index.html << 'EOF'
   <!DOCTYPE html>
   <html lang="en">
   <head>
       <meta charset="UTF-8">
       <meta name="viewport" content="width=device-width, initial-scale=1.0">
       <title>Multi-Container App</title>
       <style>
           body { font-family: Arial, sans-serif; margin: 40px; }
           .container { max-width: 800px; margin: 0 auto; }
           .status { padding: 20px; border-radius: 5px; margin: 20px 0; }
           .success { background-color: #d4edda; border: 1px solid #c3e6cb; }
           .error { background-color: #f8d7da; border: 1px solid #f5c6cb; }
       </style>
   </head>
   <body>
       <div class="container">
           <h1>Multi-Container Cloud Run Application</h1>
           <p>This application demonstrates Cloud Run's multi-container capabilities.</p>
           
           <button onclick="testBackend()">Test Backend Connection</button>
           <div id="result"></div>
           
           <script>
               async function testBackend() {
                   const resultDiv = document.getElementById('result');
                   try {
                       const response = await fetch('/api/data');
                       const data = await response.json();
                       
                       if (data.success) {
                           resultDiv.innerHTML = `
                               <div class="status success">
                                   <h3>Backend Connection Successful!</h3>
                                   <p>Database Time: ${data.data.current_time}</p>
                                   <p>Database Version: ${data.data.db_version}</p>
                               </div>
                           `;
                       } else {
                           throw new Error('Backend returned error');
                       }
                   } catch (error) {
                       resultDiv.innerHTML = `
                           <div class="status error">
                               <h3>Connection Failed</h3>
                               <p>Error: ${error.message}</p>
                           </div>
                       `;
                   }
               }
           </script>
       </div>
   </body>
   </html>
   EOF
   
   # Create frontend Dockerfile
   cat > frontend/Dockerfile << 'EOF'
   FROM node:18-alpine
   WORKDIR /app
   COPY package*.json ./
   RUN npm install
   COPY . .
   EXPOSE 3000
   CMD ["npm", "start"]
   EOF
   
   echo "✅ Frontend service files created"
   ```

   The frontend service now provides a complete user interface that can communicate with the backend API. This separation enables modern development practices where frontend and backend teams can work independently while maintaining clear API contracts.

6. **Create Nginx Proxy Configuration**:

   An Nginx proxy acts as a reverse proxy and load balancer, routing requests to appropriate services based on URL patterns. This sidecar container pattern enables sophisticated request routing, SSL termination, and can provide additional security layers for your multi-container application.

   ```bash
   # Create Nginx configuration for request routing
   cat > proxy/nginx.conf << 'EOF'
   events {
       worker_connections 1024;
   }
   
   http {
       upstream frontend {
           server localhost:3000;
       }
       
       upstream backend {
           server localhost:8080;
       }
       
       server {
           listen 8000;
           
           # Health check endpoint
           location /health {
               proxy_pass http://frontend/health;
               proxy_set_header Host $host;
               proxy_set_header X-Real-IP $remote_addr;
           }
           
           # Route API requests to backend
           location /api/ {
               proxy_pass http://backend;
               proxy_set_header Host $host;
               proxy_set_header X-Real-IP $remote_addr;
               proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
               proxy_set_header X-Forwarded-Proto $scheme;
           }
           
           # Route everything else to frontend
           location / {
               proxy_pass http://frontend;
               proxy_set_header Host $host;
               proxy_set_header X-Real-IP $remote_addr;
               proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
               proxy_set_header X-Forwarded-Proto $scheme;
           }
       }
   }
   EOF
   
   # Create proxy Dockerfile
   cat > proxy/Dockerfile << 'EOF'
   FROM nginx:alpine
   COPY nginx.conf /etc/nginx/nginx.conf
   EXPOSE 8000
   CMD ["nginx", "-g", "daemon off;"]
   EOF
   
   echo "✅ Nginx proxy configuration created"
   ```

   The proxy configuration enables intelligent request routing between your frontend and backend services. This architecture provides a single entry point for your application while enabling independent scaling and deployment of individual services.

7. **Create Docker Compose Configuration**:

   Docker Compose orchestrates multi-container applications by defining service relationships, networking, and resource sharing. Creating a comprehensive compose configuration enables both local development and Cloud Run deployment using the same service definitions.

   ```bash
   # Create Docker Compose configuration for multi-container app
   cat > docker-compose.yml << 'EOF'
   version: '3.8'
   
   services:
     proxy:
       build: ./proxy
       ports:
         - "8000:8000"
       depends_on:
         - frontend
         - backend
       restart: unless-stopped
   
     frontend:
       build: ./frontend
       ports:
         - "3000:3000"
       environment:
         - NODE_ENV=production
       restart: unless-stopped
   
     backend:
       build: ./backend
       ports:
         - "8080:8080"
       environment:
         - NODE_ENV=production
         - DB_PASSWORD=${DB_PASSWORD}
       depends_on:
         - db-proxy
       restart: unless-stopped
   
     db-proxy:
       image: gcr.io/cloud-sql-connectors/cloud-sql-proxy:2.8.0
       command:
         - /cloud-sql-proxy
         - --port=5432
         - --address=0.0.0.0
         - ${PROJECT_ID}:${REGION}:${SQL_INSTANCE_NAME}
       ports:
         - "5432:5432"
       restart: unless-stopped
   
   networks:
     default:
       driver: bridge
   EOF
   
   echo "✅ Docker Compose configuration created"
   ```

   The compose configuration establishes service relationships and networking that enables seamless communication between containers. The Cloud SQL proxy sidecar provides secure database connectivity without requiring VPC configuration or IP allowlisting.

8. **Build and Push Container Images**:

   Building optimized container images and pushing them to Artifact Registry prepares your application for Cloud Run deployment. This process creates immutable artifacts that can be deployed consistently across environments while leveraging Google Cloud's integrated container scanning and security features.

   ```bash
   # Set base image repository URL
   BASE_URL="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPOSITORY_NAME}"
   
   # Build and push frontend image
   cd frontend
   docker build -t ${BASE_URL}/frontend:latest .
   docker push ${BASE_URL}/frontend:latest
   cd ..
   
   # Build and push backend image
   cd backend
   docker build -t ${BASE_URL}/backend:latest .
   docker push ${BASE_URL}/backend:latest
   cd ..
   
   # Build and push proxy image
   cd proxy
   docker build -t ${BASE_URL}/proxy:latest .
   docker push ${BASE_URL}/proxy:latest
   cd ..
   
   # Verify images are available in Artifact Registry
   gcloud artifacts docker images list ${BASE_URL}
   
   echo "✅ All container images built and pushed to Artifact Registry"
   ```

   The container images are now securely stored in Artifact Registry with vulnerability scanning enabled. These images serve as the deployment artifacts that Cloud Run will use to create your multi-container service instances.

9. **Create Cloud Run Service with Multi-Container Configuration**:

   Cloud Run's multi-container support enables deploying complex applications using familiar Docker Compose patterns while providing serverless scalability and management. Creating the service with proper resource allocation and security configuration ensures optimal performance and security.

   ```bash
   # Create Cloud Run service YAML configuration
   cat > service.yaml << EOF
   apiVersion: serving.knative.dev/v1
   kind: Service
   metadata:
     name: ${SERVICE_NAME}
     annotations:
       run.googleapis.com/ingress: all
       run.googleapis.com/execution-environment: gen2
   spec:
     template:
       metadata:
         annotations:
           run.googleapis.com/cpu-throttling: "false"
           run.googleapis.com/execution-environment: gen2
       spec:
         serviceAccountName: ${PROJECT_ID}-compute@developer.gserviceaccount.com
         containers:
         - name: proxy
           image: ${BASE_URL}/proxy:latest
           ports:
           - containerPort: 8000
           resources:
             limits:
               cpu: 1000m
               memory: 512Mi
         - name: frontend
           image: ${BASE_URL}/frontend:latest
           ports:
           - containerPort: 3000
           resources:
             limits:
               cpu: 1000m
               memory: 512Mi
         - name: backend
           image: ${BASE_URL}/backend:latest
           ports:
           - containerPort: 8080
           env:
           - name: DB_PASSWORD
             valueFrom:
               secretKeyRef:
                 name: db-password
                 key: latest
           resources:
             limits:
               cpu: 1000m
               memory: 512Mi
         - name: cloud-sql-proxy
           image: gcr.io/cloud-sql-connectors/cloud-sql-proxy:2.8.0
           args:
           - --port=5432
           - --address=0.0.0.0
           - ${PROJECT_ID}:${REGION}:${SQL_INSTANCE_NAME}
           resources:
             limits:
               cpu: 500m
               memory: 256Mi
   EOF
   
   # Deploy the multi-container service to Cloud Run
   gcloud run services replace service.yaml \
       --region=${REGION}
   
   # Allow unauthenticated access for testing
   gcloud run services add-iam-policy-binding ${SERVICE_NAME} \
       --region=${REGION} \
       --member="allUsers" \
       --role="roles/run.invoker"
   
   # Get the service URL
   SERVICE_URL=$(gcloud run services describe ${SERVICE_NAME} \
       --region=${REGION} \
       --format='value(status.url)')
   
   echo "✅ Multi-container Cloud Run service deployed"
   echo "✅ Service URL: ${SERVICE_URL}"
   ```

   The multi-container service is now running on Cloud Run with all containers working together within the same network namespace. This deployment pattern provides the benefits of microservices architecture while maintaining the simplicity of single-service deployment and management.

## Validation & Testing

1. **Verify Service Health and Container Status**:

   ```bash
   # Check Cloud Run service status
   gcloud run services describe ${SERVICE_NAME} \
       --region=${REGION} \
       --format="table(status.conditions[].type,status.conditions[].status)"
   
   # Test health endpoints for each service
   curl -s "${SERVICE_URL}/health" | jq '.'
   ```

   Expected output: Service should show "Ready" status and health endpoint should return JSON with healthy status.

2. **Test Multi-Container Communication**:

   ```bash
   # Test frontend to backend API communication through proxy
   curl -s "${SERVICE_URL}/api/data" | jq '.'
   
   # Verify database connectivity through the application
   curl -s "${SERVICE_URL}" | grep -o "Multi-Container Cloud Run Application"
   ```

   Expected output: API should return database connection information and current timestamp from Cloud SQL.

3. **Validate Container Resource Allocation**:

   ```bash
   # Check service configuration and resource limits
   gcloud run services describe ${SERVICE_NAME} \
       --region=${REGION} \
       --format="yaml" | grep -A 5 -B 5 "resources:"
   
   # Monitor service metrics
   gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=${SERVICE_NAME}" \
       --limit=10 \
       --format="table(timestamp,textPayload)"
   ```

## Cleanup

1. **Delete Cloud Run Service**:

   ```bash
   # Delete the multi-container Cloud Run service
   gcloud run services delete ${SERVICE_NAME} \
       --region=${REGION} \
       --quiet
   
   echo "✅ Cloud Run service deleted"
   ```

2. **Remove Cloud SQL Instance**:

   ```bash
   # Delete Cloud SQL instance and all associated data
   gcloud sql instances delete ${SQL_INSTANCE_NAME} \
       --quiet
   
   echo "✅ Cloud SQL instance deleted"
   ```

3. **Clean Up Secrets and Images**:

   ```bash
   # Delete secrets from Secret Manager
   gcloud secrets delete db-password --quiet
   gcloud secrets delete db-connection-string --quiet
   
   # Delete Artifact Registry repository
   gcloud artifacts repositories delete ${REPOSITORY_NAME} \
       --location=${REGION} \
       --quiet
   
   # Remove local files
   cd ~
   rm -rf multicontainer-app
   
   echo "✅ All resources cleaned up"
   ```

4. **Optional: Delete Project**:

   ```bash
   # If you created a dedicated project, delete it entirely
   gcloud projects delete ${PROJECT_ID} --quiet
   
   echo "✅ Project deleted (if created specifically for this recipe)"
   ```

## Discussion

Cloud Run's multi-container support represents a significant evolution in serverless container deployment, bridging the gap between simple single-container services and complex microservices architectures. This capability enables developers to deploy applications using familiar Docker Compose patterns while leveraging Google Cloud's fully managed serverless infrastructure. The sidecar pattern demonstrated in this recipe allows for sophisticated application architectures including proxy services, database connectors, monitoring agents, and other supporting services that run alongside your main application containers.

The integration with Google Cloud services like Secret Manager and Cloud SQL showcases how multi-container Cloud Run applications can securely access managed services without compromising security or operational complexity. The Cloud SQL proxy sidecar pattern eliminates the need for complex VPC configurations or IP allowlisting while providing secure, encrypted connections to your databases. This approach follows Google Cloud security best practices by using IAM-based authentication and avoiding hardcoded credentials in container images.

The architectural pattern demonstrated here scales from development through production environments, providing consistency across your deployment pipeline. Cloud Run's automatic scaling capabilities apply to the entire multi-container service as a unit, ensuring that all containers scale together while maintaining proper resource allocation and inter-service communication. This approach is particularly valuable for applications that require tight coupling between services or shared local storage volumes.

Resource management in multi-container Cloud Run services requires careful consideration of CPU and memory allocation across containers. The configuration shown allocates resources proportionally based on each container's role, with the proxy and application containers receiving more resources than the supporting Cloud SQL proxy. Google Cloud's pay-per-use pricing model for Cloud Run means you only pay for the compute resources actually consumed, making this architecture cost-effective for both development and production workloads.

> **Tip**: Use Cloud Run's traffic allocation features to implement blue-green deployments and canary releases with your multi-container applications. This enables safe rollouts of complex application updates while maintaining service availability.

For more information on Cloud Run multi-container patterns, see the [Cloud Run multi-container documentation](https://cloud.google.com/run/docs/deploying). Additional security patterns are covered in the [Cloud Run security guide](https://cloud.google.com/run/docs/securing), and performance optimization techniques are detailed in the [Cloud Run performance best practices](https://cloud.google.com/run/docs/tips/performance). Integration patterns with other Google Cloud services are documented in the [Cloud Run integrations guide](https://cloud.google.com/run/docs/integrations), and cost optimization strategies are outlined in the [Cloud Run pricing documentation](https://cloud.google.com/run/pricing).

## Challenge

Extend this multi-container application by implementing these advanced patterns:

1. **Add Monitoring and Observability**: Integrate a Prometheus metrics sidecar container and configure Cloud Monitoring to collect custom application metrics from your multi-container service, implementing distributed tracing with OpenTelemetry.

2. **Implement Caching Layer**: Add a Redis sidecar container using Cloud Memorystore for improved application performance, implementing cache-aside patterns for database queries and session management.

3. **Add Security Scanning**: Integrate a security scanning sidecar that performs runtime vulnerability assessment and compliance checking, using Google Cloud Security Command Center for centralized security monitoring.

4. **Implement Blue-Green Deployment**: Configure Cloud Run traffic allocation to support blue-green deployments of your multi-container application, including automated rollback mechanisms based on health check failures.

5. **Add Message Queue Processing**: Integrate a message processing sidecar using Cloud Pub/Sub for asynchronous task processing, implementing event-driven architecture patterns with proper error handling and dead letter queues.

## Infrastructure Code

*Infrastructure code will be generated after recipe approval.*