// JavaScript functionality for the App Engine Flask application
// Provides interactive features for health checking and application info

/**
 * Display status messages with appropriate styling
 * @param {string} message - The message to display
 * @param {string} type - The type of message ('success', 'error', 'loading', 'info')
 */
function displayStatus(message, type = 'info') {
    const statusDisplay = document.getElementById('status-display');
    
    // Clear existing status classes
    statusDisplay.className = 'status-display';
    
    // Add appropriate status class
    if (type === 'success') {
        statusDisplay.classList.add('status-success');
    } else if (type === 'error') {
        statusDisplay.classList.add('status-error');
    } else if (type === 'loading') {
        statusDisplay.classList.add('status-loading');
    }
    
    statusDisplay.textContent = message;
}

/**
 * Format timestamp for better readability
 * @param {string} timestamp - ISO timestamp string
 * @returns {string} Formatted timestamp
 */
function formatTimestamp(timestamp) {
    try {
        const date = new Date(timestamp);
        return date.toLocaleString('en-US', {
            year: 'numeric',
            month: 'short',
            day: 'numeric',
            hour: '2-digit',
            minute: '2-digit',
            second: '2-digit',
            timeZoneName: 'short'
        });
    } catch (error) {
        return timestamp;
    }
}

/**
 * Perform application health check
 */
async function checkHealth() {
    const button = document.getElementById('health-check-btn');
    const originalText = button.textContent;
    
    try {
        // Show loading state
        button.innerHTML = '<span class="loading"></span> Checking Health...';
        button.disabled = true;
        displayStatus('Performing health check...', 'loading');
        
        // Make health check request
        const response = await fetch('/health', {
            method: 'GET',
            headers: {
                'Accept': 'application/json',
                'Cache-Control': 'no-cache'
            }
        });
        
        const data = await response.json();
        
        if (response.ok && data.status === 'healthy') {
            // Format success message
            const message = `✅ Application is healthy!
            
Status: ${data.status}
Timestamp: ${formatTimestamp(data.timestamp)}
Version: ${data.version || 'Unknown'}
Service: ${data.service || 'default'}
Instance: ${data.instance || 'N/A'}`;
            
            displayStatus(message, 'success');
        } else {
            // Handle unhealthy response
            const message = `❌ Application health check failed
            
Status: ${data.status || 'Unknown'}
Error: ${data.error || 'Unknown error'}
Timestamp: ${formatTimestamp(data.timestamp)}`;
            
            displayStatus(message, 'error');
        }
        
    } catch (error) {
        // Handle network or other errors
        const message = `❌ Health check failed
        
Error: ${error.message}
Time: ${new Date().toLocaleString()}

This could indicate a network issue or server problem.`;
        
        displayStatus(message, 'error');
        console.error('Health check error:', error);
    } finally {
        // Restore button state
        button.textContent = originalText;
        button.disabled = false;
    }
}

/**
 * Get detailed application information
 */
async function getAppInfo() {
    const button = document.getElementById('app-info-btn');
    const originalText = button.textContent;
    
    try {
        // Show loading state
        button.innerHTML = '<span class="loading"></span> Getting Info...';
        button.disabled = true;
        displayStatus('Retrieving application information...', 'loading');
        
        // Make info request
        const response = await fetch('/info', {
            method: 'GET',
            headers: {
                'Accept': 'application/json',
                'Cache-Control': 'no-cache'
            }
        });
        
        const data = await response.json();
        
        if (response.ok) {
            // Format info message
            const message = `ℹ️ Application Information
            
Application Name: ${data.app_name || 'Unknown'}
Runtime: ${data.runtime || 'Unknown'}
Framework: ${data.framework || 'Unknown'}
Version: ${data.version || 'Unknown'}
Service: ${data.service || 'default'}
Retrieved: ${formatTimestamp(data.timestamp)}`;
            
            displayStatus(message, 'success');
        } else {
            // Handle error response
            const message = `❌ Failed to get application info
            
Error: ${data.error || 'Unknown error'}
Time: ${new Date().toLocaleString()}`;
            
            displayStatus(message, 'error');
        }
        
    } catch (error) {
        // Handle network or other errors
        const message = `❌ Failed to get application info
        
Error: ${error.message}
Time: ${new Date().toLocaleString()}

This could indicate a network issue or server problem.`;
        
        displayStatus(message, 'error');
        console.error('App info error:', error);
    } finally {
        // Restore button state
        button.textContent = originalText;
        button.disabled = false;
    }
}

/**
 * Update current time display every second
 */
function updateCurrentTime() {
    const timeElement = document.getElementById('current-time');
    if (timeElement) {
        const now = new Date();
        timeElement.textContent = now.toLocaleString('en-US', {
            year: 'numeric',
            month: '2-digit',
            day: '2-digit',
            hour: '2-digit',
            minute: '2-digit',
            second: '2-digit',
            timeZone: 'UTC',
            timeZoneName: 'short'
        });
    }
}

/**
 * Initialize the application when DOM is loaded
 */
document.addEventListener('DOMContentLoaded', function() {
    console.log('App Engine Flask application loaded successfully');
    
    // Update time display every second
    updateCurrentTime();
    setInterval(updateCurrentTime, 1000);
    
    // Add keyboard shortcuts
    document.addEventListener('keydown', function(event) {
        // Alt + H for health check
        if (event.altKey && event.key === 'h') {
            event.preventDefault();
            checkHealth();
        }
        
        // Alt + I for app info
        if (event.altKey && event.key === 'i') {
            event.preventDefault();
            getAppInfo();
        }
    });
    
    // Display initial welcome message
    displayStatus('Welcome to your App Engine application! Use the buttons above to test functionality.', 'info');
    
    console.log('Keyboard shortcuts: Alt+H (health check), Alt+I (app info)');
});