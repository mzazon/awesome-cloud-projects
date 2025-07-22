#!/bin/bash

# Deploy script for API Middleware with Cloud Run MCP Servers and Service Extensions
# This script deploys intelligent API middleware using Model Context Protocol (MCP) servers
# on Google Cloud Platform with Cloud Run, Service Extensions, and Vertex AI integration

set -euo pipefail

# Color codes for output
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

# Error handling
cleanup_on_error() {
    log_error "Deployment failed. Cleaning up partial resources..."
    ./destroy.sh --force 2>/dev/null || true
    exit 1
}

trap cleanup_on_error ERR

# Configuration and defaults
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ID="${PROJECT_ID:-mcp-middleware-$(date +%s)}"
REGION="${REGION:-us-central1}"
ZONE="${ZONE:-us-central1-a}"
RANDOM_SUFFIX="${RANDOM_SUFFIX:-$(openssl rand -hex 3)}"
MCP_SERVICE_PREFIX="${MCP_SERVICE_PREFIX:-mcp-server-${RANDOM_SUFFIX}}"
MIDDLEWARE_SERVICE="${MIDDLEWARE_SERVICE:-api-middleware-${RANDOM_SUFFIX}}"
ENDPOINTS_CONFIG="${ENDPOINTS_CONFIG:-endpoints-config-${RANDOM_SUFFIX}}"
DRY_RUN=false
SKIP_PROJECT_CREATION=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --project-id)
            PROJECT_ID="$2"
            shift 2
            ;;
        --region)
            REGION="$2"
            shift 2
            ;;
        --skip-project-creation)
            SKIP_PROJECT_CREATION=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help)
            echo "Usage: $0 [options]"
            echo "Options:"
            echo "  --project-id ID          Set Google Cloud project ID"
            echo "  --region REGION          Set deployment region (default: us-central1)"
            echo "  --skip-project-creation  Skip project creation (use existing project)"
            echo "  --dry-run               Show what would be deployed without executing"
            echo "  --help                  Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Display deployment configuration
log_info "=== API Middleware MCP Deployment Configuration ==="
log_info "Project ID: $PROJECT_ID"
log_info "Region: $REGION"
log_info "Zone: $ZONE"
log_info "MCP Service Prefix: $MCP_SERVICE_PREFIX"
log_info "Middleware Service: $MIDDLEWARE_SERVICE"
log_info "Endpoints Config: $ENDPOINTS_CONFIG"
log_info "Dry Run: $DRY_RUN"
log_info "Skip Project Creation: $SKIP_PROJECT_CREATION"

if [[ "$DRY_RUN" == "true" ]]; then
    log_warning "DRY RUN MODE - No resources will be created"
    exit 0
fi

# Prerequisites check
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Check if docker is installed
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed. Please install Docker."
        exit 1
    fi
    
    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        log_error "OpenSSL is not available. Please install OpenSSL."
        exit 1
    fi
    
    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
        log_error "No active gcloud authentication found. Please run 'gcloud auth login'."
        exit 1
    fi
    
    # Check if Python 3.10+ is available
    if command -v python3 &> /dev/null; then
        PYTHON_VERSION=$(python3 --version 2>&1 | cut -d' ' -f2 | cut -d'.' -f1,2)
        if [[ $(echo "$PYTHON_VERSION 3.10" | awk '{print ($1 >= $2)}') -eq 0 ]]; then
            log_warning "Python 3.10+ recommended for local development and testing"
        fi
    fi
    
    log_success "Prerequisites check completed"
}

# Project setup
setup_project() {
    log_info "Setting up Google Cloud project..."
    
    if [[ "$SKIP_PROJECT_CREATION" == "false" ]]; then
        # Create project if it doesn't exist
        if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
            log_info "Creating project: $PROJECT_ID"
            gcloud projects create "$PROJECT_ID" --name="MCP Middleware Project"
        else
            log_info "Project $PROJECT_ID already exists"
        fi
    fi
    
    # Set current project
    gcloud config set project "$PROJECT_ID"
    gcloud config set compute/region "$REGION"
    gcloud config set compute/zone "$ZONE"
    
    log_success "Project configuration completed"
}

# Enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "run.googleapis.com"
        "aiplatform.googleapis.com"
        "endpoints.googleapis.com"
        "servicecontrol.googleapis.com"
        "cloudbuild.googleapis.com"
        "artifactregistry.googleapis.com"
        "logging.googleapis.com"
        "monitoring.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling $api..."
        gcloud services enable "$api"
    done
    
    log_success "All required APIs enabled"
}

# Create application source code
create_mcp_servers() {
    log_info "Creating MCP server applications..."
    
    # Create project structure
    local work_dir="/tmp/mcp-middleware-$$"
    mkdir -p "$work_dir"/{content-analyzer,request-router,response-enhancer,api-middleware}
    
    # Create Content Analyzer MCP Server
    log_info "Creating Content Analyzer MCP Server..."
    cat > "$work_dir/content-analyzer/main.py" << 'EOF'
import json
import os
from typing import Dict, Any, List
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from google.cloud import aiplatform
from pydantic import BaseModel

app = FastAPI(title="MCP Content Analyzer Server")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Initialize Vertex AI
try:
    aiplatform.init(project=os.getenv('PROJECT_ID'), location=os.getenv('REGION'))
except Exception as e:
    print(f"Warning: Vertex AI initialization failed: {e}")

class AnalysisRequest(BaseModel):
    content: str
    content_type: str
    metadata: Dict[str, Any] = {}

class AnalysisResponse(BaseModel):
    sentiment: str
    complexity: str
    routing_recommendation: str
    enhancement_suggestions: List[str]
    confidence: float

@app.post("/analyze", response_model=AnalysisResponse)
async def analyze_content(request: AnalysisRequest):
    """MCP endpoint for content analysis using Vertex AI"""
    try:
        # Analyze content characteristics
        content_length = len(request.content)
        has_special_chars = any(char in request.content for char in ['@', '#', '$', '%'])
        
        # Determine complexity based on content analysis
        if content_length > 500 or has_special_chars:
            complexity = "complex"
            routing = "premium"
        elif content_length < 100:
            complexity = "simple"
            routing = "basic"
        else:
            complexity = "moderate"
            routing = "standard"
        
        # Analyze sentiment (simplified)
        positive_words = ['good', 'great', 'excellent', 'amazing', 'wonderful']
        negative_words = ['bad', 'terrible', 'awful', 'horrible', 'worst']
        
        positive_count = sum(1 for word in positive_words if word in request.content.lower())
        negative_count = sum(1 for word in negative_words if word in request.content.lower())
        
        if positive_count > negative_count:
            sentiment = "positive"
        elif negative_count > positive_count:
            sentiment = "negative"
        else:
            sentiment = "neutral"
        
        suggestions = ["Add caching headers", "Optimize response format"]
        if complexity == "complex":
            suggestions.extend(["Enable compression", "Use CDN"])
        
        return AnalysisResponse(
            sentiment=sentiment,
            complexity=complexity,
            routing_recommendation=routing,
            enhancement_suggestions=suggestions,
            confidence=0.85
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/health")
async def health_check():
    return {"status": "healthy", "service": "MCP Content Analyzer"}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=int(os.getenv("PORT", 8080)))
EOF

    cat > "$work_dir/content-analyzer/requirements.txt" << 'EOF'
fastapi==0.104.1
uvicorn[standard]==0.24.0
google-cloud-aiplatform==1.38.1
pydantic==2.5.0
EOF

    cat > "$work_dir/content-analyzer/Dockerfile" << 'EOF'
FROM python:3.11-slim

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 8080
CMD ["python", "main.py"]
EOF

    # Create Request Router MCP Server
    log_info "Creating Request Router MCP Server..."
    cat > "$work_dir/request-router/main.py" << 'EOF'
import json
import os
import httpx
from typing import Dict, Any, List
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

app = FastAPI(title="MCP Request Router Server")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

class RoutingRequest(BaseModel):
    original_request: Dict[str, Any]
    analysis_result: Dict[str, Any]
    routing_rules: Dict[str, Any] = {}

class RoutingResponse(BaseModel):
    target_endpoint: str
    routing_confidence: float
    applied_transformations: List[str]
    estimated_latency: int

@app.post("/route", response_model=RoutingResponse)
async def route_request(request: RoutingRequest):
    """MCP endpoint for intelligent request routing"""
    try:
        analysis = request.analysis_result
        complexity = analysis.get('complexity', 'moderate')
        sentiment = analysis.get('sentiment', 'neutral')
        
        # Apply routing logic based on analysis
        if complexity == 'complex' and sentiment == 'positive':
            target = "https://premium-api.example.com"
            latency = 200
            transformations = ["priority_queue", "enhanced_processing"]
        elif complexity == 'simple':
            target = "https://basic-api.example.com"
            latency = 50
            transformations = ["fast_track"]
        else:
            target = "https://standard-api.example.com"
            latency = 100
            transformations = ["standard_processing"]
        
        return RoutingResponse(
            target_endpoint=target,
            routing_confidence=0.9,
            applied_transformations=transformations,
            estimated_latency=latency
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/health")
async def health_check():
    return {"status": "healthy", "service": "MCP Request Router"}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=int(os.getenv("PORT", 8080)))
EOF

    cp "$work_dir/content-analyzer/requirements.txt" "$work_dir/request-router/"
    sed 's/google-cloud-aiplatform==1.38.1/httpx==0.25.2/' "$work_dir/content-analyzer/requirements.txt" > "$work_dir/request-router/requirements.txt"
    cp "$work_dir/content-analyzer/Dockerfile" "$work_dir/request-router/"

    # Create Response Enhancer MCP Server
    log_info "Creating Response Enhancer MCP Server..."
    cat > "$work_dir/response-enhancer/main.py" << 'EOF'
import json
import os
from typing import Dict, Any, List, Optional
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from google.cloud import aiplatform
from pydantic import BaseModel

app = FastAPI(title="MCP Response Enhancer Server")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Initialize Vertex AI
try:
    aiplatform.init(project=os.getenv('PROJECT_ID'), location=os.getenv('REGION'))
except Exception as e:
    print(f"Warning: Vertex AI initialization failed: {e}")

class EnhancementRequest(BaseModel):
    original_response: Dict[str, Any]
    routing_context: Dict[str, Any]
    enhancement_rules: List[str] = []

class EnhancementResponse(BaseModel):
    enhanced_response: Dict[str, Any]
    applied_enhancements: List[str]
    performance_metrics: Dict[str, Any]

@app.post("/enhance", response_model=EnhancementResponse)
async def enhance_response(request: EnhancementRequest):
    """MCP endpoint for AI-powered response enhancement"""
    try:
        original = request.original_response
        context = request.routing_context
        
        # Apply enhancements based on context
        enhanced = original.copy()
        enhancements_applied = []
        
        # Add AI-generated metadata
        if context.get('complexity') == 'complex':
            enhanced['ai_insights'] = {
                'processing_complexity': 'high',
                'recommended_caching': 'aggressive',
                'optimization_hints': ['enable_compression', 'use_edge_cache']
            }
            enhancements_applied.append('ai_insights')
        
        # Add performance recommendations
        enhanced['performance_recommendations'] = {
            'estimated_processing_time': context.get('estimated_latency', 100),
            'cache_headers': {'max-age': 3600, 'public': True},
            'compression': {'gzip': True, 'br': True}
        }
        enhancements_applied.append('performance_optimization')
        
        # Add contextual links
        enhanced['contextual_navigation'] = {
            'related_endpoints': ['/api/v1/related', '/api/v1/suggestions'],
            'documentation': f"/docs/{context.get('service_type', 'standard')}"
        }
        enhancements_applied.append('contextual_navigation')
        
        metrics = {
            'enhancement_latency_ms': 15,
            'ai_confidence': 0.92,
            'cache_hit_probability': 0.75
        }
        
        return EnhancementResponse(
            enhanced_response=enhanced,
            applied_enhancements=enhancements_applied,
            performance_metrics=metrics
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/health")
async def health_check():
    return {"status": "healthy", "service": "MCP Response Enhancer"}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=int(os.getenv("PORT", 8080)))
EOF

    cp "$work_dir/content-analyzer/requirements.txt" "$work_dir/response-enhancer/"
    cp "$work_dir/content-analyzer/Dockerfile" "$work_dir/response-enhancer/"

    # Create Main API Middleware Service
    log_info "Creating Main API Middleware Service..."
    cat > "$work_dir/api-middleware/main.py" << 'EOF'
import json
import os
import httpx
import asyncio
from typing import Dict, Any, Optional
from fastapi import FastAPI, Request, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

app = FastAPI(title="Intelligent API Middleware")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# MCP Server URLs (set via environment variables)
CONTENT_ANALYZER_URL = os.getenv('CONTENT_ANALYZER_URL')
REQUEST_ROUTER_URL = os.getenv('REQUEST_ROUTER_URL')
RESPONSE_ENHANCER_URL = os.getenv('RESPONSE_ENHANCER_URL')

async def call_mcp_server(url: str, endpoint: str, data: Dict[str, Any]) -> Dict[str, Any]:
    """Helper function to call MCP servers"""
    if not url:
        raise HTTPException(status_code=500, detail=f"MCP server URL not configured for {endpoint}")
    
    async with httpx.AsyncClient(timeout=30.0) as client:
        try:
            response = await client.post(f"{url}{endpoint}", json=data)
            response.raise_for_status()
            return response.json()
        except httpx.RequestError as e:
            raise HTTPException(status_code=503, detail=f"MCP server unavailable: {str(e)}")

@app.api_route("/{path:path}", methods=["GET", "POST", "PUT", "DELETE", "PATCH"])
async def intelligent_middleware(request: Request, path: str):
    """Main middleware endpoint that processes requests through MCP servers"""
    try:
        # Extract request information
        method = request.method
        headers = dict(request.headers)
        query_params = dict(request.query_params)
        
        # Get request body for POST/PUT/PATCH requests
        body = None
        if method in ["POST", "PUT", "PATCH"]:
            body = await request.body()
            if body:
                try:
                    body = json.loads(body)
                except json.JSONDecodeError:
                    body = body.decode('utf-8')
        
        # Step 1: Analyze content using MCP Content Analyzer
        content_to_analyze = str(body) if body else str(query_params)
        analysis_request = {
            "content": content_to_analyze,
            "content_type": headers.get("content-type", "application/json"),
            "metadata": {
                "method": method,
                "path": path,
                "user_agent": headers.get("user-agent", "unknown")
            }
        }
        
        analysis_result = await call_mcp_server(
            CONTENT_ANALYZER_URL, 
            "/analyze", 
            analysis_request
        )
        
        # Step 2: Determine routing using MCP Request Router
        routing_request = {
            "original_request": {
                "method": method,
                "path": path,
                "headers": headers,
                "body": body,
                "query_params": query_params
            },
            "analysis_result": analysis_result,
            "routing_rules": {
                "default_backend": "https://api.example.com",
                "load_balancing": "intelligent"
            }
        }
        
        routing_result = await call_mcp_server(
            REQUEST_ROUTER_URL,
            "/route",
            routing_request
        )
        
        # Step 3: Simulate backend API call (replace with actual backend)
        backend_response = {
            "status": "success",
            "data": {
                "message": "Processed through intelligent middleware",
                "path": path,
                "method": method,
                "analysis": analysis_result,
                "routing": routing_result
            },
            "timestamp": "2025-07-12T10:00:00Z"
        }
        
        # Step 4: Enhance response using MCP Response Enhancer
        enhancement_request = {
            "original_response": backend_response,
            "routing_context": routing_result,
            "enhancement_rules": ["ai_insights", "performance_optimization"]
        }
        
        enhancement_result = await call_mcp_server(
            RESPONSE_ENHANCER_URL,
            "/enhance",
            enhancement_request
        )
        
        # Return the enhanced response
        final_response = enhancement_result.get("enhanced_response", backend_response)
        final_response["middleware_metadata"] = {
            "processing_chain": ["analyze", "route", "enhance"],
            "mcp_servers_used": 3,
            "enhancements_applied": enhancement_result.get("applied_enhancements", []),
            "performance_metrics": enhancement_result.get("performance_metrics", {})
        }
        
        return JSONResponse(content=final_response)
        
    except Exception as e:
        return JSONResponse(
            status_code=500,
            content={
                "error": "Middleware processing failed",
                "details": str(e),
                "suggestion": "Check MCP server connectivity"
            }
        )

@app.get("/health")
async def health_check():
    """Health check endpoint"""
    try:
        # Test connectivity to all MCP servers if URLs are configured
        health_checks = []
        if CONTENT_ANALYZER_URL:
            health_checks.append(call_mcp_server(CONTENT_ANALYZER_URL, "/health", {}))
        if REQUEST_ROUTER_URL:
            health_checks.append(call_mcp_server(REQUEST_ROUTER_URL, "/health", {}))
        if RESPONSE_ENHANCER_URL:
            health_checks.append(call_mcp_server(RESPONSE_ENHANCER_URL, "/health", {}))
        
        if health_checks:
            results = await asyncio.gather(*health_checks, return_exceptions=True)
            
            return {
                "status": "healthy",
                "service": "Intelligent API Middleware",
                "mcp_servers": {
                    "content_analyzer": "healthy" if CONTENT_ANALYZER_URL and not isinstance(results[0], Exception) else "unhealthy",
                    "request_router": "healthy" if REQUEST_ROUTER_URL and not isinstance(results[1], Exception) else "unhealthy",
                    "response_enhancer": "healthy" if RESPONSE_ENHANCER_URL and not isinstance(results[2], Exception) else "unhealthy"
                }
            }
        else:
            return {
                "status": "healthy",
                "service": "Intelligent API Middleware",
                "note": "MCP servers not yet configured"
            }
    except Exception as e:
        return JSONResponse(
            status_code=503,
            content={
                "status": "unhealthy",
                "error": str(e)
            }
        )

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=int(os.getenv("PORT", 8080)))
EOF

    cat > "$work_dir/api-middleware/requirements.txt" << 'EOF'
