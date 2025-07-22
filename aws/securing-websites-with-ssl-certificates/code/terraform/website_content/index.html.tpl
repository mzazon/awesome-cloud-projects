<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Secure Static Website - ${domain_name}</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            line-height: 1.6;
            margin: 0;
            padding: 0;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
        }
        .container {
            background: white;
            padding: 3rem;
            border-radius: 10px;
            box-shadow: 0 20px 40px rgba(0,0,0,0.1);
            max-width: 600px;
            text-align: center;
        }
        .secure {
            color: #28a745;
            font-weight: bold;
            display: inline-flex;
            align-items: center;
            gap: 0.5rem;
        }
        .lock-icon {
            font-size: 1.2em;
        }
        .feature-list {
            text-align: left;
            margin: 2rem 0;
        }
        .feature-item {
            padding: 0.5rem 0;
            border-bottom: 1px solid #eee;
        }
        .feature-item:last-child {
            border-bottom: none;
        }
        .check {
            color: #28a745;
            font-weight: bold;
            margin-right: 0.5rem;
        }
        .footer {
            margin-top: 2rem;
            padding-top: 1rem;
            border-top: 1px solid #eee;
            color: #666;
            font-size: 0.9em;
        }
        .timestamp {
            font-family: monospace;
            background: #f8f9fa;
            padding: 0.2rem 0.5rem;
            border-radius: 4px;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>Welcome to Your <span class="secure"><span class="lock-icon">🔒</span>Secure</span> Website</h1>
        <p>This website is served over HTTPS using <strong>AWS Certificate Manager</strong> and <strong>CloudFront CDN</strong>.</p>
        
        <div class="feature-list">
            <div class="feature-item">
                <span class="check">✅</span>
                <strong>SSL/TLS Certificate:</strong> Automatically managed by AWS ACM
            </div>
            <div class="feature-item">
                <span class="check">✅</span>
                <strong>Global CDN:</strong> Content delivered from AWS edge locations
            </div>
            <div class="feature-item">
                <span class="check">✅</span>
                <strong>HTTPS Redirect:</strong> All HTTP traffic automatically redirected to HTTPS
            </div>
            <div class="feature-item">
                <span class="check">✅</span>
                <strong>Origin Access Control:</strong> S3 bucket secured from direct access
            </div>
            <div class="feature-item">
                <span class="check">✅</span>
                <strong>Auto-Renewal:</strong> Certificate automatically renewed before expiration
            </div>
            <div class="feature-item">
                <span class="check">✅</span>
                <strong>High Availability:</strong> 99.99% SLA with AWS infrastructure
            </div>
        </div>
        
        <p><strong>Domain:</strong> <code>${domain_name}</code></p>
        <p><strong>Deployed with:</strong> Terraform Infrastructure as Code</p>
        
        <div class="footer">
            <p><strong>Deployment timestamp:</strong> <span class="timestamp">${timestamp}</span></p>
            <p>Powered by AWS Certificate Manager, CloudFront, and S3</p>
        </div>
    </div>
</body>
</html>