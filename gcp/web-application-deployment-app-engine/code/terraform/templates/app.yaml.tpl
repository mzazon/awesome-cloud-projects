# App Engine configuration file
# This file defines how App Engine should run the application

runtime: ${runtime}

# Automatic scaling configuration
automatic_scaling:
  min_instances: ${min_instances}
  max_instances: ${max_instances}
  target_cpu_utilization: ${target_cpu_utilization}

# Resource limits for each instance
resources:
  cpu: 1
  memory_gb: 0.5
  disk_size_gb: 10

# Static file handlers for efficient serving
handlers:
# Serve static CSS files
- url: /static/css/.*
  static_dir: static/css
  expiration: "1d"

# Serve static JavaScript files  
- url: /static/js/.*
  static_dir: static/js
  expiration: "1d"

# Serve static image files
- url: /static/images/.*
  static_dir: static/images
  expiration: "7d"

# Serve all other static files
- url: /static/.*
  static_dir: static
  expiration: "1h"

# Main application handler
- url: /.*
  script: auto

# Environment variables
env_variables:
%{ for key, value in environment_variables ~}
  ${key}: "${value}"
%{ endfor ~}

# Skip files during deployment (improves deployment speed)
skip_files:
- ^(.*/)?#.*#$
- ^(.*/)?.*~$
- ^(.*/)?.*\.py[co]$
- ^(.*/)?.*/RCS/.*$
- ^(.*/)?\..*$
- ^(.*/)?.*\.bak$
- ^(.*/)?venv/.*$
- ^(.*/)?__pycache__/.*$