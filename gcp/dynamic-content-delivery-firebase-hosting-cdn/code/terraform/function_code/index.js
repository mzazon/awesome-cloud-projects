/**
 * Cloud Functions for Dynamic Content Delivery
 * 
 * This file contains serverless functions that provide dynamic content
 * generation for the Firebase Hosting application with CDN optimization.
 */

const functions = require('@google-cloud/functions-framework');

/**
 * Get Products Function
 * 
 * Provides dynamic product catalog with regional personalization
 * and intelligent caching for CDN optimization.
 */
functions.http('getProducts', (req, res) => {
    // Enable CORS for web application access
    res.set('Access-Control-Allow-Origin', '*');
    res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    res.set('Access-Control-Allow-Headers', 'Content-Type');
    
    // Handle preflight requests
    if (req.method === 'OPTIONS') {
        res.status(204).send('');
        return;
    }
    
    try {
        // Sample product data with regional personalization
        const products = [
            {
                id: 1,
                name: "Premium Wireless Headphones",
                price: "$299.99",
                image: "/images/headphones.jpg",
                category: "electronics",
                description: "High-quality wireless headphones with noise cancellation"
            },
            {
                id: 2,
                name: "Smart Fitness Watch",
                price: "$399.99",
                image: "/images/smartwatch.jpg",
                category: "electronics",
                description: "Advanced fitness tracking with heart rate monitoring"
            },
            {
                id: 3,
                name: "Designer Travel Backpack",
                price: "$159.99",
                image: "/images/backpack.jpg",
                category: "fashion",
                description: "Stylish and functional backpack for urban professionals"
            },
            {
                id: 4,
                name: "Ergonomic Office Chair",
                price: "$449.99",
                image: "/images/office-chair.jpg",
                category: "furniture",
                description: "Comfortable ergonomic chair for long work sessions"
            },
            {
                id: 5,
                name: "Portable Bluetooth Speaker",
                price: "$79.99",
                image: "/images/speaker.jpg",
                category: "electronics",
                description: "Compact speaker with powerful sound and long battery life"
            }
        ];
        
        // Get user region from headers for personalization
        const userRegion = req.headers['cf-ipcountry'] || 
                          req.headers['x-forwarded-country'] || 
                          req.headers['cloudfront-viewer-country'] || 
                          'US';
        
        // Apply regional pricing and currency conversion
        const personalizedProducts = products.map(product => {
            let regionalPrice = product.price;
            let currency = 'USD';
            
            // Simple regional pricing logic
            if (userRegion === 'GB' || userRegion === 'EU') {
                const basePrice = parseFloat(product.price.replace('$', ''));
                regionalPrice = `£${Math.floor(basePrice * 0.85)}`;
                currency = 'GBP';
            } else if (userRegion === 'JP') {
                const basePrice = parseFloat(product.price.replace('$', ''));
                regionalPrice = `¥${Math.floor(basePrice * 110)}`;
                currency = 'JPY';
            } else if (userRegion === 'CA') {
                const basePrice = parseFloat(product.price.replace('$', ''));
                regionalPrice = `CAD $${(basePrice * 1.25).toFixed(2)}`;
                currency = 'CAD';
            }
            
            return {
                ...product,
                regionalPrice,
                currency,
                region: userRegion
            };
        });
        
        // Generate response with caching headers for CDN optimization
        const response = {
            products: personalizedProducts,
            region: userRegion,
            timestamp: new Date().toISOString(),
            total: personalizedProducts.length,
            metadata: {
                version: '1.0',
                environment: process.env.ENVIRONMENT || 'production',
                projectId: process.env.PROJECT_ID || '${project_id}'
            }
        };
        
        // Set CDN-friendly caching headers
        res.set('Cache-Control', 'public, max-age=300, s-maxage=600'); // 5min client, 10min CDN
        res.set('Vary', 'Accept-Encoding, Origin');
        res.set('Content-Type', 'application/json');
        
        // Add custom headers for debugging and monitoring
        res.set('X-Function-Region', process.env.FUNCTION_REGION || 'us-central1');
        res.set('X-Response-Time', Date.now().toString());
        
        res.status(200).json(response);
        
    } catch (error) {
        console.error('Error in getProducts function:', error);
        
        // Return error response with appropriate caching
        res.set('Cache-Control', 'no-cache, no-store, must-revalidate');
        res.status(500).json({
            error: 'Internal server error',
            message: 'Unable to fetch products at this time',
            timestamp: new Date().toISOString()
        });
    }
});

