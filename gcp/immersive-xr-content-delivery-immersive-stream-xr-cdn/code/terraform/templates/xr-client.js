/**
 * XR Client Library for Google Cloud Immersive Stream for XR
 * Handles XR session management, device detection, and streaming operations
 */

class XRClient {
    constructor() {
        // Initialize client configuration
        this.config = window.platformConfig || {};
        this.streamEndpoint = (this.config.cdnEndpoint || window.location.origin) + '/stream/';
        this.apiEndpoint = (this.config.cdnEndpoint || window.location.origin) + '/api/';
        
        // Session management
        this.sessionId = null;
        this.isConnected = false;
        this.isARMode = false;
        this.isLoading = false;
        
        // Device and capability detection
        this.deviceInfo = this.detectDevice();
        this.capabilities = this.detectCapabilities();
        
        // Event handlers
        this.eventHandlers = {
            onSessionStart: [],
            onSessionEnd: [],
            onError: [],
            onModeChange: []
        };
        
        // Initialize the client
        this.initialize();
        
        console.log('XR Client initialized:', {
            endpoint: this.streamEndpoint,
            device: this.deviceInfo,
            capabilities: this.capabilities
        });
    }
    
    /**
     * Initialize the XR client and set up event listeners
     */
    initialize() {
        // Set up periodic health checks
        this.healthCheckInterval = setInterval(() => {
            if (this.isConnected) {
                this.performHealthCheck();
            }
        }, 30000); // Check every 30 seconds
        
        // Set up window event listeners
        window.addEventListener('beforeunload', () => {
            this.cleanup();
        });
        
        // Set up resize handler for responsive XR container
        window.addEventListener('resize', () => {
            this.handleResize();
        });
    }
    
    /**
     * Detect device type and capabilities
     */
    detectDevice() {
        const userAgent = navigator.userAgent.toLowerCase();
        const platform = navigator.platform.toLowerCase();
        
        let deviceType = 'desktop';
        let os = 'unknown';
        
        // Detect mobile devices
        if (/ipad|iphone|ipod/.test(userAgent)) {
            deviceType = 'ios';
            os = 'ios';
        } else if (/android/.test(userAgent)) {
            deviceType = 'android';
            os = 'android';
        } else if (/windows/.test(platform)) {
            os = 'windows';
        } else if (/mac/.test(platform)) {
            os = 'macos';
        } else if (/linux/.test(platform)) {
            os = 'linux';
        }
        
        // Detect VR/AR capabilities
        const hasWebXR = 'xr' in navigator;
        const hasWebGL = this.detectWebGL();
        const hasCamera = this.detectCamera();
        
        return {
            type: deviceType,
            os: os,
            userAgent: userAgent,
            hasWebXR: hasWebXR,
            hasWebGL: hasWebGL,
            hasCamera: hasCamera,
            screenSize: {
                width: window.screen.width,
                height: window.screen.height
            },
            viewport: {
                width: window.innerWidth,
                height: window.innerHeight
            }
        };
    }
    
    /**
     * Detect WebGL support
     */
    detectWebGL() {
        try {
            const canvas = document.createElement('canvas');
            const gl = canvas.getContext('webgl') || canvas.getContext('experimental-webgl');
            return !!gl;
        } catch (e) {
            return false;
        }
    }
    
