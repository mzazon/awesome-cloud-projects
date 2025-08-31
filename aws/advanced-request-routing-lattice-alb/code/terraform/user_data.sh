#!/bin/bash
# User data script for EC2 instances serving web content
# This script sets up Apache with different content for routing demonstration

# Update system packages
dnf update -y

# Install Apache HTTP Server
dnf install -y httpd

# Start and enable Apache
systemctl start httpd
systemctl enable httpd

# Create different content for routing demonstration
mkdir -p /var/www/html/api/v1

# Default service content
cat > /var/www/html/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Default Service</title>
    <style>
        body { 
            font-family: Arial, sans-serif; 
            margin: 40px; 
            background-color: #f5f5f5; 
        }
        .container { 
            background-color: white; 
            padding: 20px; 
            border-radius: 8px; 
            box-shadow: 0 2px 4px rgba(0,0,0,0.1); 
        }
        .header { 
            color: #2c3e50; 
            border-bottom: 2px solid #3498db; 
            padding-bottom: 10px; 
        }
        .info { 
            margin: 20px 0; 
            padding: 15px; 
            background-color: #ecf0f1; 
            border-radius: 4px; 
        }
    </style>
</head>
<body>
    <div class="container">
        <h1 class="header">Default Service</h1>
        <div class="info">
            <p><strong>Environment:</strong> ${environment}</p>
            <p><strong>Project:</strong> ${project}</p>
            <p><strong>Routing:</strong> Default routing target</p>
            <p><strong>Instance ID:</strong> <span id="instance-id">Loading...</span></p>
            <p><strong>Timestamp:</strong> <span id="timestamp"></span></p>
        </div>
        <p>This is the default service endpoint. Requests that don't match specific routing rules will land here.</p>
    </div>
    
    <script>
        // Get instance metadata
        fetch('http://169.254.169.254/latest/meta-data/instance-id')
            .then(response => response.text())
            .then(data => document.getElementById('instance-id').textContent = data)
            .catch(error => document.getElementById('instance-id').textContent = 'Unavailable');
            
        // Set current timestamp
        document.getElementById('timestamp').textContent = new Date().toISOString();
    </script>
</body>
</html>
EOF

# API v1 service content
cat > /var/www/html/api/v1/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>API V1 Service</title>
    <style>
        body { 
            font-family: Arial, sans-serif; 
            margin: 40px; 
            background-color: #e8f5e8; 
        }
        .container { 
            background-color: white; 
            padding: 20px; 
            border-radius: 8px; 
            box-shadow: 0 2px 4px rgba(0,0,0,0.1); 
        }
        .header { 
            color: #27ae60; 
            border-bottom: 2px solid #2ecc71; 
            padding-bottom: 10px; 
        }
        .info { 
            margin: 20px 0; 
            padding: 15px; 
            background-color: #d5f4e6; 
            border-radius: 4px; 
        }
    </style>
</head>
<body>
    <div class="container">
        <h1 class="header">API V1 Service</h1>
        <div class="info">
            <p><strong>Environment:</strong> ${environment}</p>
            <p><strong>Project:</strong> ${project}</p>
            <p><strong>Path:</strong> /api/v1/</p>
            <p><strong>Routing Type:</strong> Path-based routing</p>
            <p><strong>Instance ID:</strong> <span id="instance-id">Loading...</span></p>
            <p><strong>Timestamp:</strong> <span id="timestamp"></span></p>
        </div>
        <p>This endpoint is reached via path-based routing. Requests to /api/v1/* are directed here.</p>
    </div>
    
    <script>
        // Get instance metadata
        fetch('http://169.254.169.254/latest/meta-data/instance-id')
            .then(response => response.text())
            .then(data => document.getElementById('instance-id').textContent = data)
            .catch(error => document.getElementById('instance-id').textContent = 'Unavailable');
            
        // Set current timestamp
        document.getElementById('timestamp').textContent = new Date().toISOString();
    </script>
</body>
</html>
EOF

# Beta service content (accessed via header routing)
cat > /var/www/html/beta.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Beta Service</title>
    <style>
        body { 
            font-family: Arial, sans-serif; 
            margin: 40px; 
            background-color: #fff3cd; 
        }
        .container { 
            background-color: white; 
            padding: 20px; 
            border-radius: 8px; 
            box-shadow: 0 2px 4px rgba(0,0,0,0.1); 
        }
        .header { 
            color: #f39c12; 
            border-bottom: 2px solid #f1c40f; 
            padding-bottom: 10px; 
        }
        .info { 
            margin: 20px 0; 
            padding: 15px; 
            background-color: #fef9e7; 
            border-radius: 4px; 
        }
        .warning { 
            background-color: #fff3cd; 
            border: 1px solid #ffeaa7; 
            padding: 10px; 
            border-radius: 4px; 
            margin: 15px 0; 
        }
    </style>
</head>
<body>
    <div class="container">
        <h1 class="header">Beta Service</h1>
        <div class="info">
            <p><strong>Environment:</strong> ${environment}</p>
            <p><strong>Project:</strong> ${project}</p>
            <p><strong>Header:</strong> X-Service-Version: beta</p>
            <p><strong>Routing Type:</strong> Header-based routing</p>
            <p><strong>Instance ID:</strong> <span id="instance-id">Loading...</span></p>
            <p><strong>Timestamp:</strong> <span id="timestamp"></span></p>
        </div>
        <div class="warning">
            <strong>⚠️ Beta Service:</strong> This is a beta version with experimental features.
        </div>
        <p>This endpoint is reached via header-based routing. Requests with the X-Service-Version: beta header are directed here.</p>
    </div>
    
    <script>
        // Get instance metadata
        fetch('http://169.254.169.254/latest/meta-data/instance-id')
            .then(response => response.text())
            .then(data => document.getElementById('instance-id').textContent = data)
            .catch(error => document.getElementById('instance-id').textContent = 'Unavailable');
            
        // Set current timestamp
        document.getElementById('timestamp').textContent = new Date().toISOString();
    </script>
</body>
</html>
EOF

# Configure virtual hosts for header-based routing
cat >> /etc/httpd/conf/httpd.conf << 'VHOST'

# Virtual host configuration for header-based routing
<VirtualHost *:80>
    DocumentRoot /var/www/html
    
    # Enable rewrite engine for header-based routing
    RewriteEngine On
    
    # Route requests with X-Service-Version: beta to beta.html
    RewriteCond %{HTTP:X-Service-Version} ^beta$ [NC]
    RewriteRule ^(.*)$ /beta.html [L]
    
    # Log rewrite rules for debugging
    LogLevel alert rewrite:trace3
</VirtualHost>
VHOST

# Set proper permissions
chown -R apache:apache /var/www/html
chmod -R 644 /var/www/html
find /var/www/html -type d -exec chmod 755 {} \;

# Restart Apache to apply configuration changes
systemctl restart httpd

# Enable Apache status for health checks
cat > /var/www/html/health << 'EOF'
OK
EOF

# Create a simple API endpoint for testing
mkdir -p /var/www/html/api/v1
cat > /var/www/html/api/v1/status << 'EOF'
{
    "status": "healthy",
    "service": "api-v1",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

# Log the completion
echo "$(date): Web server setup completed" >> /var/log/user-data.log