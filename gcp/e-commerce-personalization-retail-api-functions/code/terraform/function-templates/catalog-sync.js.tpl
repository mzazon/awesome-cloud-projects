// Catalog Sync Cloud Function Template
// This function synchronizes product catalog data with the Retail API

const {ProductServiceClient} = require('@google-cloud/retail');
const {Storage} = require('@google-cloud/storage');
const functions = require('@google-cloud/functions-framework');

const productClient = new ProductServiceClient();
const storage = new Storage();

functions.http('syncCatalog', async (req, res) => {
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
    
    const {products} = req.body;
    
    if (!products || !Array.isArray(products)) {
      res.status(400).json({error: 'Invalid request: products array is required'});
      return;
    }
    
    const parent = `projects/${process.env.PROJECT_ID || '${project_id}'}/locations/global/catalogs/${process.env.CATALOG_NAME || 'default_catalog'}/branches/${process.env.BRANCH_NAME || 'default_branch'}`;
    
    const syncedProducts = [];
    
    for (const product of products) {
      try {
        // Validate required product fields
        if (!product.id || !product.title) {
          console.warn(`Skipping product with missing id or title:`, product);
          continue;
        }
        
        const request = {
          parent: parent,
          product: {
            title: product.title,
            id: product.id,
            categories: product.categories || [],
            priceInfo: {
              price: product.price || 0,
              originalPrice: product.originalPrice || product.price || 0,
              currencyCode: product.currencyCode || 'USD'
            },
            availability: product.availability || 'IN_STOCK',
            attributes: product.attributes || {},
            // Add additional fields for better recommendations
            description: product.description || product.title,
            tags: product.tags || [],
            images: product.images || []
          }
        };
        
        const [response] = await productClient.createProduct(request);
        syncedProducts.push({
          id: product.id,
          title: product.title,
          status: 'synced',
          resourceName: response.name
        });
        
        console.log(`Product ${product.id} synced successfully`);
        
      } catch (productError) {
        console.error(`Error syncing product ${product.id}:`, productError);
        syncedProducts.push({
          id: product.id,
          title: product.title,
          status: 'error',
          error: productError.message
        });
      }
    }
    
    const successCount = syncedProducts.filter(p => p.status === 'synced').length;
    const errorCount = syncedProducts.filter(p => p.status === 'error').length;
    
    res.json({
      success: true,
      message: `Catalog sync completed: ${successCount} products synced, ${errorCount} errors`,
      totalProducts: products.length,
      syncedProducts: successCount,
      errors: errorCount,
      details: syncedProducts
    });
    
  } catch (error) {
    console.error('Catalog sync error:', error);
    res.status(500).json({
      error: 'Internal server error',
      message: error.message,
      details: error.stack
    });
  }
});