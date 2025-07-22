/**
 * Default model configuration
 */

module.exports.models = {
    // Your app's default datastore
    datastore: 'default',
  
    // Whether or not to use migrations
    migrate: 'alter',
  
    // Setting attributes
    attributes: {
      // Automatically add ID attribute to models
      id: { type: 'number', autoIncrement: true },
      
      // Add created/updated timestamps to all models
      createdAt: { type: 'number', autoCreatedAt: true },
      updatedAt: { type: 'number', autoUpdatedAt: true },
    },
  
    // Default cascade behavior on destroy
    cascadeOnDestroy: true
  };