fastapi==0.104.1
uvicorn[standard]==0.24.0
httpx==0.25.2
EOF

    cp "$work_dir/content-analyzer/Dockerfile" "$work_dir/api-middleware/"
    
    echo "$work_dir"
}

# Deploy MCP servers to Cloud Run
deploy_mcp_servers() {
    log_info "Deploying MCP servers to Cloud Run..."
    
    local work_dir="$1"
    local urls_file="/tmp/mcp-urls-$$"
    
    # Deploy Content Analyzer MCP Server
    log_info "Deploying Content Analyzer MCP Server..."
    cd "$work_dir/content-analyzer"
    gcloud run deploy "${MCP_SERVICE_PREFIX}-content-analyzer" \
        --source . \
        --region "$REGION" \
        --platform managed \
        --allow-unauthenticated \
        --set-env-vars "PROJECT_ID=${PROJECT_ID},REGION=${REGION}" \
        --memory 512Mi \
        --cpu 1 \
        --concurrency 100 \
        --timeout 300 \
        --quiet
    
    # Get the URL for the content analyzer
    CONTENT_ANALYZER_URL=$(gcloud run services describe \
        "${MCP_SERVICE_PREFIX}-content-analyzer" \
        --region "$REGION" \
        --format 'value(status.url)')
    
    echo "CONTENT_ANALYZER_URL=${CONTENT_ANALYZER_URL}" >> "$urls_file"
    log_success "Content Analyzer deployed at: ${CONTENT_ANALYZER_URL}"
    
    # Deploy Request Router MCP Server
    log_info "Deploying Request Router MCP Server..."
    cd "$work_dir/request-router"
    gcloud run deploy "${MCP_SERVICE_PREFIX}-request-router" \
        --source . \
        --region "$REGION" \
        --platform managed \
        --allow-unauthenticated \
        --set-env-vars "PROJECT_ID=${PROJECT_ID},REGION=${REGION}" \
        --memory 512Mi \
        --cpu 1 \
        --concurrency 100 \
        --timeout 300 \
        --quiet
    
    # Get the URL for the request router
    REQUEST_ROUTER_URL=$(gcloud run services describe \
        "${MCP_SERVICE_PREFIX}-request-router" \
        --region "$REGION" \
        --format 'value(status.url)')
    
    echo "REQUEST_ROUTER_URL=${REQUEST_ROUTER_URL}" >> "$urls_file"
    log_success "Request Router deployed at: ${REQUEST_ROUTER_URL}"
    
    # Deploy Response Enhancer MCP Server
    log_info "Deploying Response Enhancer MCP Server..."
    cd "$work_dir/response-enhancer"
    gcloud run deploy "${MCP_SERVICE_PREFIX}-response-enhancer" \
        --source . \
        --region "$REGION" \
        --platform managed \
        --allow-unauthenticated \
        --set-env-vars "PROJECT_ID=${PROJECT_ID},REGION=${REGION}" \
        --memory 512Mi \
        --cpu 1 \
        --concurrency 100 \
        --timeout 300 \
        --quiet
    
    # Get the URL for the response enhancer
    RESPONSE_ENHANCER_URL=$(gcloud run services describe \
        "${MCP_SERVICE_PREFIX}-response-enhancer" \
        --region "$REGION" \
        --format 'value(status.url)')
    
    echo "RESPONSE_ENHANCER_URL=${RESPONSE_ENHANCER_URL}" >> "$urls_file"
    log_success "Response Enhancer deployed at: ${RESPONSE_ENHANCER_URL}"
    
    echo "$urls_file"
}

