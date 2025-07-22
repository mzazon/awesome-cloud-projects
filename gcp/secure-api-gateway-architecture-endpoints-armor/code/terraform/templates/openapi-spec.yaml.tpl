swagger: "2.0"
info:
  title: "Secure API Gateway Demo"
  description: "Production-ready API gateway with Cloud Endpoints and Cloud Armor security"
  version: "1.0.0"
  contact:
    name: "API Support"
    email: "support@example.com"
  license:
    name: "MIT"
    url: "https://opensource.org/licenses/MIT"

host: "${api_name}.endpoints.${project_id}.cloud.goog"
basePath: "/"
schemes:
  - "https"
  - "http"
produces:
  - "application/json"
consumes:
  - "application/json"

# Security definitions for API key authentication
securityDefinitions:
  api_key:
    type: "apiKey"
    name: "key"
    in: "query"
    description: "API key for authentication"

# API endpoint definitions
paths:
  /health:
    get:
      summary: "Health check endpoint"
      description: "Returns the health status of the API service"
      operationId: "healthCheck"
      tags:
        - "health"
      responses:
        200:
          description: "Service is healthy"
          schema:
            type: "object"
            properties:
              status:
                type: "string"
                example: "healthy"
              timestamp:
                type: "string"
                format: "date-time"
              service:
                type: "string"
                example: "backend-api"
              version:
                type: "string"
                example: "1.0.0"
        503:
          description: "Service is unhealthy"
          schema:
            type: "object"
            properties:
              status:
                type: "string"
                example: "unhealthy"
              error:
                type: "string"

  /api/v1/users:
    get:
      summary: "Get users list"
      description: "Retrieve a list of all users in the system"
      operationId: "getUsers"
      tags:
        - "users"
      security:
        - api_key: []
      responses:
        200:
          description: "Users retrieved successfully"
          schema:
            type: "object"
            properties:
              users:
                type: "array"
                items:
                  type: "object"
                  properties:
                    id:
                      type: "integer"
                      example: 1
                    name:
                      type: "string"
                      example: "Alice"
                    email:
                      type: "string"
                      format: "email"
                      example: "alice@example.com"
              total:
                type: "integer"
                example: 3
              timestamp:
                type: "string"
                format: "date-time"
        401:
          description: "Unauthorized - missing or invalid API key"
          schema:
            $ref: "#/definitions/Error"
        403:
          description: "Forbidden - access denied"
          schema:
            $ref: "#/definitions/Error"

  /api/v1/data:
    post:
      summary: "Create new data"
      description: "Submit new data to the system for processing"
      operationId: "createData"
      tags:
        - "data"
      security:
        - api_key: []
      parameters:
        - in: "body"
          name: "body"
          description: "Data to be processed"
          required: true
          schema:
            type: "object"
            properties:
              name:
                type: "string"
                example: "Sample Data"
              value:
                type: "string"
                example: "Sample Value"
              category:
                type: "string"
                example: "test"
            required:
              - "name"
              - "value"
      responses:
        201:
          description: "Data created successfully"
          schema:
            type: "object"
            properties:
              message:
                type: "string"
                example: "Data received and processed successfully"
              data:
                type: "object"
              id:
                type: "integer"
                example: 12345
              timestamp:
                type: "string"
                format: "date-time"
              status:
                type: "string"
                example: "created"
        400:
          description: "Bad request - invalid data format"
          schema:
            $ref: "#/definitions/Error"
        401:
          description: "Unauthorized - missing or invalid API key"
          schema:
            $ref: "#/definitions/Error"
        403:
          description: "Forbidden - access denied"
          schema:
            $ref: "#/definitions/Error"

  /api/v1/status:
    get:
      summary: "Get system status"
      description: "Retrieve the current status of the API system"
      operationId: "getStatus"
      tags:
        - "system"
      security:
        - api_key: []
      responses:
        200:
          description: "System status retrieved successfully"
          schema:
            type: "object"
            properties:
              service:
                type: "string"
                example: "backend-api"
              status:
                type: "string"
                example: "running"
              uptime:
                type: "string"
                example: "2 hours"
              timestamp:
                type: "string"
                format: "date-time"
              environment:
                type: "string"
                example: "production"
        401:
          description: "Unauthorized - missing or invalid API key"
          schema:
            $ref: "#/definitions/Error"
        403:
          description: "Forbidden - access denied"
          schema:
            $ref: "#/definitions/Error"

# Common data type definitions
definitions:
  Error:
    type: "object"
    properties:
      error:
        type: "string"
        description: "Error type"
      message:
        type: "string"
        description: "Human-readable error message"
      timestamp:
        type: "string"
        format: "date-time"
        description: "Timestamp when the error occurred"
    required:
      - "error"
      - "message"
      - "timestamp"

# Google Cloud Endpoints specific configuration
x-google-backend:
  address: "http://${backend_service_name}.${zone}.c.${project_id}.internal:${backend_port}"
  protocol: "http"
  path_translation: "APPEND_PATH_TO_ADDRESS"

# Rate limiting and quota configuration
x-google-quota:
  metric_rules:
    - selector: "*"
      metric_costs:
        "serviceruntime.googleapis.com/api/request_count": 1

# API management configuration
x-google-management:
  metrics:
    - name: "serviceruntime.googleapis.com/api/request_count"
      display_name: "Request Count"
      description: "Number of API requests"
      metric_kind: "DELTA"
      value_type: "INT64"
  quota:
    limits:
      - name: "request_limit"
        display_name: "Request Limit"
        description: "Rate limit for API requests"
        default_limit: 1000
        duration: "60s"
        max_limit: 10000

# Documentation and developer portal configuration
x-google-endpoints:
  - name: "${api_name}.endpoints.${project_id}.cloud.goog"
    target: "${backend_service_name}.${zone}.c.${project_id}.internal:${backend_port}"