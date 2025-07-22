<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Global Content Delivery Infrastructure - ${environment}</title>
    <style>
        body {
            font-family: 'Arial', sans-serif;
            margin: 0;
            padding: 20px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            min-height: 100vh;
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
            padding: 40px 20px;
        }
        .header {
            text-align: center;
            margin-bottom: 40px;
        }
        .header h1 {
            font-size: 2.5em;
            margin-bottom: 10px;
            text-shadow: 2px 2px 4px rgba(0,0,0,0.3);
        }
        .header p {
            font-size: 1.2em;
            opacity: 0.9;
        }
        .info-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 20px;
            margin-bottom: 40px;
        }
        .info-card {
            background: rgba(255, 255, 255, 0.1);
            backdrop-filter: blur(10px);
            border-radius: 15px;
            padding: 25px;
            border: 1px solid rgba(255, 255, 255, 0.2);
        }
        .info-card h3 {
            margin-top: 0;
            color: #fff;
            font-size: 1.3em;
        }
        .info-card p {
            margin: 5px 0;
            opacity: 0.9;
        }
        .files-section {
            background: rgba(255, 255, 255, 0.1);
            backdrop-filter: blur(10px);
            border-radius: 15px;
            padding: 30px;
            margin-top: 30px;
            border: 1px solid rgba(255, 255, 255, 0.2);
        }
        .files-section h3 {
            margin-top: 0;
            color: #fff;
            font-size: 1.5em;
            text-align: center;
            margin-bottom: 20px;
        }
        .file-links {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 15px;
        }
        .file-link {
            background: rgba(255, 255, 255, 0.2);
            padding: 15px;
            border-radius: 10px;
            text-align: center;
            text-decoration: none;
            color: white;
            transition: all 0.3s ease;
            border: 1px solid rgba(255, 255, 255, 0.3);
        }
        .file-link:hover {
            background: rgba(255, 255, 255, 0.3);
            transform: translateY(-2px);
            box-shadow: 0 5px 15px rgba(0,0,0,0.3);
        }
        .footer {
            text-align: center;
            margin-top: 40px;
            padding-top: 20px;
            border-top: 1px solid rgba(255, 255, 255, 0.3);
            opacity: 0.8;
        }
        .status-indicator {
            display: inline-block;
            width: 12px;
            height: 12px;
            background: #4CAF50;
            border-radius: 50%;
            margin-right: 8px;
            animation: pulse 2s infinite;
        }
        @keyframes pulse {
            0% { opacity: 1; }
            50% { opacity: 0.5; }
            100% { opacity: 1; }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🌐 Global Content Delivery Infrastructure</h1>
            <p>Powered by Google Cloud WAN and Anywhere Cache</p>
        </div>

        <div class="info-grid">
            <div class="info-card">
                <h3>🚀 Infrastructure Status</h3>
                <p><span class="status-indicator"></span>Status: Active</p>
                <p><strong>Environment:</strong> ${environment}</p>
                <p><strong>Storage Bucket:</strong> ${bucket_name}</p>
                <p><strong>Generated:</strong> ${timestamp}</p>
            </div>

            <div class="info-card">
                <h3>🏗️ Architecture Components</h3>
                <p>✅ Multi-region Cloud Storage</p>
                <p>⚡ Anywhere Cache (SSD-backed)</p>
                <p>🌍 Global Load Balancer</p>
                <p>🔥 Cloud CDN Edge Caching</p>
                <p>📊 Cloud Monitoring</p>
            </div>

            <div class="info-card">
                <h3>🌏 Global Regions</h3>
                <p>🇺🇸 <strong>Americas:</strong> us-central1</p>
                <p>🇪🇺 <strong>EMEA:</strong> europe-west1</p>
                <p>🇦🇺 <strong>APAC:</strong> asia-east1</p>
                <p>📡 <strong>WAN Backbone:</strong> Google Global Network</p>
            </div>

            <div class="info-card">
                <h3>⚡ Performance Features</h3>
                <p>🏎️ Up to 40% faster delivery</p>
                <p>💰 40% cost reduction potential</p>
                <p>🗄️ 2.5 TB/s cache throughput</p>
                <p>🌐 100+ CDN edge locations</p>
                <p>🔄 Intelligent cache admission</p>
            </div>
        </div>

        <div class="files-section">
            <h3>📁 Test Content Files</h3>
            <div class="file-links">
                <a href="/small-file.dat" class="file-link">
                    <strong>Small File</strong><br>
                    <small>1 MB Test File</small>
                </a>
                <a href="/medium-file.dat" class="file-link">
                    <strong>Medium File</strong><br>
                    <small>10 MB Test File</small>
                </a>
                <a href="/large-file.dat" class="file-link">
                    <strong>Large File</strong><br>
                    <small>100 MB Test File</small>
                </a>
            </div>
        </div>

        <div class="footer">
            <p>🔧 <strong>Recipe:</strong> Establishing Global Content Delivery Infrastructure with Cloud WAN and Anywhere Cache</p>
            <p>☁️ <strong>Provider:</strong> Google Cloud Platform</p>
            <p>🏷️ <strong>Services:</strong> Cloud WAN, Cloud Storage, Cloud Monitoring, Cloud CDN</p>
        </div>
    </div>

    <script>
        // Add some interactivity
        document.addEventListener('DOMContentLoaded', function() {
            // Animate cards on load
            const cards = document.querySelectorAll('.info-card');
            cards.forEach((card, index) => {
                card.style.opacity = '0';
                card.style.transform = 'translateY(20px)';
                setTimeout(() => {
                    card.style.transition = 'all 0.6s ease';
                    card.style.opacity = '1';
                    card.style.transform = 'translateY(0)';
                }, index * 200);
            });

            // Add click tracking for file downloads
            const fileLinks = document.querySelectorAll('.file-link');
            fileLinks.forEach(link => {
                link.addEventListener('click', function(e) {
                    console.log('Downloading:', this.href);
                    // You could add analytics tracking here
                });
            });
        });
    </script>
</body>
</html>