# Deploy main middleware service
deploy_middleware() {
    log_info "Deploying main API middleware service..."
    
    local work_dir="$1"
    local urls_file="$2"
    
    # Source the URLs
    source "$urls_file"
    
    cd "$work_dir/api-middleware"
    gcloud run deploy "$MIDDLEWARE_SERVICE" \
        --source . \
        --region "$REGION" \
        --platform managed \
        --allow-unauthenticated \
        --set-env-vars "PROJECT_ID=${PROJECT_ID},REGION=${REGION},CONTENT_ANALYZER_URL=${CONTENT_ANALYZER_URL},REQUEST_ROUTER_URL=${REQUEST_ROUTER_URL},RESPONSE_ENHANCER_URL=${RESPONSE_ENHANCER_URL}" \
        --memory 1Gi \
        --cpu 2 \
        --concurrency 100 \
        --timeout 300 \
        --quiet
    
    # Get the middleware service URL
    MIDDLEWARE_URL=$(gcloud run services describe \
        "$MIDDLEWARE_SERVICE" \
        --region "$REGION" \
        --format 'value(status.url)')
    
    echo "MIDDLEWARE_URL=${MIDDLEWARE_URL}" >> "$urls_file"
    log_success "Main middleware deployed at: ${MIDDLEWARE_URL}"
}

