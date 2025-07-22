function handler(event) {
    var request = event.request;
    var headers = request.headers;
    
    // Add security headers
    headers['x-forwarded-proto'] = {value: 'https'};
    headers['x-request-id'] = {value: generateRequestId()};
    
    // Normalize cache key by removing specific query parameters
    var uri = request.uri;
    var querystring = request.querystring;
    
    // Remove tracking parameters to improve cache hit ratio
    delete querystring.utm_source;
    delete querystring.utm_medium;
    delete querystring.utm_campaign;
    delete querystring.fbclid;
    delete querystring.gclid;
    delete querystring._ga;
    delete querystring._gid;
    
    // Redirect old paths to new structure
    if (uri.startsWith('/old-api/')) {
        uri = uri.replace('/old-api/', '/api/');
        request.uri = uri;
    }
    
    // Handle index files for directories
    if (uri.endsWith('/')) {
        request.uri = uri + 'index.html';
    }
    
    // Normalize case for file extensions
    if (uri.match(/\.(css|js|png|jpg|jpeg|gif|ico|svg)$/i)) {
        request.uri = uri.toLowerCase();
    }
    
    return request;
}

function generateRequestId() {
    return 'req-' + Math.random().toString(36).substr(2, 9);
}