/**
 * Get Recommendations Function
 * 
 * Provides personalized content recommendations based on user behavior
 * and preferences with intelligent caching strategies.
 */
functions.http('getRecommendations', (req, res) => {
    // Enable CORS for web application access
    res.set('Access-Control-Allow-Origin', '*');
    res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    res.set('Access-Control-Allow-Headers', 'Content-Type');
    
    // Handle preflight requests
    if (req.method === 'OPTIONS') {
        res.status(204).send('');
        return;
    }
    
    try {
        // Extract user context from query parameters
        const userId = req.query.userId || 'anonymous';
        const category = req.query.category || 'general';
        const limit = parseInt(req.query.limit) || 5;
        
        // Generate personalized recommendations based on user context
        const baseRecommendations = [
            {
                id: 'rec1',
                title: 'Trending Products',
                description: 'Products that are popular in your region',
                count: 8,
                category: 'trending',
                priority: 1
            },
            {
                id: 'rec2',
                title: 'Similar Items',
                description: 'Based on your browsing history',
                count: 5,
                category: 'similar',
                priority: 2
            },
            {
                id: 'rec3',
                title: 'Recently Viewed',
                description: 'Continue where you left off',
                count: 3,
                category: 'recent',
                priority: 3
            },
            {
                id: 'rec4',
                title: 'Recommended for You',
                description: 'Curated picks based on your preferences',
                count: 6,
                category: 'personalized',
                priority: 4
            },
            {
                id: 'rec5',
                title: 'New Arrivals',
                description: 'Latest products in your favorite categories',
                count: 4,
                category: 'new',
                priority: 5
            }
        ];
        
        // Filter and personalize recommendations
        let recommendations = baseRecommendations;
        
        // Apply category filtering if specified
        if (category !== 'general') {
            recommendations = recommendations.filter(rec => 
                rec.category === category || rec.category === 'personalized'
            );
        }
        
        // Limit results and add personalization
        recommendations = recommendations
            .slice(0, limit)
            .map(rec => ({
                ...rec,
                userId,
                timestamp: new Date().toISOString(),
                confidence: Math.random() * 0.3 + 0.7, // 0.7-1.0 confidence score
                expires: new Date(Date.now() + 300000).toISOString() // 5 minutes
            }));
        
        // Generate response with metadata
        const response = {
            recommendations,
            userId,
            category,
            total: recommendations.length,
            metadata: {
                algorithm: 'collaborative-filtering-v2',
                version: '1.0',
                environment: process.env.ENVIRONMENT || 'production',
                projectId: process.env.PROJECT_ID || '${project_id}',
                generatedAt: new Date().toISOString()
            }
        };
        
        // Set caching headers optimized for recommendations
        res.set('Cache-Control', 'private, max-age=300'); // 5 minute cache for personalized content
        res.set('Vary', 'User-Agent, Accept-Encoding');
        res.set('Content-Type', 'application/json');
        
        // Add custom headers for debugging and monitoring
        res.set('X-Function-Region', process.env.FUNCTION_REGION || 'us-central1');
        res.set('X-User-Context', userId);
        res.set('X-Response-Time', Date.now().toString());
        
        res.status(200).json(response);
        
    } catch (error) {
        console.error('Error in getRecommendations function:', error);
        
        // Return error response with appropriate caching
        res.set('Cache-Control', 'no-cache, no-store, must-revalidate');
        res.status(500).json({
            error: 'Internal server error',
            message: 'Unable to fetch recommendations at this time',
            timestamp: new Date().toISOString()
        });
    }
});

/**
 * Health Check Function
 * 
 * Provides health status for monitoring and load balancer health checks.
 */
functions.http('healthCheck', (req, res) => {
    res.set('Cache-Control', 'no-cache, no-store, must-revalidate');
    res.set('Content-Type', 'application/json');
    
    const healthStatus = {
        status: 'healthy',
        timestamp: new Date().toISOString(),
        version: '1.0',
        environment: process.env.ENVIRONMENT || 'production',
        projectId: process.env.PROJECT_ID || '${project_id}',
        region: process.env.FUNCTION_REGION || 'us-central1',
        uptime: process.uptime(),
        memory: process.memoryUsage()
    };
    
    res.status(200).json(healthStatus);
});

// Export functions for testing (Node.js environment)
if (typeof module !== 'undefined' && module.exports) {
    module.exports = {
        getProducts: functions.getFunction('getProducts'),
        getRecommendations: functions.getFunction('getRecommendations'),
        healthCheck: functions.getFunction('healthCheck')
    };
}