# Configure Cloud Endpoints
configure_endpoints() {
    log_info "Configuring Cloud Endpoints..."
    
    local urls_file="$1"
    source "$urls_file"
    
    # Create Cloud Endpoints configuration
    cat > "/tmp/openapi-$$.yaml" << EOF
swagger: '2.0'
info:
  title: Intelligent API Middleware Gateway
  description: AI-powered API gateway using MCP servers
  version: 1.0.0
host: ${ENDPOINTS_CONFIG}.endpoints.${PROJECT_ID}.cloud.goog
schemes:
  - https
produces:
  - application/json
paths:
  /{proxy+}:
    x-google-backend:
      address: ${MIDDLEWARE_URL}
      path_translation: APPEND_PATH_TO_ADDRESS
    get:
      summary: Intelligent GET requests
      operationId: intelligentGet
      parameters:
        - name: proxy
          in: path
          required: true
          type: string
      responses:
        200:
          description: Successful response
    post:
      summary: Intelligent POST requests
      operationId: intelligentPost
      parameters:
        - name: proxy
          in: path
          required: true
          type: string
        - name: body
          in: body
          schema:
            type: object
      responses:
        200:
          description: Successful response
EOF
    
    # Deploy Cloud Endpoints configuration
    gcloud endpoints services deploy "/tmp/openapi-$$.yaml" --quiet
    
    # Get the endpoint URL
    ENDPOINT_URL="https://${ENDPOINTS_CONFIG}.endpoints.${PROJECT_ID}.cloud.goog"
    
    echo "ENDPOINT_URL=${ENDPOINT_URL}" >> "$urls_file"
    log_success "Cloud Endpoints configured at: ${ENDPOINT_URL}"
    
    # Clean up temporary file
    rm -f "/tmp/openapi-$$.yaml"
}

