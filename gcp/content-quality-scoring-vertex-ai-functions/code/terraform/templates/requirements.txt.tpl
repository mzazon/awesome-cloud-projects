# ================================================================
# Python Dependencies for Content Quality Analysis Cloud Function
# ================================================================
# This file specifies the Python packages required for the Cloud
# Function to operate correctly.
# ================================================================

# Core Cloud Functions framework
functions-framework==${functions_framework_version}

# Google Cloud client libraries
google-cloud-storage==${storage_version}
google-cloud-aiplatform==${aiplatform_version}
google-cloud-logging==${logging_version}

# Additional Google Cloud dependencies
google-cloud-core>=2.4.1
google-auth>=2.23.0
google-api-core>=2.12.0

# JSON and data processing
simplejson>=3.19.0

# HTTP and networking
requests>=2.31.0
urllib3>=1.26.0

# Date and time utilities
python-dateutil>=2.8.2

# Development and debugging utilities (optional)
# Uncomment these for enhanced debugging capabilities
# google-cloud-error-reporting>=1.9.0
# google-cloud-trace>=1.12.0

# Performance and reliability
tenacity>=8.2.0  # For retry logic
cachetools>=5.3.0  # For caching API responses

# Security utilities
cryptography>=41.0.0

# Text processing utilities
chardet>=5.2.0  # For character encoding detection

# ================================================================
# Version Notes
# ================================================================
# 
# functions-framework: Google Cloud Functions runtime framework
# - Provides the @functions_framework decorator
# - Handles HTTP and CloudEvent triggers
# - Manages function lifecycle and error handling
#
# google-cloud-storage: Cloud Storage client library
# - Enables reading from content bucket
# - Supports writing to results bucket
# - Provides metadata and IAM operations
#
# google-cloud-aiplatform: Vertex AI client library
# - Enables Vertex AI Gemini model access
# - Provides generative AI capabilities
# - Supports model configuration and content generation
#
# google-cloud-logging: Cloud Logging client library
# - Structured logging for function monitoring
# - Integration with Cloud Logging for observability
# - Error tracking and debugging support
#
# Additional libraries provide enhanced functionality:
# - simplejson: Enhanced JSON parsing and serialization
# - requests: HTTP client for external API calls
# - python-dateutil: Advanced date/time parsing
# - tenacity: Retry logic for transient failures
# - cachetools: Caching for performance optimization
# - cryptography: Security and encryption utilities
# - chardet: Character encoding detection for text files
#
# ================================================================
# Security Considerations
# ================================================================
#
# All package versions are pinned to specific versions for:
# - Reproducible builds and deployments
# - Security vulnerability management
# - Consistent behavior across environments
# - Compliance with security policies
#
# Regular updates should be performed to:
# - Address security vulnerabilities
# - Incorporate bug fixes and improvements
# - Maintain compatibility with Google Cloud services
# - Leverage new features and optimizations
#
# ================================================================
# Performance Optimization
# ================================================================
#
# Package selection optimized for:
# - Cold start performance (minimal dependencies)
# - Memory usage efficiency
# - CPU performance for text processing
# - Network efficiency for API calls
#
# Consider these optimizations:
# - Use streaming for large files
# - Implement caching for repeated operations
# - Optimize JSON serialization for large results
# - Use async operations where applicable