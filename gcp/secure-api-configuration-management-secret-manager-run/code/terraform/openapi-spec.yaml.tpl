# OpenAPI 3.0 specification for secure API Gateway configuration
# This specification defines the API endpoints, authentication, and routing rules

swagger: '2.0'
info:
  title: Secure API Gateway
  description: API Gateway for secure configuration management with Secret Manager integration
  version: 1.0.0
  contact:
    name: Cloud Architecture Team
    email: cloud-team@example.com
  license:
    name: Apache 2.0
    url: https://www.apache.org/licenses/LICENSE-2.0.html

host: ${service_name}.gateway.dev
schemes:
  - https
basePath: /
produces:
  - application/json
consumes:
  - application/json

# Security definitions for API key authentication
securityDefinitions:
  api_key:
    type: apiKey
    name: key
    in: query
    description: API key for accessing protected endpoints
  bearer_auth:
    type: apiKey
    name: Authorization
    in: header
    description: Bearer token for API authentication

# Global security requirements
security:
  - api_key: []

# API paths and operations
paths:
  /health:
    get:
      summary: Health check endpoint
      description: Returns the health status of the API service
      operationId: healthCheck
      tags:
        - Health
      responses:
        200:
          description: Service is healthy
          schema:
            type: object
            properties:
              status:
                type: string
                example: "healthy"
              service:
                type: string
                example: "secure-api"
              environment:
                type: string
                example: "dev"
              timestamp:
                type: number
                example: 1640995200
              version:
                type: string
                example: "1.0.0"
              secret_manager:
                type: string
                example: "accessible"
        503:
          description: Service is unhealthy
          schema:
            type: object
            properties:
              status:
                type: string
                example: "unhealthy"
              error:
                type: string
      x-google-backend:
        address: ${service_url}
        path_translation: APPEND_PATH_TO_ADDRESS

  /config:
    get:
      summary: Get application configuration
      description: Returns non-sensitive application configuration settings
      operationId: getConfig
      tags:
        - Configuration
      security:
        - api_key: []
      responses:
        200:
          description: Configuration retrieved successfully
          schema:
            type: object
            properties:
              debug_mode:
                type: boolean
                example: false
              rate_limit:
                type: integer
                example: 1000
              cache_ttl:
                type: integer
                example: 3600
              log_level:
                type: string
                example: "INFO"
              session_timeout:
                type: integer
                example: 1800
              environment:
                type: string
                example: "dev"
              retrieved_at:
                type: number
                example: 1640995200
        500:
          description: Configuration unavailable
          schema:
            type: object
            properties:
              error:
                type: string
                example: "Configuration unavailable"
              message:
                type: string
                example: "Unable to retrieve application configuration"
      x-google-backend:
        address: ${service_url}
        path_translation: APPEND_PATH_TO_ADDRESS

  /database/status:
    get:
      summary: Check database connectivity
      description: Returns database connection status and configuration
      operationId: databaseStatus
      tags:
        - Database
      security:
        - api_key: []
      responses:
        200:
          description: Database status retrieved successfully
          schema:
            type: object
            properties:
              database:
                type: string
                example: "connected"
              host:
                type: string
                example: "db.example.com"
              port:
                type: integer
                example: 5432
              database:
                type: string
                example: "api_db"
              ssl_mode:
                type: string
                example: "require"
              connection_pool:
                type: string
                example: "healthy"
              last_check:
                type: number
                example: 1640995200
        500:
          description: Database configuration unavailable
          schema:
            type: object
            properties:
              error:
                type: string
                example: "Database configuration unavailable"
              message:
                type: string
                example: "Unable to retrieve database configuration"
      x-google-backend:
        address: ${service_url}
        path_translation: APPEND_PATH_TO_ADDRESS

  /api/data:
    get:
      summary: Get secure API data
      description: Returns protected data requiring Bearer token authentication
      operationId: getSecureData
      tags:
        - Secure Data
      security:
        - api_key: []
        - bearer_auth: []
      parameters:
        - name: Authorization
          in: header
          type: string
          required: true
          description: Bearer token for API authentication
          example: "Bearer sk-1234567890abcdef"
      responses:
        200:
          description: Secure data retrieved successfully
          schema:
            type: object
            properties:
              data:
                type: string
                example: "sensitive_api_data"
              timestamp:
                type: number
                example: 1640995200
              source:
                type: string
                example: "secure-api"
              environment:
                type: string
                example: "dev"
              user_agent:
                type: string
                example: "Mozilla/5.0"
              request_id:
                type: string
                example: "req_1640995200"
        401:
          description: Unauthorized access
          schema:
            type: object
            properties:
              error:
                type: string
                example: "Unauthorized"
              message:
                type: string
                example: "Invalid or missing API key"
        500:
          description: API keys unavailable
          schema:
            type: object
            properties:
              error:
                type: string
                example: "API keys unavailable"
              message:
                type: string
                example: "Unable to retrieve API keys for authentication"
      x-google-backend:
        address: ${service_url}
        path_translation: APPEND_PATH_TO_ADDRESS

  /secrets/rotate:
    post:
      summary: Trigger secret rotation
      description: Clears secret cache to force refresh from Secret Manager
      operationId: rotateSecrets
      tags:
        - Secret Management
      security:
        - api_key: []
      responses:
        200:
          description: Secret cache refreshed successfully
          schema:
            type: object
            properties:
              message:
                type: string
                example: "Secret cache refreshed successfully"
              timestamp:
                type: number
                example: 1640995200
        500:
          description: Secret rotation failed
          schema:
            type: object
            properties:
              error:
                type: string
                example: "Rotation error"
              message:
                type: string
                example: "Failed to refresh secret cache"
      x-google-backend:
        address: ${service_url}
        path_translation: APPEND_PATH_TO_ADDRESS

  /metrics:
    get:
      summary: Get application metrics
      description: Returns basic application metrics and status information
      operationId: getMetrics
      tags:
        - Monitoring
      security:
        - api_key: []
      responses:
        200:
          description: Metrics retrieved successfully
          schema:
            type: object
            properties:
              cache_size:
                type: integer
                example: 3
              environment:
                type: string
                example: "dev"
              uptime:
                type: number
                example: 1640995200
              secret_names:
                type: array
                items:
                  type: string
                example: ["database", "api_keys", "application"]
              client_initialized:
                type: boolean
                example: true
        500:
          description: Metrics collection failed
          schema:
            type: object
            properties:
              error:
                type: string
                example: "Metrics error"
              message:
                type: string
                example: "Failed to collect metrics"
      x-google-backend:
        address: ${service_url}
        path_translation: APPEND_PATH_TO_ADDRESS

# Tag definitions for better organization
tags:
  - name: Health
    description: Health check and status endpoints
  - name: Configuration
    description: Application configuration management
  - name: Database
    description: Database connectivity and status
  - name: Secure Data
    description: Protected API endpoints requiring authentication
  - name: Secret Management
    description: Secret rotation and management
  - name: Monitoring
    description: Application metrics and monitoring

# Global response definitions
definitions:
  Error:
    type: object
    required:
      - error
      - message
    properties:
      error:
        type: string
        description: Error type identifier
      message:
        type: string
        description: Human-readable error message
      timestamp:
        type: number
        description: Unix timestamp when error occurred
      request_id:
        type: string
        description: Unique identifier for the request

  HealthStatus:
    type: object
    required:
      - status
      - service
    properties:
      status:
        type: string
        enum: ["healthy", "unhealthy"]
        description: Overall health status
      service:
        type: string
        description: Service name
      environment:
        type: string
        description: Deployment environment
      timestamp:
        type: number
        description: Unix timestamp of health check
      version:
        type: string
        description: Application version
      secret_manager:
        type: string
        enum: ["accessible", "error", "not_initialized"]
        description: Secret Manager connectivity status