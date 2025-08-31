<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Visual Infrastructure Demo</title>
    <style>
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            margin: 0;
            padding: 40px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
        }
        .container {
            max-width: 800px;
            background: white;
            padding: 40px;
            border-radius: 15px;
            box-shadow: 0 20px 40px rgba(0, 0, 0, 0.1);
            text-align: center;
        }
        h1 {
            color: #333;
            margin-bottom: 20px;
            font-size: 2.5em;
        }
        .success {
            color: #4CAF50;
            font-size: 1.2em;
            margin: 20px 0;
        }
        .info-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 20px;
            margin: 30px 0;
        }
        .info-card {
            background: #f8f9fa;
            padding: 20px;
            border-radius: 10px;
            border-left: 4px solid #667eea;
        }
        .info-card h3 {
            margin: 0 0 10px 0;
            color: #333;
        }
        .info-card p {
            margin: 0;
            color: #666;
            font-family: 'Courier New', monospace;
            font-size: 0.9em;
            word-break: break-all;
        }
        .badge {
            display: inline-block;
            background: #667eea;
            color: white;
            padding: 5px 15px;
            border-radius: 20px;
            font-size: 0.9em;
            margin: 5px;
        }
        .footer {
            margin-top: 30px;
            padding-top: 20px;
            border-top: 1px solid #eee;
            color: #666;
            font-size: 0.9em;
        }
        .terraform-icon {
            font-size: 3em;
            margin-bottom: 20px;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="terraform-icon">🏗️</div>
        <h1>🎉 Infrastructure Deployment Successful!</h1>
        <p class="success">This website was deployed using Terraform Infrastructure as Code!</p>
        <p>Your visual infrastructure design concept has been successfully implemented and is now live, serving content from AWS S3.</p>
        
        <div class="info-grid">
            <div class="info-card">
                <h3>🌐 Website URL</h3>
                <p>${website_url}</p>
            </div>
            <div class="info-card">
                <h3>📦 S3 Bucket</h3>
                <p>${bucket_name}</p>
            </div>
            <div class="info-card">
                <h3>🌍 AWS Region</h3>
                <p>${region}</p>
            </div>
        </div>

        <div style="margin: 30px 0;">
            <span class="badge">AWS S3</span>
            <span class="badge">Static Website</span>
            <span class="badge">Terraform</span>
            <span class="badge">Infrastructure as Code</span>
        </div>

        <div style="background: #e8f5e8; padding: 20px; border-radius: 10px; margin: 20px 0;">
            <h3 style="color: #2e7d32; margin-top: 0;">✅ What's Working</h3>
            <ul style="text-align: left; color: #2e7d32;">
                <li>S3 bucket configured for static website hosting</li>
                <li>Public read access enabled via bucket policy</li>
                <li>Custom index and error pages configured</li>
                <li>Server-side encryption enabled (AES256)</li>
                <li>Resource tagging and organization applied</li>
            </ul>
        </div>

        <div class="footer">
            <p><strong>Next Steps:</strong></p>
            <ul style="text-align: left; display: inline-block;">
                <li>Upload your own content to the S3 bucket</li>
                <li>Consider adding CloudFront for global distribution</li>
                <li>Implement CI/CD for automated deployments</li>
                <li>Enable monitoring and alerting</li>
            </ul>
            <p style="margin-top: 20px;">
                <em>This infrastructure demonstrates the same result that could be achieved through AWS Infrastructure Composer's visual design interface, but deployed via Terraform for version control and automation.</em>
            </p>
        </div>
    </div>
</body>
</html>