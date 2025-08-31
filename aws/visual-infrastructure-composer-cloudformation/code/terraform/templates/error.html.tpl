<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Page Not Found - Visual Infrastructure Demo</title>
    <style>
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            margin: 0;
            padding: 40px;
            background: linear-gradient(135deg, #ff6b6b 0%, #ee5a24 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
        }
        .container {
            max-width: 600px;
            background: white;
            padding: 40px;
            border-radius: 15px;
            box-shadow: 0 20px 40px rgba(0, 0, 0, 0.1);
            text-align: center;
        }
        h1 {
            color: #333;
            margin-bottom: 20px;
            font-size: 3em;
        }
        .error-code {
            font-size: 6em;
            color: #ff6b6b;
            margin: 20px 0;
            font-weight: bold;
        }
        .error-message {
            color: #666;
            font-size: 1.2em;
            margin: 20px 0;
        }
        .info-card {
            background: #f8f9fa;
            padding: 20px;
            border-radius: 10px;
            border-left: 4px solid #ff6b6b;
            margin: 20px 0;
        }
        .info-card p {
            margin: 0;
            color: #666;
            font-family: 'Courier New', monospace;
            font-size: 0.9em;
            word-break: break-all;
        }
        .back-button {
            display: inline-block;
            background: #ff6b6b;
            color: white;
            padding: 15px 30px;
            border-radius: 25px;
            text-decoration: none;
            font-weight: bold;
            margin-top: 20px;
            transition: background 0.3s ease;
        }
        .back-button:hover {
            background: #ee5a24;
        }
        .footer {
            margin-top: 30px;
            padding-top: 20px;
            border-top: 1px solid #eee;
            color: #666;
            font-size: 0.9em;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="error-code">404</div>
        <h1>Page Not Found</h1>
        <p class="error-message">
            Oops! The page you're looking for doesn't exist on this website.
        </p>
        
        <div class="info-card">
            <h3 style="margin: 0 0 10px 0; color: #333;">🏠 Return to Homepage</h3>
            <p>${website_url}</p>
        </div>

        <a href="${website_url}" class="back-button">← Go Back Home</a>

        <div class="footer">
            <p><strong>About This Error Page:</strong></p>
            <p>This custom 404 error page is served from S3 bucket: <code>${bucket_name}</code></p>
            <p style="margin-top: 15px;">
                <em>This infrastructure was deployed using Terraform, demonstrating the same capabilities that could be achieved through AWS Infrastructure Composer's visual design interface.</em>
            </p>
        </div>
    </div>
</body>
</html>