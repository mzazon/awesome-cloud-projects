#!/bin/bash
# User data script for VPC Lattice TLS Passthrough target instances
# This script configures Apache HTTP Server with HTTPS and self-signed certificates

set -e

# Update system packages
dnf update -y
dnf install -y httpd mod_ssl openssl

# Create certificate directory if it doesn't exist
mkdir -p /etc/pki/tls/private
mkdir -p /etc/pki/tls/certs

# Write the certificate files
cat > /etc/pki/tls/certs/server.crt << 'EOF'
${certificate_crt}
EOF

cat > /etc/pki/tls/private/server.key << 'EOF'
${certificate_key}
EOF

# Set proper permissions on certificate files
chmod 644 /etc/pki/tls/certs/server.crt
chmod 600 /etc/pki/tls/private/server.key
chown root:root /etc/pki/tls/certs/server.crt
chown root:root /etc/pki/tls/private/server.key

# Configure SSL virtual host
cat > /etc/httpd/conf.d/ssl.conf << 'SSLCONF'
LoadModule ssl_module modules/mod_ssl.so
Listen 443

<VirtualHost *:443>
    ServerName ${custom_domain}
    DocumentRoot /var/www/html
    
    # SSL Configuration
    SSLEngine on
    SSLCertificateFile /etc/pki/tls/certs/server.crt
    SSLCertificateKeyFile /etc/pki/tls/private/server.key
    
    # Security settings
    SSLProtocol TLSv1.2 TLSv1.3
    SSLCipherSuite ECDHE+AESGCM:ECDHE+CHACHA20:DHE+AESGCM:DHE+CHACHA20:!aNULL:!MD5:!DSS
    SSLHonorCipherOrder on
    
    # Security headers
    Header always set Strict-Transport-Security "max-age=31536000; includeSubDomains"
    Header always set X-Content-Type-Options nosniff
    Header always set X-Frame-Options DENY
    Header always set X-XSS-Protection "1; mode=block"
    
    # Logging
    ErrorLog /var/log/httpd/ssl_error.log
    CustomLog /var/log/httpd/ssl_access.log combined
</VirtualHost>
SSLCONF

# Get instance metadata
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
INSTANCE_TYPE=$(curl -s http://169.254.169.254/latest/meta-data/instance-type)
AVAILABILITY_ZONE=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)
LOCAL_IPV4=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)

# Create dynamic HTTPS response page
cat > /var/www/html/index.html << HTMLEOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>VPC Lattice TLS Passthrough - Target Instance</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            max-width: 800px;
            margin: 0 auto;
            padding: 20px;
            background-color: #f5f5f5;
        }
        .container {
            background-color: white;
            padding: 30px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        .header {
            color: #232F3E;
            border-bottom: 2px solid #FF9900;
            padding-bottom: 10px;
            margin-bottom: 20px;
        }
        .success {
            background-color: #d4edda;
            border: 1px solid #c3e6cb;
            color: #155724;
            padding: 15px;
            border-radius: 4px;
            margin: 20px 0;
        }
        .info-table {
            width: 100%;
            border-collapse: collapse;
            margin: 20px 0;
        }
        .info-table th, .info-table td {
            border: 1px solid #ddd;
            padding: 12px;
            text-align: left;
        }
        .info-table th {
            background-color: #f8f9fa;
            font-weight: bold;
        }
        .footer {
            margin-top: 30px;
            font-size: 0.9em;
            color: #666;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1 class="header">🔒 VPC Lattice TLS Passthrough Success</h1>
        
        <div class="success">
            <strong>✅ End-to-End TLS Encryption Verified!</strong><br>
            This response confirms that encrypted traffic successfully passed through VPC Lattice 
            to this target instance without intermediate decryption.
        </div>

        <h2>Instance Information</h2>
        <table class="info-table">
            <tr>
                <th>Property</th>
                <th>Value</th>
            </tr>
            <tr>
                <td>Instance ID</td>
                <td><code>$INSTANCE_ID</code></td>
            </tr>
            <tr>
                <td>Instance Type</td>
                <td><code>$INSTANCE_TYPE</code></td>
            </tr>
            <tr>
                <td>Availability Zone</td>
                <td><code>$AVAILABILITY_ZONE</code></td>
            </tr>
            <tr>
                <td>Private IP</td>
                <td><code>$LOCAL_IPV4</code></td>
            </tr>
            <tr>
                <td>Request Timestamp</td>
                <td><code id="timestamp"></code></td>
            </tr>
            <tr>
                <td>Server Name</td>
                <td><code>${custom_domain}</code></td>
            </tr>
        </table>

        <h2>TLS Configuration</h2>
        <ul>
            <li><strong>Protocol:</strong> TLS 1.2/1.3</li>
            <li><strong>Certificate:</strong> Self-signed (Demo)</li>
            <li><strong>Cipher Suite:</strong> ECDHE+AESGCM</li>
            <li><strong>Passthrough Mode:</strong> Enabled</li>
        </ul>

        <h2>Security Headers</h2>
        <ul>
            <li>Strict-Transport-Security</li>
            <li>X-Content-Type-Options</li>
            <li>X-Frame-Options</li>
            <li>X-XSS-Protection</li>
        </ul>

        <div class="footer">
            <p><strong>Note:</strong> This is a demonstration environment using self-signed certificates. 
            In production environments, use properly signed certificates from a trusted Certificate Authority.</p>
            
            <p><strong>VPC Lattice TLS Passthrough Recipe</strong> - 
            Demonstrating end-to-end encryption with AWS VPC Lattice, Certificate Manager, and Route 53.</p>
        </div>
    </div>

    <script>
        // Update timestamp on page load
        document.getElementById('timestamp').textContent = new Date().toISOString();
        
        // Add refresh functionality
        setTimeout(function() {
            document.getElementById('timestamp').textContent = new Date().toISOString();
        }, 1000);
    </script>
</body>
</html>
HTMLEOF

# Create health check endpoint
cat > /var/www/html/health << 'HEALTHEOF'
OK
HEALTHEOF

# Configure Apache to start on boot and start it now
systemctl enable httpd
systemctl start httpd

# Configure firewall (if active)
if systemctl is-active --quiet firewalld; then
    firewall-cmd --permanent --add-service=https
    firewall-cmd --reload
fi

# Create log rotation for SSL logs
cat > /etc/logrotate.d/httpd-ssl << 'LOGROTATE'
/var/log/httpd/ssl_*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    postrotate
        /bin/systemctl reload httpd.service > /dev/null 2>/dev/null || true
    endscript
}
LOGROTATE

# Log successful completion
echo "$(date): VPC Lattice target instance configuration completed successfully" >> /var/log/user-data.log
echo "Instance ID: $INSTANCE_ID" >> /var/log/user-data.log
echo "Custom Domain: ${custom_domain}" >> /var/log/user-data.log
echo "Configuration Status: SUCCESS" >> /var/log/user-data.log

# Verify Apache is running
if systemctl is-active --quiet httpd; then
    echo "$(date): Apache HTTPS service is running successfully" >> /var/log/user-data.log
else
    echo "$(date): ERROR - Apache HTTPS service failed to start" >> /var/log/user-data.log
    systemctl status httpd >> /var/log/user-data.log
fi