// User Events Tracking Cloud Function Template
// This function tracks user events for personalization and sends them to the Retail API

const {UserEventServiceClient} = require('@google-cloud/retail');
const {Firestore} = require('@google-cloud/firestore');
const functions = require('@google-cloud/functions-framework');

const userEventClient = new UserEventServiceClient();
const firestore = new Firestore({
  databaseId: process.env.FIRESTORE_DATABASE || 'user-profiles'
});

functions.http('trackEvent', async (req, res) => {
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
    
    const {userId, eventType, productId, searchQuery, pageInfo, quantity, purchaseTransaction} = req.body;
    
    // Validate required fields
    if (!userId || !eventType) {
      res.status(400).json({error: 'userId and eventType are required'});
      return;
    }
    
    // Validate event type
    const validEventTypes = [
      'detail-page-view', 'add-to-cart', 'purchase', 'search', 'home-page-view',
      'category-page-view', 'shopping-cart-page-view', 'checkout-start'
    ];
    
    if (!validEventTypes.includes(eventType)) {
      res.status(400).json({
        error: 'Invalid event type',
        validTypes: validEventTypes
      });
      return;
    }
    
    const parent = `projects/${process.env.PROJECT_ID || '${project_id}'}/locations/global/catalogs/${process.env.CATALOG_NAME || 'default_catalog'}`;
    
    // Create user event for Retail API
    const userEvent = {
      eventType: eventType,
      visitorId: userId,
      eventTime: {
        seconds: Math.floor(Date.now() / 1000)
      },
      userInfo: {
        userId: userId
      }
    };
    
    // Add product details for product-related events
    if (productId && ['detail-page-view', 'add-to-cart', 'purchase'].includes(eventType)) {
      userEvent.productDetails = [{
        product: {
          id: productId
        },
        quantity: quantity || 1
      }];
    }
    
    // Add search query for search events
    if (searchQuery && eventType === 'search') {
      userEvent.searchQuery = searchQuery;
    }
    
    // Add page info
    if (pageInfo) {
      userEvent.pageInfo = {
        pageCategory: pageInfo.pageCategory || 'other',
        uri: pageInfo.uri || '',
        referrerUri: pageInfo.referrerUri || ''
      };
    }
    
    // Add purchase transaction info
    if (purchaseTransaction && eventType === 'purchase') {
      userEvent.purchaseTransaction = {
        id: purchaseTransaction.id,
        revenue: purchaseTransaction.revenue || 0,
        tax: purchaseTransaction.tax || 0,
        cost: purchaseTransaction.cost || 0,
        currencyCode: purchaseTransaction.currencyCode || 'USD'
      };
    }
    
    // Send event to Retail API
    const [retailResponse] = await userEventClient.writeUserEvent({
      parent: parent,
      userEvent: userEvent
    });
    
    // Store user profile data in Firestore
    const userRef = firestore.collection('user_profiles').doc(userId);
    const eventData = {
      eventType,
      productId,
      searchQuery,
      timestamp: new Date(),
      pageInfo: pageInfo || null,
      sessionId: req.headers['x-session-id'] || 'anonymous'
    };
    
    await userRef.set({
      lastActivity: new Date(),
      totalEvents: firestore.FieldValue.increment(1),
      lastEventType: eventType,
      eventHistory: firestore.FieldValue.arrayUnion(eventData)
    }, {merge: true});
    
    // Update event type counters
    const counterUpdate = {};
    counterUpdate[`eventCounts.${eventType}`] = firestore.FieldValue.increment(1);
    await userRef.update(counterUpdate);
    
    console.log(`Event tracked for user ${userId}: ${eventType}`);
    
    res.json({
      success: true,
      message: 'Event tracked successfully',
      eventId: retailResponse.name,
      userId: userId,
      eventType: eventType,
      timestamp: new Date().toISOString()
    });
    
  } catch (error) {
    console.error('Event tracking error:', error);
    res.status(500).json({
      error: 'Internal server error',
      message: error.message,
      details: error.stack
    });
  }
});