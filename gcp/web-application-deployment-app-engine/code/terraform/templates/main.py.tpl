from flask import Flask, render_template, jsonify
import datetime
import os
import logging

# Configure logging for production
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize Flask application
app = Flask(__name__)

# Configure Flask settings
app.config['SECRET_KEY'] = os.environ.get('SECRET_KEY', 'dev-key-change-in-production')

@app.route('/')
def home():
    """Main application route serving the homepage."""
    try:
        current_time = datetime.datetime.now()
        version = os.environ.get('GAE_VERSION', 'local')
        
        logger.info(f"Home page accessed at {current_time}")
        
        return render_template('index.html', 
                             current_time=current_time,
                             version=version,
                             app_name='${app_name}')
    except Exception as e:
        logger.error(f"Error serving home page: {str(e)}")
        return jsonify({'error': 'Internal server error'}), 500

@app.route('/health')
def health_check():
    """Health check endpoint for monitoring and load balancer probes."""
    try:
        health_data = {
            'status': 'healthy',
            'timestamp': str(datetime.datetime.now()),
            'version': os.environ.get('GAE_VERSION', 'local'),
            'service': os.environ.get('GAE_SERVICE', 'default'),
            'instance': os.environ.get('GAE_INSTANCE', 'local')
        }
        
        logger.info("Health check requested")
        return jsonify(health_data)
    except Exception as e:
        logger.error(f"Health check failed: {str(e)}")
        return jsonify({
            'status': 'unhealthy',
            'timestamp': str(datetime.datetime.now()),
            'error': str(e)
        }), 500

@app.route('/info')
def app_info():
    """Application information endpoint."""
    try:
        info_data = {
            'app_name': '${app_name}',
            'runtime': 'python312',
            'framework': 'Flask',
            'version': os.environ.get('GAE_VERSION', 'local'),
            'service': os.environ.get('GAE_SERVICE', 'default'),
            'timestamp': str(datetime.datetime.now())
        }
        
        return jsonify(info_data)
    except Exception as e:
        logger.error(f"Error getting app info: {str(e)}")
        return jsonify({'error': 'Unable to get app info'}), 500

@app.errorhandler(404)
def not_found(error):
    """Handle 404 errors."""
    return jsonify({'error': 'Not found'}), 404

@app.errorhandler(500)
def internal_error(error):
    """Handle 500 errors."""
    logger.error(f"Internal server error: {str(error)}")
    return jsonify({'error': 'Internal server error'}), 500

if __name__ == '__main__':
    # Local development server configuration
    port = int(os.environ.get('PORT', 8080))
    app.run(host='127.0.0.1', port=port, debug=True)