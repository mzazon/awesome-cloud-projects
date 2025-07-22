const AWS = require('aws-sdk');
const dynamodb = new AWS.DynamoDB.DocumentClient();

/**
 * AWS Lambda function for handling advanced business logic in the GraphQL API
 * Supports product scoring, recommendations, search indexing, and analytics processing
 */
exports.handler = async (event) => {
    console.log('Received event:', JSON.stringify(event, null, 2));
    
    const { field, arguments: args, source, identity } = event;
    
    try {
        switch (field) {
            case 'calculateProductScore':
                return await calculateProductScore(args.productId);
            case 'getProductRecommendations':
                return await getProductRecommendations(args.userId, args.category);
            case 'updateProductSearchIndex':
                return await updateProductSearchIndex(args.productData);
            case 'processAnalytics':
                return await processAnalytics(args.event, identity);
            case 'getTopProducts':
                return await getTopProducts(args.category, args.limit);
            case 'getTrendingProducts':
                return await getTrendingProducts(args.limit);
            case 'getCategoryStats':
                return await getCategoryStats();
            default:
                throw new Error(`Unknown field: ${field}`);
        }
    } catch (error) {
        console.error('Error processing request:', error);
        throw error;
    }
};

/**
 * Calculate a composite score for a product based on multiple factors
 * @param {string} productId - The product ID to score
 * @returns {Object} Product score with breakdown
 */
async function calculateProductScore(productId) {
    try {
        const product = await dynamodb.get({
            TableName: process.env.PRODUCTS_TABLE,
            Key: { productId }
        }).promise();
        
        if (!product.Item) {
            throw new Error('Product not found');
        }
        
        const { rating = 0, reviewCount = 0, price = 0, category, createdAt } = product.Item;
        
        // Calculate individual score components
        const ratingScore = Math.min(rating / 5, 1) * 0.4; // 40% weight
        const popularityScore = Math.min(reviewCount / 100, 1) * 0.3; // 30% weight
        
        // Price scoring based on category expectations
        let priceScore = 0.3; // Default score
        if (price < 50) priceScore = 0.3;
        else if (price < 200) priceScore = 0.2;
        else priceScore = 0.1;
        priceScore *= 0.3; // 30% weight
        
        // Recency bonus (products created in last 30 days get bonus)
        const thirtyDaysAgo = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);
        const productDate = new Date(createdAt);
        const recencyBonus = productDate > thirtyDaysAgo ? 0.1 : 0;
        
        const totalScore = ratingScore + popularityScore + priceScore + recencyBonus;
        
        return {
            productId,
            score: Math.round(totalScore * 100) / 100,
            breakdown: {
                rating: Math.round(ratingScore * 100) / 100,
                popularity: Math.round(popularityScore * 100) / 100,
                price: Math.round(priceScore * 100) / 100,
                recency: Math.round(recencyBonus * 100) / 100
            },
            maxPossibleScore: 1.1
        };
    } catch (error) {
        console.error('Error calculating product score:', error);
        throw error;
    }
}

/**
 * Get personalized product recommendations for a user
 * @param {string} userId - The user ID for personalization
 * @param {string} category - Optional category filter
 * @returns {Array} Array of recommended products
 */
async function getProductRecommendations(userId, category) {
    try {
        // Get user preferences if available
        let userPreferences = null;
        try {
            const user = await dynamodb.get({
                TableName: process.env.USERS_TABLE,
                Key: { userId }
            }).promise();
            userPreferences = user.Item?.preferences;
        } catch (err) {
            console.warn('Could not fetch user preferences:', err.message);
        }
        
        // Query products by category or get all products
        let params;
        if (category) {
            params = {
                TableName: process.env.PRODUCTS_TABLE,
                IndexName: 'CategoryIndex',
                KeyConditionExpression: 'category = :category',
                ExpressionAttributeValues: {
                    ':category': category
                },
                Limit: 20
            };
        } else {
            params = {
                TableName: process.env.PRODUCTS_TABLE,
                Limit: 20
            };
        }
        
        const result = category ? 
            await dynamodb.query(params).promise() : 
            await dynamodb.scan(params).promise();
        
        // Apply recommendation scoring algorithm
        const recommendations = result.Items.map(item => {
            let score = 0.5; // Base score
            
            // Boost score based on rating and reviews
            if (item.rating) {
                score += (item.rating / 5) * 0.3;
            }
            if (item.reviewCount) {
                score += Math.min(item.reviewCount / 100, 1) * 0.2;
            }
            
            // User preference matching
            if (userPreferences?.favoriteCategories?.includes(item.category)) {
                score += 0.2;
            }
            
            // Price range preference
            if (userPreferences?.priceRange === item.priceRange) {
                score += 0.1;
            }
            
            // Add some randomness for diversity
            score += Math.random() * 0.1;
            
            return {
                ...item,
                recommendationScore: Math.round(score * 100) / 100
            };
        });
        
        // Sort by recommendation score and return top 5
        return recommendations
            .sort((a, b) => b.recommendationScore - a.recommendationScore)
            .slice(0, 5);
            
    } catch (error) {
        console.error('Error generating recommendations:', error);
        throw error;
    }
}

/**
 * Update OpenSearch index with product data
 * @param {Object} productData - Product data to index
 * @returns {Object} Success response
 */