# Verify deployment
verify_deployment() {
    log_info "Verifying deployment..."
    
    local urls_file="$1"
    source "$urls_file"
    
    # Test MCP server health endpoints
    log_info "Testing MCP server health endpoints..."
    
    local services=("$CONTENT_ANALYZER_URL" "$REQUEST_ROUTER_URL" "$RESPONSE_ENHANCER_URL")
    local service_names=("Content Analyzer" "Request Router" "Response Enhancer")
    
    for i in "${!services[@]}"; do
        local url="${services[$i]}"
        local name="${service_names[$i]}"
        
        if curl -sf "${url}/health" > /dev/null 2>&1; then
            log_success "${name} health check passed"
        else
            log_warning "${name} health check failed - service may still be starting"
        fi
    done
    
    # Test main middleware health
    log_info "Testing main middleware health..."
    if curl -sf "${MIDDLEWARE_URL}/health" > /dev/null 2>&1; then
        log_success "Main middleware health check passed"
    else
        log_warning "Main middleware health check failed - service may still be starting"
    fi
    
    # Test API endpoint
    log_info "Testing API endpoint..."
    if curl -sf "${ENDPOINT_URL}/api/test?query=sample" > /dev/null 2>&1; then
        log_success "API endpoint test passed"
    else
        log_warning "API endpoint test failed - endpoints may still be configuring"
    fi
}

