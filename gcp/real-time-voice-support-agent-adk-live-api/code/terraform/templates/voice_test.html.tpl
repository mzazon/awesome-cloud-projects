<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Voice Support Agent Test Interface - ${agent_name}</title>
    <style>
        body { 
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; 
            max-width: 1000px; 
            margin: 0 auto; 
            padding: 20px; 
            background-color: #f5f5f5;
            line-height: 1.6;
        }
        
        .container {
            background: white;
            padding: 30px;
            border-radius: 10px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        
        h1 {
            color: #333;
            text-align: center;
            margin-bottom: 30px;
            border-bottom: 3px solid #4285f4;
            padding-bottom: 10px;
        }
        
        .controls { 
            margin: 20px 0; 
            display: flex;
            gap: 10px;
            flex-wrap: wrap;
        }
        
        button { 
            padding: 12px 24px; 
            margin: 5px; 
            font-size: 16px;
            border: none;
            border-radius: 5px;
            cursor: pointer;
            transition: all 0.3s ease;
            font-weight: 500;
        }
        
        .primary-btn {
            background-color: #4285f4;
            color: white;
        }
        
        .secondary-btn {
            background-color: #34a853;
            color: white;
        }
        
        .info-btn {
            background-color: #fbbc04;
            color: #333;
        }
        
        button:hover {
            opacity: 0.8;
            transform: translateY(-2px);
        }
        
        button:disabled {
            background-color: #ccc;
            cursor: not-allowed;
            transform: none;
        }
        
        .status { 
            padding: 15px; 
            margin: 15px 0; 
            border-radius: 5px;
            border-left: 4px solid #4285f4;
            font-weight: 500;
        }
        
        .success { 
            background-color: #d4edda; 
            color: #155724; 
            border-left-color: #28a745;
        }
        
        .error { 
            background-color: #f8d7da; 
            color: #721c24; 
            border-left-color: #dc3545;
        }
        
        .info {
            background-color: #d1ecf1;
            color: #0c5460;
            border-left-color: #17a2b8;
        }
        
        .response { 
            background-color: #f8f9fa; 
            padding: 20px; 
            margin: 15px 0; 
            border-radius: 5px;
            border: 1px solid #dee2e6;
            font-family: 'Courier New', monospace;
            max-height: 400px;
            overflow-y: auto;
        }
        
        .response-header {
            font-weight: bold;
            color: #495057;
            margin-bottom: 10px;
            font-family: 'Segoe UI', sans-serif;
        }
        
        .json-content {
            white-space: pre-wrap;
            word-wrap: break-word;
        }
        
        .test-section {
            margin: 30px 0;
            padding: 20px;
            border: 1px solid #e9ecef;
            border-radius: 8px;
        }
        
        .test-section h3 {
            margin-top: 0;
            color: #495057;
        }
        
        .input-group {
            margin: 15px 0;
        }
        
        .input-group label {
            display: block;
            margin-bottom: 5px;
            font-weight: 500;
            color: #495057;
        }
        
        .input-group input, .input-group textarea {
            width: 100%;
            padding: 10px;
            border: 1px solid #ced4da;
            border-radius: 4px;
            font-size: 14px;
        }
        
        .input-group textarea {
            height: 80px;
            resize: vertical;
        }
        
        .endpoint-info {
            background-color: #e7f3ff;
            padding: 15px;
            border-radius: 5px;
            margin: 20px 0;
            font-family: monospace;
            font-size: 14px;
        }
        
        .loading {
            display: inline-block;
            width: 20px;
            height: 20px;
            border: 3px solid #f3f3f3;
            border-top: 3px solid #4285f4;
            border-radius: 50%;
            animation: spin 1s linear infinite;
            margin-right: 10px;
        }
        
        @keyframes spin {
            0% { transform: rotate(0deg); }
            100% { transform: rotate(360deg); }
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🎤 Voice Support Agent Test Interface</h1>
        
        <div class="endpoint-info">
            <strong>API Endpoint:</strong> ${function_url}
        </div>
        
        <div class="test-section">
            <h3>Quick Tests</h3>
            <div class="controls">
                <button id="healthCheck" class="info-btn">🏥 Health Check</button>
                <button id="startVoice" class="primary-btn">🎙️ Initialize Voice Session</button>
                <button id="testText" class="secondary-btn">💬 Test Text Message</button>
            </div>
        </div>
        
        <div class="test-section">
            <h3>Custom Text Message Test</h3>
            <div class="input-group">
                <label for="customMessage">Message:</label>
                <textarea id="customMessage" placeholder="Enter your test message here...">Hello, I need help with my account. My customer ID is 12345.</textarea>
            </div>
            <div class="input-group">
                <label for="customerId">Customer ID (optional):</label>
                <input type="text" id="customerId" placeholder="12345" value="test-customer">
            </div>
            <button id="sendCustomMessage" class="secondary-btn">📨 Send Custom Message</button>
        </div>
        
        <div class="test-section">
            <h3>Voice Session Configuration</h3>
            <div class="input-group">
                <label for="sessionId">Session ID:</label>
                <input type="text" id="sessionId" placeholder="test-session-123" value="">
            </div>
            <button id="startCustomVoice" class="primary-btn">🎯 Start Custom Voice Session</button>
        </div>
        
        <div id="status" class="status info">Ready to test voice agent - Click any button above to begin</div>
        <div id="responses"></div>
    </div>
    
    <script>
        const functionUrl = '${function_url}';
        let requestCounter = 0;
        
        // Generate random session ID on page load
        document.getElementById('sessionId').value = 'test-session-' + Date.now();
        
        // Event listeners
        document.getElementById('startVoice').addEventListener('click', () => startVoiceSession());
        document.getElementById('testText').addEventListener('click', () => testTextMessage());
        document.getElementById('healthCheck').addEventListener('click', () => healthCheck());
        document.getElementById('sendCustomMessage').addEventListener('click', () => sendCustomMessage());
        document.getElementById('startCustomVoice').addEventListener('click', () => startCustomVoiceSession());
        
        function updateStatus(message, type = 'success', showLoading = false) {
            const statusDiv = document.getElementById('status');
            statusDiv.innerHTML = showLoading ? '<span class="loading"></span>' + message : message;
            statusDiv.className = `status $${type}`;
        }
        
        function addResponse(content, title = 'Agent Response') {
            requestCounter++;
            const responsesDiv = document.getElementById('responses');
            const responseDiv = document.createElement('div');
            responseDiv.className = 'response';
            
            const headerDiv = document.createElement('div');
            headerDiv.className = 'response-header';
            headerDiv.textContent = `$${title} #$${requestCounter} - $${new Date().toLocaleTimeString()}`;
            
            const contentDiv = document.createElement('div');
            contentDiv.className = 'json-content';
            contentDiv.textContent = JSON.stringify(content, null, 2);
            
            responseDiv.appendChild(headerDiv);
            responseDiv.appendChild(contentDiv);
            responsesDiv.appendChild(responseDiv);
            
            // Scroll to the new response
            responseDiv.scrollIntoView({ behavior: 'smooth' });
        }
        
        async function makeRequest(method, data = null, title = 'API Response') {
            try {
                updateStatus('Sending request...', 'info', true);
                
                const options = {
                    method: method,
                    headers: { 'Content-Type': 'application/json' }
                };
                
                if (data) {
                    options.body = JSON.stringify(data);
                }
                
                const response = await fetch(functionUrl, options);
                const result = await response.json();
                
                if (response.ok) {
                    updateStatus(`$${title} successful`, 'success');
                    addResponse(result, title);
                } else {
                    updateStatus(`$${title} failed: $${response.status}`, 'error');
                    addResponse(result, `$${title} (Error)`);
                }
                
            } catch (error) {
                updateStatus(`Error: $${error.message}`, 'error');
                addResponse({ error: error.message, type: 'network_error' }, `$${title} (Network Error)`);
            }
        }
        
        async function startVoiceSession() {
            const sessionId = 'quick-test-' + Date.now();
            await makeRequest('POST', {
                type: 'voice_start',
                session_id: sessionId
            }, 'Voice Session Initialization');
        }
        
        async function testTextMessage() {
            await makeRequest('POST', {
                type: 'text',
                message: 'Hello, I need help with my account. My customer ID is 12345.',
                customer_context: { 
                    source: 'web_test',
                    timestamp: new Date().toISOString()
                }
            }, 'Text Message Test');
        }
        
        async function healthCheck() {
            await makeRequest('GET', null, 'Health Check');
        }
        
        async function sendCustomMessage() {
            const message = document.getElementById('customMessage').value;
            const customerId = document.getElementById('customerId').value;
            
            if (!message.trim()) {
                updateStatus('Please enter a message', 'error');
                return;
            }
            
            await makeRequest('POST', {
                type: 'text',
                message: message,
                customer_context: { 
                    customer_id: customerId,
                    source: 'custom_test',
                    timestamp: new Date().toISOString()
                }
            }, 'Custom Text Message');
        }
        
        async function startCustomVoiceSession() {
            const sessionId = document.getElementById('sessionId').value;
            
            if (!sessionId.trim()) {
                updateStatus('Please enter a session ID', 'error');
                return;
            }
            
            await makeRequest('POST', {
                type: 'voice_start',
                session_id: sessionId,
                configuration: {
                    enhanced: true,
                    source: 'custom_test'
                }
            }, 'Custom Voice Session');
        }
        
        // Auto-run health check on page load
        window.addEventListener('load', function() {
            setTimeout(() => {
                updateStatus('Running initial health check...', 'info', true);
                healthCheck();
            }, 1000);
        });
    </script>
</body>
</html>