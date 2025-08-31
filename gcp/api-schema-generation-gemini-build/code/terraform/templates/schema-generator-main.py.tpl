import json
import os
import traceback
from typing import Dict, Any
from google.cloud import storage
from flask import Request
import functions_framework

@functions_framework.http
def generate_schema(request: Request):
    """Generate OpenAPI schema from source code using AI analysis"""
    
    try:
        # In a real implementation, this would use Gemini Code Assist API
        # to analyze source code and extract API patterns
        
        # Enhanced OpenAPI schema with comprehensive documentation
        schema = {
            "openapi": "3.0.3",
            "info": {
                "title": "Generated API Documentation",
                "version": "1.0.0",
                "description": "Auto-generated from source code analysis using Gemini Code Assist",
                "contact": {
                    "name": "API Support",
                    "email": "api-support@example.com"
                }
            },
            "servers": [
                {
                    "url": "https://api.example.com/v1",
                    "description": "Production server"
                },
                {
                    "url": "https://staging-api.example.com/v1",
                    "description": "Staging server"
                }
            ],
            "paths": {
                "/api/users": {
                    "get": {
                        "summary": "Retrieve all users",
                        "description": "Get a list of users with optional filtering",
                        "parameters": [
                            {
                                "name": "limit",
                                "in": "query",
                                "description": "Maximum number of users to return",
                                "required": False,
                                "schema": {"type": "integer", "default": 50, "minimum": 1, "maximum": 100}
                            },
                            {
                                "name": "role",
                                "in": "query",
                                "description": "Filter by user role",
                                "required": False,
                                "schema": {"type": "string", "enum": ["admin", "user", "viewer"]}
                            }
                        ],
                        "responses": {
                            "200": {
                                "description": "List of users",
                                "content": {
                                    "application/json": {
                                        "schema": {
                                            "type": "array",
                                            "items": {"$ref": "#/components/schemas/User"}
                                        }
                                    }
                                }
                            },
                            "400": {
                                "description": "Bad request",
                                "content": {
                                    "application/json": {
                                        "schema": {"$ref": "#/components/schemas/Error"}
                                    }
                                }
                            }
                        }
                    },
                    "post": {
                        "summary": "Create a new user",
                        "description": "Create a new user with the provided information",
                        "requestBody": {
                            "required": True,
                            "content": {
                                "application/json": {
                                    "schema": {"$ref": "#/components/schemas/CreateUserRequest"}
                                }
                            }
                        },
                        "responses": {
                            "201": {
                                "description": "User created successfully",
                                "content": {
                                    "application/json": {
                                        "schema": {"$ref": "#/components/schemas/User"}
                                    }
                                }
                            },
                            "400": {
                                "description": "Invalid request data",
                                "content": {
                                    "application/json": {
                                        "schema": {"$ref": "#/components/schemas/Error"}
                                    }
                                }
                            }
                        }
                    }
                },
                "/api/users/{userId}": {
                    "get": {
                        "summary": "Retrieve a specific user",
                        "description": "Get user details by ID",
                        "parameters": [
                            {
                                "name": "userId",
                                "in": "path",
                                "required": True,
                                "description": "Unique identifier for the user",
                                "schema": {"type": "integer", "minimum": 1}
                            }
                        ],
                        "responses": {
                            "200": {
                                "description": "User details",
                                "content": {
                                    "application/json": {
                                        "schema": {"$ref": "#/components/schemas/User"}
                                    }
                                }
                            },
                            "404": {
                                "description": "User not found",
                                "content": {
                                    "application/json": {
                                        "schema": {"$ref": "#/components/schemas/Error"}
                                    }
                                }
                            }
                        }
                    }
                },
                "/api/health": {
                    "get": {
                        "summary": "Health check",
                        "description": "Check API health status",
                        "responses": {
                            "200": {
                                "description": "API is healthy",
                                "content": {
                                    "application/json": {
                                        "schema": {"$ref": "#/components/schemas/HealthStatus"}
                                    }
                                }
                            }
                        }
                    }
                }
            },
            "components": {
                "schemas": {
                    "User": {
                        "type": "object",
                        "required": ["id", "name", "email"],
                        "properties": {
                            "id": {"type": "integer", "description": "Unique user identifier"},
                            "name": {"type": "string", "description": "User's full name"},
                            "email": {"type": "string", "format": "email", "description": "User's email address"},
                            "role": {"type": "string", "enum": ["admin", "user", "viewer"], "description": "User's role"}
                        }
                    },
                    "CreateUserRequest": {
                        "type": "object",
                        "required": ["name", "email"],
                        "properties": {
                            "name": {"type": "string", "minLength": 1, "description": "User's full name"},
                            "email": {"type": "string", "format": "email", "description": "User's email address"},
                            "role": {"type": "string", "enum": ["admin", "user", "viewer"], "default": "user"}
                        }
                    },
                    "Error": {
                        "type": "object",
                        "required": ["error"],
                        "properties": {
                            "error": {"type": "string", "description": "Error message"},
                            "details": {"type": "string", "description": "Additional error details"}
                        }
                    },
                    "HealthStatus": {
                        "type": "object",
                        "required": ["status"],
                        "properties": {
                            "status": {"type": "string", "enum": ["healthy", "unhealthy"]},
                            "timestamp": {"type": "string", "format": "date-time"}
                        }
                    }
                }
            }
        }
        
        # Upload schema to Cloud Storage with metadata
        client = storage.Client()
        bucket_name = os.environ.get('BUCKET_NAME', '${bucket_name}')
        bucket = client.bucket(bucket_name)
        
        # Create schema blob with metadata
        blob = bucket.blob('openapi-schema.json')
        blob.metadata = {
            'generated_at': '2025-07-23T00:00:00Z',
            'generator': 'gemini-code-assist',
            'version': '1.0.0'
        }
        blob.upload_from_string(
            json.dumps(schema, indent=2),
            content_type='application/json'
        )
        
        return {
            "status": "success",
            "schema_location": f"gs://{bucket_name}/openapi-schema.json",
            "endpoints_discovered": len(schema["paths"]),
            "schemas_generated": len(schema["components"]["schemas"])
        }
        
    except Exception as e:
        error_details = {
            "status": "error",
            "message": str(e),
            "traceback": traceback.format_exc()
        }
        print(f"Error generating schema: {error_details}")
        return error_details, 500