async function updateProductSearchIndex(productData) {
    try {
        // Note: In a real implementation, you would use the OpenSearch client
        // For this template, we'll simulate the indexing operation
        console.log('Updating search index for product:', productData.productId);
        
        const searchDocument = {
            productId: productData.productId,
            name: productData.name,
            description: productData.description,
            category: productData.category,
            tags: productData.tags || [],
            price: productData.price,
            searchText: `${productData.name} ${productData.description} ${(productData.tags || []).join(' ')}`.toLowerCase(),
            timestamp: new Date().toISOString()
        };
        
        // In a real implementation, you would:
        // 1. Create OpenSearch client with proper authentication
        // 2. Index the document to the products index
        // 3. Handle any indexing errors
        
        console.log('Search document prepared:', searchDocument);
        
        return { 
            success: true, 
            productId: productData.productId,
            message: 'Search index update queued successfully'
        };
        
    } catch (error) {
        console.error('Error updating search index:', error);
        throw error;
    }
}

/**
 * Process analytics events and store them
 * @param {Object} eventData - Analytics event data
 * @param {Object} identity - User identity context
 * @returns {Object} Success response
 */
async function processAnalytics(eventData, identity) {
    try {
        const analyticsRecord = {
            metricId: `${eventData.type}-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`,
            timestamp: new Date().toISOString(),
            eventType: eventData.type,
            userId: identity?.sub || 'anonymous',
            userGroups: identity?.['cognito:groups'] || [],
            data: eventData.data || {},
            ttl: Math.floor(Date.now() / 1000) + (30 * 24 * 60 * 60), // 30 days TTL
            source: 'graphql-api',
            sessionId: eventData.sessionId,
            clientInfo: eventData.clientInfo
        };
        
        await dynamodb.put({
            TableName: process.env.ANALYTICS_TABLE,
            Item: analyticsRecord
        }).promise();
        
        console.log('Analytics event processed:', analyticsRecord.metricId);
        
        return { 
            success: true, 
            eventId: analyticsRecord.metricId,
            timestamp: analyticsRecord.timestamp
        };
        
    } catch (error) {
        console.error('Error processing analytics:', error);
        throw error;
    }
}

/**
 * Get top-performing products by category
 * @param {string} category - Optional category filter
 * @param {number} limit - Number of products to return
 * @returns {Array} Top products
 */
async function getTopProducts(category, limit = 10) {
    try {
        let params;
        if (category) {
            params = {
                TableName: process.env.PRODUCTS_TABLE,
                IndexName: 'CategoryIndex',
                KeyConditionExpression: 'category = :category',
                ExpressionAttributeValues: {
                    ':category': category
                },
                Limit: 50 // Get more to sort and filter
            };
        } else {
            params = {
                TableName: process.env.PRODUCTS_TABLE,
                Limit: 50
            };
        }
        
        const result = category ? 
            await dynamodb.query(params).promise() : 
            await dynamodb.scan(params).promise();
        
        // Calculate scores and sort
        const scored = result.Items.map(item => ({
            ...item,
            topScore: (item.rating || 0) * (item.reviewCount || 1) * 0.1
        }));
        
        return scored
            .sort((a, b) => b.topScore - a.topScore)
            .slice(0, limit);
            
    } catch (error) {
        console.error('Error getting top products:', error);
        throw error;
    }
}

/**
 * Get trending products based on recent activity
 * @param {number} limit - Number of products to return
 * @returns {Array} Trending products
 */
async function getTrendingProducts(limit = 10) {
    try {
        const params = {
            TableName: process.env.PRODUCTS_TABLE,
            Limit: 50
        };
        
        const result = await dynamodb.scan(params).promise();
        
        // Simple trending algorithm based on creation date and activity
        const trending = result.Items.map(item => {
            const daysSinceCreation = Math.floor((Date.now() - new Date(item.createdAt).getTime()) / (1000 * 60 * 60 * 24));
            const trendScore = (item.reviewCount || 0) / Math.max(daysSinceCreation, 1);
            
            return {
                ...item,
                trendScore: trendScore
            };
        });
        
        return trending
            .sort((a, b) => b.trendScore - a.trendScore)
            .slice(0, limit);
            
    } catch (error) {
        console.error('Error getting trending products:', error);
        throw error;
    }
}

/**
 * Get category statistics and insights
 * @returns {Array} Category statistics
 */
async function getCategoryStats() {
    try {
        const params = {
            TableName: process.env.PRODUCTS_TABLE
        };
        
        const result = await dynamodb.scan(params).promise();
        
        // Group by category and calculate stats
        const categoryMap = new Map();
        
        result.Items.forEach(item => {
            if (!categoryMap.has(item.category)) {
                categoryMap.set(item.category, {
                    category: item.category,
                    products: [],
                    totalProducts: 0,
                    totalPrice: 0,
                    totalRating: 0,
                    ratedProducts: 0
                });
            }
            
            const stats = categoryMap.get(item.category);
            stats.products.push(item);
            stats.totalProducts++;
            stats.totalPrice += item.price || 0;
            
            if (item.rating) {
                stats.totalRating += item.rating;
                stats.ratedProducts++;
            }
        });
        
        // Convert to array with calculated averages
        return Array.from(categoryMap.values()).map(stats => ({
            category: stats.category,
            totalProducts: stats.totalProducts,
            averagePrice: Math.round((stats.totalPrice / stats.totalProducts) * 100) / 100,
            averageRating: stats.ratedProducts > 0 ? 
                Math.round((stats.totalRating / stats.ratedProducts) * 100) / 100 : 0
        }));
        
    } catch (error) {
        console.error('Error getting category stats:', error);
        throw error;
    }
}