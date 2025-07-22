<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>XR Experience Platform</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
        }
        
        .container {
            background: rgba(255, 255, 255, 0.95);
            border-radius: 20px;
            padding: 40px;
            box-shadow: 0 20px 40px rgba(0, 0, 0, 0.1);
            text-align: center;
            max-width: 600px;
            width: 90%;
        }
        
        h1 {
            color: #333;
            margin-bottom: 20px;
            font-size: 2.5em;
            font-weight: 700;
        }
        
        .subtitle {
            color: #666;
            margin-bottom: 30px;
            font-size: 1.2em;
        }
        
        .info-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        
        .info-card {
            background: #f8f9fa;
            padding: 20px;
            border-radius: 10px;
            border-left: 4px solid #667eea;
        }
        
        .info-label {
            font-weight: bold;
            color: #333;
            margin-bottom: 5px;
        }
        
        .info-value {
            color: #666;
            font-family: monospace;
            font-size: 0.9em;
        }
        
        #xr-container {
            width: 100%;
            height: 400px;
            background: #f0f0f0;
            border-radius: 15px;
            position: relative;
            margin: 20px 0;
            border: 2px dashed #ccc;
            display: flex;
            align-items: center;
            justify-content: center;
        }
        
        #loading {
            color: #666;
            font-size: 1.1em;
        }
        
        .controls {
            display: flex;
            gap: 15px;
            justify-content: center;
            flex-wrap: wrap;
            margin-top: 20px;
        }
        
        button {
            padding: 12px 24px;
            border: none;
            border-radius: 25px;
            cursor: pointer;
            font-size: 1em;
            font-weight: 600;
            transition: all 0.3s ease;
            min-width: 120px;
        }
        
        .btn-primary {
            background: linear-gradient(135deg, #667eea, #764ba2);
            color: white;
        }
        
        .btn-secondary {
            background: #f8f9fa;
            color: #333;
            border: 2px solid #ddd;
        }
        
        button:hover {
            transform: translateY(-2px);
            box-shadow: 0 5px 15px rgba(0, 0, 0, 0.2);
        }
        
        .btn-primary:hover {
            background: linear-gradient(135deg, #764ba2, #667eea);
        }
        
        .btn-secondary:hover {
            background: #e9ecef;
        }
        
        .status {
            margin-top: 20px;
            padding: 10px;
            border-radius: 5px;
            font-weight: bold;
        }
        
        .status.success {
            background: #d4edda;
            color: #155724;
            border: 1px solid #c3e6cb;
        }
        
        .status.error {
            background: #f8d7da;
            color: #721c24;
            border: 1px solid #f5c6cb;
        }
        
        .status.info {
            background: #cce7f0;
            color: #0c5460;
            border: 1px solid #bee5eb;
        }
        
        @media (max-width: 768px) {
            .container {
                padding: 20px;
                width: 95%;
            }
            
            h1 {
                font-size: 2em;
            }
            
            .controls {
                flex-direction: column;
                align-items: center;
            }
            
            button {
                width: 100%;
                max-width: 250px;
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🥽 XR Experience Platform</h1>
        <p class="subtitle">Powered by Google Cloud Immersive Stream for XR</p>
        
        <div class="info-grid">
            <div class="info-card">
                <div class="info-label">Project ID</div>
                <div class="info-value">${project_id}</div>
            </div>
            <div class="info-card">
                <div class="info-label">Environment</div>
                <div class="info-value">${environment}</div>
            </div>
            <div class="info-card">
                <div class="info-label">CDN Endpoint</div>
                <div class="info-value">${cdn_endpoint}</div>
            </div>
        </div>
        
        <div id="xr-container">
            <div id="loading">🚀 Ready to launch XR experience...</div>
        </div>
        
        <div class="controls">
            <button class="btn-primary" onclick="startXR()">Start XR Session</button>
            <button class="btn-secondary" onclick="toggleAR()">Toggle AR Mode</button>
            <button class="btn-secondary" onclick="resetView()">Reset View</button>
            <button class="btn-secondary" onclick="loadConfig()">Load Config</button>
        </div>
        
        <div id="status" class="status" style="display: none;"></div>
        
        <div style="margin-top: 30px; color: #666; font-size: 0.9em;">
            <p>This is a demo XR platform showcasing Google Cloud's Immersive Stream for XR capabilities.</p>
            <p>For production use, integrate with your actual XR streaming service endpoints.</p>
        </div>
    </div>
    
    <script src="xr-client.js"></script>
    <script>
        // Initialize platform info
        window.platformConfig = {
            projectId: '${project_id}',
            environment: '${environment}',
            cdnEndpoint: '${cdn_endpoint}'
        };
    </script>
</body>
</html>