console.log("CloudFront Monitoring Demo Page loaded");

// Simulate API call for testing
fetch("/api/data")
    .then(response => {
        if (!response.ok) {
            throw new Error('Network response was not ok');
        }
        return response.json();
    })
    .then(data => {
        document.getElementById("content").innerHTML = `
            <h3>API Response:</h3>
            <pre>${JSON.stringify(data, null, 2)}</pre>
        `;
    })
    .catch(error => {
        console.error('Error fetching data:', error);
        document.getElementById("content").innerHTML = `
            <h3>API Response:</h3>
            <p style="color: red;">Error loading data: ${error.message}</p>
        `;
    });

// Add some interactive elements for testing
document.addEventListener('DOMContentLoaded', function() {
    // Add click tracking
    document.addEventListener('click', function(e) {
        console.log('Click event:', e.target.tagName, e.target.className);
    });

    // Simulate periodic requests for monitoring
    setInterval(() => {
        fetch('/api/health', { method: 'HEAD' })
            .catch(error => console.log('Health check failed:', error));
    }, 30000); // Every 30 seconds
});