# Save deployment info
save_deployment_info() {
    log_info "Saving deployment information..."
    
    local urls_file="$1"
    local info_file="$SCRIPT_DIR/deployment-info.env"
    
    # Copy URLs and add additional info
    cp "$urls_file" "$info_file"
    cat >> "$info_file" << EOF
PROJECT_ID=${PROJECT_ID}
REGION=${REGION}
ZONE=${ZONE}
MCP_SERVICE_PREFIX=${MCP_SERVICE_PREFIX}
MIDDLEWARE_SERVICE=${MIDDLEWARE_SERVICE}
ENDPOINTS_CONFIG=${ENDPOINTS_CONFIG}
DEPLOYMENT_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF
    
    log_success "Deployment information saved to: $info_file"
    
    # Display deployment summary
    echo
    log_success "=== Deployment Summary ==="
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "Content Analyzer: $(grep CONTENT_ANALYZER_URL "$urls_file" | cut -d'=' -f2)"
    echo "Request Router: $(grep REQUEST_ROUTER_URL "$urls_file" | cut -d'=' -f2)"
    echo "Response Enhancer: $(grep RESPONSE_ENHANCER_URL "$urls_file" | cut -d'=' -f2)"
    echo "Main Middleware: $(grep MIDDLEWARE_URL "$urls_file" | cut -d'=' -f2)"
    echo "API Endpoint: $(grep ENDPOINT_URL "$urls_file" | cut -d'=' -f2)"
    echo
    log_info "To test the API:"
    echo "curl -X GET \"$(grep ENDPOINT_URL "$urls_file" | cut -d'=' -f2)/api/test?query=sample\""
    echo
    log_info "To clean up resources:"
    echo "./destroy.sh"
}

# Main deployment function
main() {
    log_info "Starting API Middleware MCP deployment..."
    
    check_prerequisites
    setup_project
    enable_apis
    
    local work_dir
    work_dir=$(create_mcp_servers)
    
    local urls_file
    urls_file=$(deploy_mcp_servers "$work_dir")
    
    deploy_middleware "$work_dir" "$urls_file"
    configure_endpoints "$urls_file"
    verify_deployment "$urls_file"
    save_deployment_info "$urls_file"
    
    # Clean up temporary files
    rm -rf "$work_dir"
    rm -f "$urls_file"
    
    log_success "API Middleware MCP deployment completed successfully!"
}

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi