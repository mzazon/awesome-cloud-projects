<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>${app_name} - App Engine Web Application</title>
    <link rel="stylesheet" href="{{ url_for('static', filename='style.css') }}">
    <link rel="icon" type="image/x-icon" href="data:image/x-icon;base64,AAABAAEAEBAAAAEAIABoBAAAFgAAACgAAAAQAAAAIAAAAAEAIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAP//AP//AP//AP//AP//AP//AP//AP//AP//AP//AP//AP//AP//AP//AP//AP//AP//AP//AP//AP//AO7u7v/u7u7/7u7u/+7u7v/u7u7/7u7u/+7u7v/u7u7/7u7u/+7u7v/u7u7/7u7u/+7u7v/7u7u/+7u7v/u7u7/7u7u/+7u7v/u7u7/7u7u/+7u7v/u7u7/7u7u/+7u7v/u7u7/7u7u/+7u7v/u7u7/7u7u/+7u7v/u7u7/7u7u/+7u7v/u7u7/7u7u/+7u7v/u7u7/7u7u/+7u7v/u7u7/7u7u/+7u7v/u7u7/7u7u/+7u7v/u7u7/7u7u/+7u7v/u7u7/7u7u/+7u7v/u7u7/7u7u/+7u7v/u7u7/7u7u/+7u7v/u7u7/7u7u/+7u7v/u7u7/7u7u/+7u7v/u7u7/7u7u/+7u7v/u7u7/7u7u/+7u7v/u7u7/7u7u/+7u7v/u7u7/7u7u/+7u7v/u7u7/7u7u/+7u7v/u7u7/7u7u/+7u7v/u7u7/7u7u/+7u7v/u7u7/7u7u/+7u7v/u7u7/7u7u/+7u7v/u7u7/7u7u/+7u7v/u7u7/7u7u/+7u7v/u7u7/7u7u/+7u7v/u7u7/7u7u/+7u7v/u7u7/7u7u/+7u7v/u7u7/7u7u/+7u7v/u7u7/7u7u/+7u7v/u7u7/7u7u/+7u7v/u7u7/7u7u/+7u7v/u7u7/7u7u/+7u7v/u7u7/7u7u/+7u7v//wD//8A///AF//wBf/8AX//AF//wBf/8AX//AF//wBf/8AX//AF//wBf/8AX//AF//wBf/8AX//AP//wD///8A//8=">
</head>
<body>
    <div class="container">
        <header>
            <h1>🚀 Welcome to ${app_name}!</h1>
            <p class="subtitle">Your web application is running successfully on Google App Engine</p>
        </header>
        
        <main>
            <div class="info-grid">
                <div class="info-card">
                    <h3>📅 Current Time</h3>
                    <p id="current-time">{{ current_time.strftime('%Y-%m-%d %H:%M:%S UTC') }}</p>
                </div>
                
                <div class="info-card">
                    <h3>🏷️ App Version</h3>
                    <p id="app-version">{{ version }}</p>
                </div>
                
                <div class="info-card">
                    <h3>🔧 Runtime</h3>
                    <p>Python 3.12 on App Engine</p>
                </div>
                
                <div class="info-card">
                    <h3>⚡ Features</h3>
                    <p>Auto-scaling, Load Balancing, HTTPS</p>
                </div>
            </div>
            
            <div class="actions">
                <button id="health-check-btn" onclick="checkHealth()">
                    🩺 Check Application Health
                </button>
                
                <button id="app-info-btn" onclick="getAppInfo()">
                    ℹ️ Get Application Info
                </button>
            </div>
            
            <div id="status-display" class="status-display"></div>
        </main>
        
        <footer>
            <p>Deployed with ❤️ using Terraform and Google App Engine</p>
            <p class="version-info">Application: ${app_name} | Framework: Flask | Platform: Google Cloud</p>
        </footer>
    </div>
    
    <script src="{{ url_for('static', filename='script.js') }}"></script>
</body>
</html>