    /**
     * Detect camera access capability
     */
    async detectCamera() {
        try {
            if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
                return false;
            }
            
            const devices = await navigator.mediaDevices.enumerateDevices();
            return devices.some(device => device.kind === 'videoinput');
        } catch (e) {
            return false;
        }
    }
    
    /**
     * Detect XR and streaming capabilities
     */
    detectCapabilities() {
        const capabilities = {
            webxr: {
                supported: 'xr' in navigator,
                immersiveVR: false,
                immersiveAR: false,
                inline: false
            },
            streaming: {
                webrtc: 'RTCPeerConnection' in window,
                websockets: 'WebSocket' in window,
                mediaSource: 'MediaSource' in window
            },
            performance: {
                hardwareConcurrency: navigator.hardwareConcurrency || 1,
                memory: navigator.deviceMemory || 'unknown',
                connection: this.getConnectionInfo()
            }
        };
        
        // Check specific XR modes if WebXR is supported
        if (capabilities.webxr.supported) {
            this.checkXRModes(capabilities.webxr);
        }
        
        return capabilities;
    }
    
    /**
     * Check available XR modes
     */
    async checkXRModes(webxrCapabilities) {
        try {
            if (navigator.xr) {
                webxrCapabilities.immersiveVR = await navigator.xr.isSessionSupported('immersive-vr');
                webxrCapabilities.immersiveAR = await navigator.xr.isSessionSupported('immersive-ar');
                webxrCapabilities.inline = await navigator.xr.isSessionSupported('inline');
            }
        } catch (e) {
            console.warn('XR mode detection failed:', e);
        }
    }
    
    /**
     * Get network connection information
     */
    getConnectionInfo() {
        if ('connection' in navigator) {
            const conn = navigator.connection;
            return {
                effectiveType: conn.effectiveType,
                downlink: conn.downlink,
                rtt: conn.rtt,
                saveData: conn.saveData
            };
        }
        return null;
    }
    
    /**
     * Start XR streaming session
     */
    async startXR() {
        if (this.isLoading) {
            this.showStatus('Session start already in progress...', 'info');
            return;
        }
        
        try {
            this.isLoading = true;
            this.showStatus('Initializing XR session...', 'info');
            
            // Prepare session request
            const sessionRequest = {
                device: this.deviceInfo,
                capabilities: this.capabilities,
                preferences: {
                    quality: 'high',
                    fps: 60,
                    resolution: this.getOptimalResolution(),
                    arMode: this.isARMode
                },
                timestamp: new Date().toISOString()
            };
            
            // Make request to streaming service
            const response = await this.makeRequest('/start', 'POST', sessionRequest);
            
            if (response.success) {
                this.sessionId = response.sessionId;
                this.isConnected = true;
                
                // Initialize streaming connection
                await this.initializeStream(response.streamUrl, response.config);
                
                this.showStatus(`XR session started successfully! Session ID: ${this.sessionId}`, 'success');
                this.triggerEvent('onSessionStart', { sessionId: this.sessionId, config: response.config });
            } else {
                throw new Error(response.error || 'Failed to start XR session');
            }
            
        } catch (error) {
            console.error('Failed to start XR session:', error);
            this.showStatus(`Failed to start XR session: ${error.message}`, 'error');
            this.triggerEvent('onError', { error: error, context: 'session_start' });
        } finally {
            this.isLoading = false;
        }
    }
    
    /**
     * Initialize streaming connection
     */
    async initializeStream(streamUrl, config) {
        // Update loading indicator
        const loadingElement = document.getElementById('loading');
        if (loadingElement) {
            loadingElement.innerHTML = `
                <div>🎮 Connecting to XR stream...</div>
                <div style="margin-top: 10px; font-size: 0.9em;">
                    Session: ${this.sessionId}<br>
                    Mode: ${this.isARMode ? 'AR' : 'VR'}<br>
                    Quality: ${config.quality || 'High'}
                </div>
            `;
        }
        
        // Simulate stream initialization (replace with actual streaming logic)
        await this.delay(2000);
        
        // Update container to show active stream
        this.updateStreamContainer(true);
        
        console.log('XR stream initialized:', { streamUrl, config });
    }
    
    /**
     * Toggle AR mode
     */
    async toggleAR() {
        this.isARMode = !this.isARMode;
        
        const mode = this.isARMode ? 'AR' : 'VR';
        this.showStatus(`Switched to ${mode} mode`, 'info');
        
        // If session is active, update the mode
        if (this.isConnected) {
            try {
                await this.makeRequest('/mode', 'PUT', { 
                    sessionId: this.sessionId,
                    arMode: this.isARMode 
                });
                
                this.updateStreamContainer(true);
                this.triggerEvent('onModeChange', { arMode: this.isARMode });
            } catch (error) {
                console.error('Failed to update XR mode:', error);
                this.showStatus(`Failed to update mode: ${error.message}`, 'error');
            }
        }
        
        // Update button text
        this.updateControlButtons();
    }
    
    /**
     * Reset XR view
     */
    async resetView() {
        if (!this.isConnected) {
            this.showStatus('No active XR session to reset', 'info');
            return;
        }
        
        try {
            await this.makeRequest('/reset', 'POST', { 
                sessionId: this.sessionId 
            });
            
            this.showStatus('XR view reset successfully', 'success');
            
        } catch (error) {
            console.error('Failed to reset XR view:', error);
            this.showStatus(`Failed to reset view: ${error.message}`, 'error');
        }
    }
    
    /**
     * Load configuration from server
     */
    async loadConfig() {
        try {
            this.showStatus('Loading configuration...', 'info');
            
            const configUrl = (this.config.cdnEndpoint || window.location.origin) + '/configs/app-config.json';
            const response = await fetch(configUrl);
            
            if (!response.ok) {
                throw new Error(`HTTP ${response.status}: ${response.statusText}`);
            }
            
            const config = await response.json();
            
            this.showStatus('Configuration loaded successfully', 'success');
            console.log('Loaded config:', config);
            
            // Apply configuration
            this.applyConfiguration(config);
            
        } catch (error) {
            console.error('Failed to load configuration:', error);
            this.showStatus(`Failed to load config: ${error.message}`, 'error');
        }
    }
    
    /**
     * Apply loaded configuration
     */
    applyConfiguration(config) {
        // Update client settings based on loaded config
        if (config.rendering) {
            console.log('Applying rendering settings:', config.rendering);
        }
        
        if (config.features) {
            console.log('Applying feature settings:', config.features);
            
            // Update AR mode if specified
            if (config.features.ar_enabled !== undefined && !this.isConnected) {
                this.isARMode = config.features.ar_enabled;
                this.updateControlButtons();
            }
        }
    }
    
    /**
     * Update stream container visual state
     */
    updateStreamContainer(isActive) {
        const container = document.getElementById('xr-container');
        const loadingElement = document.getElementById('loading');
        
        if (!container || !loadingElement) return;
        
        if (isActive) {
            container.style.background = 'linear-gradient(135deg, #667eea 0%, #764ba2 100%)';
            container.style.border = '2px solid #667eea';
            container.style.color = 'white';
            
            loadingElement.innerHTML = `
                <div style="text-align: center;">
                    <div style="font-size: 2em; margin-bottom: 10px;">🥽</div>
                    <div>XR Session Active</div>
                    <div style="margin-top: 10px; font-size: 0.9em; opacity: 0.8;">
                        Mode: ${this.isARMode ? 'Augmented Reality' : 'Virtual Reality'}<br>
                        Session: ${this.sessionId}<br>
                        Status: Connected
                    </div>
                </div>
            `;
        } else {
            container.style.background = '#f0f0f0';
            container.style.border = '2px dashed #ccc';
            container.style.color = '#666';
            
            loadingElement.innerHTML = '🚀 Ready to launch XR experience...';
        }
    }
    
    /**
     * Update control button states
     */
    updateControlButtons() {
        // This could be enhanced to update button text/state based on current mode
        console.log('Control buttons updated for AR mode:', this.isARMode);
    }
    
    /**
     * Get optimal resolution based on device
     */
    getOptimalResolution() {
        const { width, height } = this.deviceInfo.viewport;
        
        // Determine optimal resolution based on device capabilities
        if (width >= 1920) {
            return '1920x1080';
        } else if (width >= 1280) {
            return '1280x720';
        } else {
            return '854x480';
        }
    }
    
    /**
     * Make HTTP request to API endpoint
     */
    async makeRequest(path, method = 'GET', body = null) {
        const url = this.apiEndpoint + path.replace(/^\//, '');
        
        const options = {
            method: method,
            headers: {
                'Content-Type': 'application/json',
                'X-Client-Version': '1.0',
                'X-Device-Type': this.deviceInfo.type
            }
        };
        
        if (body) {
            options.body = JSON.stringify(body);
        }
        
        // Simulate API response for demo purposes
        // In production, this would make actual HTTP requests
        await this.delay(1000 + Math.random() * 2000);
        
        // Return mock response
        return {
            success: true,
            sessionId: 'xr-session-' + Date.now(),
            streamUrl: 'wss://xr-stream.example.com/session',
            config: {
                quality: 'high',
                fps: 60,
                features: ['ar', 'spatial_audio', 'haptic_feedback']
            }
        };
    }
    
    /**
     * Perform health check on active session
     */
    async performHealthCheck() {
        if (!this.sessionId) return;
        
        try {
            const response = await this.makeRequest('/health', 'GET');
            console.log('Health check passed:', response);
        } catch (error) {
            console.warn('Health check failed:', error);
            this.handleConnectionError(error);
        }
    }
    
    /**
     * Handle connection errors
     */
    handleConnectionError(error) {
        this.isConnected = false;
        this.sessionId = null;
        
        this.showStatus('Connection lost. Please restart your XR session.', 'error');
        this.updateStreamContainer(false);
        
        this.triggerEvent('onError', { error: error, context: 'connection' });
    }
    
    /**
     * Handle window resize
     */
    handleResize() {
        this.deviceInfo.viewport = {
            width: window.innerWidth,
            height: window.innerHeight
        };
        
        // Update any responsive elements
        console.log('Viewport updated:', this.deviceInfo.viewport);
    }
    
    /**
     * Show status message to user
     */
    showStatus(message, type = 'info') {
        const statusElement = document.getElementById('status');
        if (!statusElement) return;
        
        statusElement.textContent = message;
        statusElement.className = `status ${type}`;
        statusElement.style.display = 'block';
        
        // Auto-hide success and info messages
        if (type === 'success' || type === 'info') {
            setTimeout(() => {
                statusElement.style.display = 'none';
            }, 5000);
        }
    }
    
    /**
     * Add event listener
     */
    addEventListener(eventType, handler) {
        if (this.eventHandlers[eventType]) {
            this.eventHandlers[eventType].push(handler);
        }
    }
    
    /**
     * Trigger event
     */
    triggerEvent(eventType, data) {
        if (this.eventHandlers[eventType]) {
            this.eventHandlers[eventType].forEach(handler => {
                try {
                    handler(data);
                } catch (error) {
                    console.error(`Error in ${eventType} handler:`, error);
                }
            });
        }
    }
    
    /**
     * Cleanup resources
     */
    cleanup() {
        if (this.healthCheckInterval) {
            clearInterval(this.healthCheckInterval);
        }
        
        if (this.isConnected) {
            this.makeRequest('/stop', 'POST', { sessionId: this.sessionId })
                .catch(error => console.warn('Failed to stop session during cleanup:', error));
        }
        
        this.triggerEvent('onSessionEnd', { sessionId: this.sessionId });
    }
    
    /**
     * Utility: delay function
     */
    delay(ms) {
        return new Promise(resolve => setTimeout(resolve, ms));
    }
}

// Initialize XR client when page loads
let xrClient;

document.addEventListener('DOMContentLoaded', () => {
    xrClient = new XRClient();
    
    // Add event listeners for better user experience
    xrClient.addEventListener('onSessionStart', (data) => {
        console.log('XR session started:', data);
    });
    
    xrClient.addEventListener('onSessionEnd', (data) => {
        console.log('XR session ended:', data);
    });
    
    xrClient.addEventListener('onError', (data) => {
        console.error('XR client error:', data);
    });
});

// Global functions for button handlers
function startXR() {
    if (xrClient) {
        xrClient.startXR();
    }
}

function toggleAR() {
    if (xrClient) {
        xrClient.toggleAR();
    }
}

function resetView() {
    if (xrClient) {
        xrClient.resetView();
    }
}

function loadConfig() {
    if (xrClient) {
        xrClient.loadConfig();
    }
}