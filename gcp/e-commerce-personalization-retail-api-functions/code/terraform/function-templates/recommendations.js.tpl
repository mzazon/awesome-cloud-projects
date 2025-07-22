// Recommendations Cloud Function Template
// This function generates and serves personalized product recommendations

const {PredictionServiceClient} = require('@google-cloud/retail');
const {Firestore} = require('@google-cloud/firestore');
const functions = require('@google-cloud/functions-framework');

const predictionClient = new PredictionServiceClient();
const firestore = new Firestore({
  databaseId: process.env.FIRESTORE_DATABASE || 'user-profiles'
});

functions.http('getRecommendations', async (req, res) => {
  try {
    // Set CORS headers for web clients
    res.set('Access-Control-Allow-Origin', '*');
    res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
    res.set('Access-Control-Allow-Headers', 'Content-Type');
    
    // Handle preflight requests
    if (req.method === 'OPTIONS') {
      res.status(204).send('');
      return;
    }
    
    if (req.method !== 'POST') {
      res.status(405).send('Method Not Allowed');
      return;
    }
    
    const {userId, pageType, productId, filter, pageSize} = req.body;
    
    // Validate required fields
    if (!userId) {
      res.status(400).json({error: 'userId is required'});
      return;
    }
    
    // Determine placement based on page type
    const placementMap = {
      'home-page': 'recently_viewed_default',
      'product-detail': 'product_detail_default',
      'category-page': 'category_page_default',
      'shopping-cart': 'shopping_cart_default',
      'search-results': 'search_results_default'
    };
    
    const placementName = placementMap[pageType] || 'recently_viewed_default';
    const placement = `projects/${process.env.PROJECT_ID || '${project_id}'}/locations/global/catalogs/${process.env.CATALOG_NAME || 'default_catalog'}/placements/${placementName}`;
    
    // Get user profile from Firestore for additional context
    const userRef = firestore.collection('user_profiles').doc(userId);
    const userDoc = await userRef.get();
    const userProfile = userDoc.exists ? userDoc.data() : {};
    
    // Prepare prediction request
    const request = {
      placement: placement,
      userEvent: {
        eventType: 'detail-page-view',
        visitorId: userId,
        eventTime: {
          seconds: Math.floor(Date.now() / 1000)
        },
        userInfo: {
          userId: userId
        }
      },
      pageSize: pageSize || 10,
      returnProduct: true,
      params: {}
    };
    
    // Add product context if provided (for product detail pages)
    if (productId) {
      request.userEvent.productDetails = [{
        product: {id: productId},
        quantity: 1
      }];
    }
    
    // Add filter if provided
    if (filter) {
      request.filter = filter;
    }
    
    // Add user context from profile
    if (userProfile.eventCounts) {
      request.params = {
        'user-demographic-age': userProfile.age || 'unknown',
        'user-demographic-gender': userProfile.gender || 'unknown',
        'user-interest-categories': JSON.stringify(
          Object.keys(userProfile.eventCounts).slice(0, 5)
        )
      };
    }
    
    let recommendations = [];
    let attributionToken = '';
    let nextPageToken = '';
    
    try {
      // Get recommendations from Retail API
      const [response] = await predictionClient.predict(request);
      
      attributionToken = response.attributionToken || '';
      nextPageToken = response.nextPageToken || '';
      
      // Process recommendations
      recommendations = (response.results || []).map(result => {
        const product = result.product || {};
        return {
          productId: result.id || product.id,
          title: product.title || 'Unknown Product',
          price: product.priceInfo?.price || 0,
          originalPrice: product.priceInfo?.originalPrice || 0,
          currencyCode: product.priceInfo?.currencyCode || 'USD',
          imageUri: product.images?.[0]?.uri || '',
          categories: product.categories || [],
          availability: product.availability || 'UNKNOWN',
          attributes: product.attributes || {},
          score: result.score || 0,
          personalizedReason: getPersonalizationReason(result, userProfile, pageType)
        };
      });
      
    } catch (predictError) {
      console.warn('Prediction API error, falling back to default recommendations:', predictError);
      
      // Fallback to basic recommendations if Retail API fails
      recommendations = getFallbackRecommendations(userProfile, pageType);
    }
    
    // Log recommendation request for analytics
    console.log(`Recommendations generated for user ${userId}: ${recommendations.length} items`);
    
    // Update user profile with recommendation request
    if (userDoc.exists) {
      await userRef.update({
        lastRecommendationRequest: new Date(),
        totalRecommendationRequests: firestore.FieldValue.increment(1),
        lastPageType: pageType || 'unknown'
      });
    }
    
    res.json({
      success: true,
      userId: userId,
      recommendations: recommendations,
      attributionToken: attributionToken,
      nextPageToken: nextPageToken,
      pageType: pageType,
      recommendationCount: recommendations.length,
      timestamp: new Date().toISOString()
    });
    
  } catch (error) {
    console.error('Recommendation error:', error);
    res.status(500).json({
      error: 'Internal server error',
      message: error.message,
      details: error.stack
    });
  }
});

function getPersonalizationReason(result, userProfile, pageType) {
  // Simple logic to provide explanation for recommendations
  if (userProfile.eventHistory && userProfile.eventHistory.length > 0) {
    const recentEvents = userProfile.eventHistory.slice(-5);
    const recentCategories = recentEvents
      .filter(event => event.productId)
      .map(event => event.productId);
    
    if (result.product && result.product.categories) {
      const productCategories = result.product.categories;
      const hasMatchingCategory = productCategories.some(cat => 
        recentCategories.some(recent => recent.includes(cat))
      );
      
      if (hasMatchingCategory) {
        return "Based on your recent browsing history";
      }
    }
    
    if (pageType === 'product-detail') {
      return "Customers who viewed this item also liked";
    }
    
    if (pageType === 'shopping-cart') {
      return "Frequently bought together";
    }
  }
  
  return "Recommended for you";
}

function getFallbackRecommendations(userProfile, pageType) {
  // Fallback recommendations when Retail API is not available
  const fallbackProducts = [
    {
      productId: 'fallback_001',
      title: 'Popular Wireless Headphones',
      price: 99.99,
      originalPrice: 129.99,
      currencyCode: 'USD',
      categories: ['Electronics', 'Audio'],
      availability: 'IN_STOCK',
      score: 0.8,
      personalizedReason: 'Popular item'
    },
    {
      productId: 'fallback_002',
      title: 'Trending Fitness Tracker',
      price: 79.99,
      currencyCode: 'USD',
      categories: ['Electronics', 'Fitness'],
      availability: 'IN_STOCK',
      score: 0.7,
      personalizedReason: 'Trending now'
    },
    {
      productId: 'fallback_003',
      title: 'Bestselling Smart Watch',
      price: 199.99,
      currencyCode: 'USD',
      categories: ['Electronics', 'Wearables'],
      availability: 'IN_STOCK',
      score: 0.6,
      personalizedReason: 'Bestseller'
    }
  ];
  
  return fallbackProducts;
}