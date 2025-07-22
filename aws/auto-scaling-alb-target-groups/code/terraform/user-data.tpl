#!/bin/bash

# Update system packages
yum update -y

# Install Apache HTTP Server
yum install -y httpd

# Start and enable Apache
systemctl start httpd
systemctl enable httpd

# Create a comprehensive demo web page with instance metadata and load testing
cat > /var/www/html/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Auto Scaling Demo - ${project_name}</title>
    <style>
        body {
            font-family: 'Arial', sans-serif;
            margin: 0;
            padding: 20px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: #333;
            min-height: 100vh;
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
            background: white;
            border-radius: 15px;
            box-shadow: 0 20px 40px rgba(0,0,0,0.1);
            overflow: hidden;
        }
        .header {
            background: linear-gradient(135deg, #ff6b6b 0%, #ee5a24 100%);
            color: white;
            padding: 30px;
            text-align: center;
        }
        .header h1 {
            margin: 0;
            font-size: 2.5em;
            font-weight: 300;
        }
        .header p {
            margin: 10px 0 0 0;
            opacity: 0.9;
            font-size: 1.1em;
        }
        .content {
            padding: 30px;
        }
        .grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(350px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        .card {
            background: #f8f9fa;
            border-radius: 10px;
            padding: 25px;
            box-shadow: 0 5px 15px rgba(0,0,0,0.05);
            transition: transform 0.3s ease;
        }
        .card:hover {
            transform: translateY(-5px);
        }
        .card h3 {
            margin: 0 0 15px 0;
            color: #2c3e50;
            border-bottom: 2px solid #3498db;
            padding-bottom: 10px;
        }
        .metric-item {
            display: flex;
            justify-content: space-between;
            margin: 10px 0;
            padding: 8px 0;
            border-bottom: 1px solid #e9ecef;
        }
        .metric-label {
            font-weight: bold;
            color: #495057;
        }
        .metric-value {
            color: #007bff;
            font-family: 'Courier New', monospace;
        }
        .load-test-section {
            background: linear-gradient(135deg, #74b9ff 0%, #0984e3 100%);
            color: white;
            border-radius: 10px;
            padding: 25px;
            margin-top: 20px;
        }
        .load-test-section h3 {
            margin: 0 0 20px 0;
            border-bottom: 2px solid rgba(255,255,255,0.3);
            padding-bottom: 10px;
        }
        .button-group {
            display: flex;
            gap: 15px;
            flex-wrap: wrap;
        }
        .btn {
            background: rgba(255,255,255,0.2);
            color: white;
            border: 2px solid rgba(255,255,255,0.3);
            padding: 12px 24px;
            border-radius: 25px;
            cursor: pointer;
            font-size: 16px;
            transition: all 0.3s ease;
            text-decoration: none;
            display: inline-block;
        }
        .btn:hover {
            background: rgba(255,255,255,0.3);
            border-color: rgba(255,255,255,0.5);
            transform: translateY(-2px);
        }
        .btn:disabled {
            opacity: 0.6;
            cursor: not-allowed;
            transform: none;
        }
        .status {
            margin-top: 15px;
            padding: 10px 15px;
            border-radius: 5px;
            background: rgba(255,255,255,0.1);
            border-left: 4px solid #00b894;
        }
        .loading {
            display: inline-block;
            width: 20px;
            height: 20px;
            border: 3px solid rgba(255,255,255,0.3);
            border-radius: 50%;
            border-top-color: white;
            animation: spin 1s ease-in-out infinite;
        }
        @keyframes spin {
            to { transform: rotate(360deg); }
        }
        .footer {
            background: #2c3e50;
            color: white;
            padding: 20px 30px;
            text-align: center;
        }
        .environment-badge {
            background: #00b894;
            color: white;
            padding: 5px 15px;
            border-radius: 20px;
            font-size: 0.9em;
            display: inline-block;
            margin-top: 10px;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🚀 Auto Scaling Demo</h1>
            <p>High-Performance Web Application with Intelligent Scaling</p>
            <div class="environment-badge">Environment: ${environment}</div>
        </div>
        
        <div class="content">
            <div class="grid">
                <div class="card">
                    <h3>📊 Instance Information</h3>
                    <div class="metric-item">
                        <span class="metric-label">Instance ID:</span>
                        <span class="metric-value" id="instance-id">Loading...</span>
                    </div>
                    <div class="metric-item">
                        <span class="metric-label">Availability Zone:</span>
                        <span class="metric-value" id="az">Loading...</span>
                    </div>
                    <div class="metric-item">
                        <span class="metric-label">Instance Type:</span>
                        <span class="metric-value" id="instance-type">Loading...</span>
                    </div>
                    <div class="metric-item">
                        <span class="metric-label">Private IP:</span>
                        <span class="metric-value" id="local-ip">Loading...</span>
                    </div>
                    <div class="metric-item">
                        <span class="metric-label">Public IP:</span>
                        <span class="metric-value" id="public-ip">Loading...</span>
                    </div>
                    <div class="metric-item">
                        <span class="metric-label">Server Time:</span>
                        <span class="metric-value" id="server-time">Loading...</span>
                    </div>
                </div>
                
                <div class="card">
                    <h3>🎯 Load Balancer Info</h3>
                    <div class="metric-item">
                        <span class="metric-label">Request Count:</span>
                        <span class="metric-value" id="request-count">0</span>
                    </div>
                    <div class="metric-item">
                        <span class="metric-label">Session ID:</span>
                        <span class="metric-value" id="session-id">N/A</span>
                    </div>
                    <div class="metric-item">
                        <span class="metric-label">Load Balancer IP:</span>
                        <span class="metric-value" id="lb-ip">Detecting...</span>
                    </div>
                    <div class="metric-item">
                        <span class="metric-label">Response Time:</span>
                        <span class="metric-value" id="response-time">N/A</span>
                    </div>
                </div>
            </div>
            
            <div class="load-test-section">
                <h3>⚡ Auto Scaling Load Tests</h3>
                <p>Use these tests to trigger auto scaling events and observe the infrastructure response:</p>
                
                <div class="button-group">
                    <button class="btn" onclick="generateCPULoad(30)">
                        🔥 CPU Load (30s)
                    </button>
                    <button class="btn" onclick="generateCPULoad(60)">
                        🔥 CPU Load (60s)
                    </button>
                    <button class="btn" onclick="generateMemoryLoad()">
                        💾 Memory Load
                    </button>
                    <button class="btn" onclick="generateNetworkLoad()">
                        🌐 Network Load
                    </button>
                    <button class="btn" onclick="simulateTraffic()">
                        📈 Traffic Simulation
                    </button>
                </div>
                
                <div class="status" id="load-status">
                    <strong>Status:</strong> Ready to test auto scaling
                </div>
            </div>
        </div>
        
        <div class="footer">
            <p>Powered by AWS Auto Scaling • ALB • Target Groups • CloudWatch</p>
            <small>This demo showcases intelligent infrastructure scaling based on demand</small>
        </div>
    </div>

    <script>
        let requestCount = 0;
        let sessionId = generateSessionId();
        
        // Generate a unique session ID
        function generateSessionId() {
            return 'session-' + Math.random().toString(36).substr(2, 9);
        }
        
        // Fetch instance metadata from EC2 metadata service
        async function fetchMetadata() {
            try {
                // Get IMDSv2 token
                const tokenResponse = await fetch('http://169.254.169.254/latest/api/token', {
                    method: 'PUT',
                    headers: {
                        'X-aws-ec2-metadata-token-ttl-seconds': '21600'
                    }
                });
                
                if (!tokenResponse.ok) {
                    throw new Error('Failed to get metadata token');
                }
                
                const token = await tokenResponse.text();
                const headers = {
                    'X-aws-ec2-metadata-token': token
                };
                
                // Fetch metadata with token
                const [instanceId, az, instanceType, localIp, publicIp] = await Promise.all([
                    fetch('http://169.254.169.254/latest/meta-data/instance-id', { headers }).then(r => r.text()),
                    fetch('http://169.254.169.254/latest/meta-data/placement/availability-zone', { headers }).then(r => r.text()),
                    fetch('http://169.254.169.254/latest/meta-data/instance-type', { headers }).then(r => r.text()),
                    fetch('http://169.254.169.254/latest/meta-data/local-ipv4', { headers }).then(r => r.text()),
                    fetch('http://169.254.169.254/latest/meta-data/public-ipv4', { headers }).then(r => r.text()).catch(() => 'N/A')
                ]);
                
                document.getElementById('instance-id').textContent = instanceId;
                document.getElementById('az').textContent = az;
                document.getElementById('instance-type').textContent = instanceType;
                document.getElementById('local-ip').textContent = localIp;
                document.getElementById('public-ip').textContent = publicIp;
                
            } catch (error) {
                console.error('Error fetching metadata:', error);
                document.getElementById('instance-id').textContent = 'Error loading';
                document.getElementById('az').textContent = 'Error loading';
                document.getElementById('instance-type').textContent = 'Error loading';
                document.getElementById('local-ip').textContent = 'Error loading';
                document.getElementById('public-ip').textContent = 'Error loading';
            }
        }
        
        // Generate CPU load for testing auto scaling
        function generateCPULoad(duration) {
            const statusElement = document.getElementById('load-status');
            const allButtons = document.querySelectorAll('.btn');
            
            // Disable all buttons during load test
            allButtons.forEach(btn => btn.disabled = true);
            
            statusElement.innerHTML = `
                <div class="loading"></div>
                <strong>Status:</strong> Generating high CPU load for ${duration} seconds...
            `;
            
            // Create CPU-intensive workers
            const numWorkers = navigator.hardwareConcurrency || 4;
            const workers = [];
            
            for (let i = 0; i < numWorkers; i++) {
                const workerCode = `
                    let startTime = Date.now();
                    let iterations = 0;
                    while (Date.now() - startTime < ${duration * 1000}) {
                        // CPU intensive calculation
                        Math.sqrt(Math.random() * 1000000);
                        iterations++;
                        
                        // Allow other tasks to run occasionally
                        if (iterations % 10000 === 0) {
                            postMessage({type: 'progress', iterations: iterations});
                        }
                    }
                    postMessage({type: 'complete', iterations: iterations});
                `;
                
                const blob = new Blob([workerCode], { type: 'application/javascript' });
                const worker = new Worker(URL.createObjectURL(blob));
                workers.push(worker);
            }
            
            let completedWorkers = 0;
            workers.forEach(worker => {
                worker.onmessage = function(e) {
                    if (e.data.type === 'complete') {
                        completedWorkers++;
                        if (completedWorkers === workers.length) {
                            // All workers completed
                            workers.forEach(w => w.terminate());
                            statusElement.innerHTML = `
                                <strong>Status:</strong> CPU load test completed. Monitor CloudWatch for scaling events.
                            `;
                            allButtons.forEach(btn => btn.disabled = false);
                        }
                    }
                };
            });
        }
        
        // Generate memory load
        function generateMemoryLoad() {
            const statusElement = document.getElementById('load-status');
            const allButtons = document.querySelectorAll('.btn');
            
            allButtons.forEach(btn => btn.disabled = true);
            statusElement.innerHTML = `
                <div class="loading"></div>
                <strong>Status:</strong> Generating memory pressure...
            `;
            
            // Allocate large arrays to consume memory
            const arrays = [];
            try {
                for (let i = 0; i < 100; i++) {
                    arrays.push(new Array(1000000).fill(Math.random()));
                }
                
                setTimeout(() => {
                    // Release memory
                    arrays.length = 0;
                    statusElement.innerHTML = `
                        <strong>Status:</strong> Memory load test completed.
                    `;
                    allButtons.forEach(btn => btn.disabled = false);
                }, 30000);
                
            } catch (error) {
                statusElement.innerHTML = `
                    <strong>Status:</strong> Memory load test completed (limit reached).
                `;
                allButtons.forEach(btn => btn.disabled = false);
            }
        }
        
        // Generate network load
        function generateNetworkLoad() {
            const statusElement = document.getElementById('load-status');
            const allButtons = document.querySelectorAll('.btn');
            
            allButtons.forEach(btn => btn.disabled = true);
            statusElement.innerHTML = `
                <div class="loading"></div>
                <strong>Status:</strong> Generating network load...
            `;
            
            let requestsMade = 0;
            const maxRequests = 100;
            
            function makeRequest() {
                if (requestsMade >= maxRequests) {
                    statusElement.innerHTML = `
                        <strong>Status:</strong> Network load test completed (${requestsMade} requests).
                    `;
                    allButtons.forEach(btn => btn.disabled = false);
                    return;
                }
                
                fetch(window.location.href + '?t=' + Date.now())
                    .then(() => {
                        requestsMade++;
                        updateRequestCount();
                        if (requestsMade < maxRequests) {
                            setTimeout(makeRequest, 100); // 10 requests per second
                        } else {
                            statusElement.innerHTML = `
                                <strong>Status:</strong> Network load test completed (${requestsMade} requests).
                            `;
                            allButtons.forEach(btn => btn.disabled = false);
                        }
                    })
                    .catch(() => {
                        requestsMade++;
                        if (requestsMade < maxRequests) {
                            setTimeout(makeRequest, 100);
                        }
                    });
            }
            
            makeRequest();
        }
        
        // Simulate traffic patterns
        function simulateTraffic() {
            const statusElement = document.getElementById('load-status');
            const allButtons = document.querySelectorAll('.btn');
            
            allButtons.forEach(btn => btn.disabled = true);
            statusElement.innerHTML = `
                <div class="loading"></div>
                <strong>Status:</strong> Simulating traffic spike...
            `;
            
            // Combine CPU and network load
            generateCPULoad(45);
            setTimeout(() => {
                generateNetworkLoad();
            }, 5000);
            
            setTimeout(() => {
                statusElement.innerHTML = `
                    <strong>Status:</strong> Traffic simulation completed. Check Auto Scaling activity.
                `;
                allButtons.forEach(btn => btn.disabled = false);
            }, 60000);
        }
        
        // Update request counter
        function updateRequestCount() {
            requestCount++;
            document.getElementById('request-count').textContent = requestCount;
        }
        
        // Update server time
        function updateTime() {
            const now = new Date();
            document.getElementById('server-time').textContent = now.toLocaleString();
        }
        
        // Detect load balancer information
        function detectLoadBalancer() {
            // Get forwarded IP headers if available
            const forwardedFor = getHeaderValue('x-forwarded-for');
            if (forwardedFor) {
                document.getElementById('lb-ip').textContent = forwardedFor.split(',')[0];
            }
            
            document.getElementById('session-id').textContent = sessionId;
        }
        
        // Helper function to get header values (simulated)
        function getHeaderValue(headerName) {
            // In a real application, this would come from server-side processing
            return null;
        }
        
        // Track performance
        function trackPerformance() {
            const startTime = performance.now();
            
            fetch(window.location.href + '?performance=1')
                .then(() => {
                    const endTime = performance.now();
                    const responseTime = Math.round(endTime - startTime);
                    document.getElementById('response-time').textContent = responseTime + 'ms';
                })
                .catch(() => {
                    document.getElementById('response-time').textContent = 'Error';
                });
        }
        
        // Initialize the page
        function init() {
            fetchMetadata();
            detectLoadBalancer();
            updateTime();
            trackPerformance();
            
            // Update time every second
            setInterval(updateTime, 1000);
            
            // Track performance periodically
            setInterval(trackPerformance, 30000);
        }
        
        // Start initialization when page loads
        document.addEventListener('DOMContentLoaded', init);
        
        // Track page loads
        updateRequestCount();
    </script>
</body>
</html>
EOF

# Set proper permissions
chown apache:apache /var/www/html/index.html
chmod 644 /var/www/html/index.html

# Configure Apache for better performance
cat >> /etc/httpd/conf/httpd.conf << 'EOF'

# Performance optimizations for auto scaling demo
KeepAlive On
MaxKeepAliveRequests 100
KeepAliveTimeout 15

# Enable compression
LoadModule deflate_module modules/mod_deflate.so
<Location />
    SetOutputFilter DEFLATE
    SetEnvIfNoCase Request_URI \
        \.(?:gif|jpe?g|png)$ no-gzip dont-vary
    SetEnvIfNoCase Request_URI \
        \.(?:exe|t?gz|zip|bz2|sit|rar)$ no-gzip dont-vary
</Location>

# Security headers
Header always set X-Content-Type-Options nosniff
Header always set X-Frame-Options DENY
Header always set X-XSS-Protection "1; mode=block"
Header always set Strict-Transport-Security "max-age=63072000; includeSubDomains; preload"

# Cache static content
<LocationMatch "\.(css|js|png|jpg|jpeg|gif|ico|svg)$">
    ExpiresActive On
    ExpiresDefault "access plus 1 month"
</LocationMatch>
EOF

# Enable mod_headers for security headers
sed -i 's/#LoadModule headers_module/LoadModule headers_module/' /etc/httpd/conf/httpd.conf

# Create a health check endpoint
cat > /var/www/html/health << 'EOF'
OK
EOF

# Create a simple API endpoint for load testing
mkdir -p /var/www/html/api
cat > /var/www/html/api/status << 'EOF'
{
    "status": "healthy",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "project": "${project_name}",
    "environment": "${environment}",
    "server": "$(hostname)"
}
EOF

# Install CloudWatch agent for enhanced monitoring (optional)
yum install -y amazon-cloudwatch-agent

# Create CloudWatch agent configuration
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'EOF'
{
    "metrics": {
        "namespace": "AutoScaling/Demo",
        "metrics_collected": {
            "cpu": {
                "measurement": [
                    "cpu_usage_idle",
                    "cpu_usage_iowait",
                    "cpu_usage_user",
                    "cpu_usage_system"
                ],
                "metrics_collection_interval": 60
            },
            "disk": {
                "measurement": [
                    "used_percent"
                ],
                "metrics_collection_interval": 60,
                "resources": [
                    "*"
                ]
            },
            "diskio": {
                "measurement": [
                    "io_time"
                ],
                "metrics_collection_interval": 60,
                "resources": [
                    "*"
                ]
            },
            "mem": {
                "measurement": [
                    "mem_used_percent"
                ],
                "metrics_collection_interval": 60
            },
            "netstat": {
                "measurement": [
                    "tcp_established",
                    "tcp_time_wait"
                ],
                "metrics_collection_interval": 60
            }
        }
    },
    "logs": {
        "logs_collected": {
            "files": {
                "collect_list": [
                    {
                        "file_path": "/var/log/httpd/access_log",
                        "log_group_name": "/aws/autoscaling/demo/apache/access",
                        "log_stream_name": "{instance_id}",
                        "timestamp_format": "%d/%b/%Y:%H:%M:%S %z"
                    },
                    {
                        "file_path": "/var/log/httpd/error_log",
                        "log_group_name": "/aws/autoscaling/demo/apache/error",
                        "log_stream_name": "{instance_id}",
                        "timestamp_format": "%d/%b/%Y:%H:%M:%S %z"
                    }
                ]
            }
        }
    }
}
EOF

# Start CloudWatch agent
systemctl enable amazon-cloudwatch-agent
systemctl start amazon-cloudwatch-agent

# Restart Apache to apply all changes
systemctl restart httpd

# Enable automatic security updates
yum install -y yum-cron
systemctl enable yum-cron
systemctl start yum-cron

# Log completion
echo "$(date): Auto Scaling demo web server setup completed successfully" >> /var/log/user-data.log
echo "Project: ${project_name}, Environment: ${environment}" >> /var/log/user-data.log

# Signal that the instance is ready (this would typically be used with CloudFormation)
# For Terraform, we rely on health checks to determine readiness