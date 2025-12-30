pin 'application-spree-delhivery', to: 'spree_delhivery/application.js', preload: false

pin_all_from SpreeDelhivery::Engine.root.join('app/javascript/spree_delhivery/controllers'),
             under: 'spree_delhivery/controllers',
             to:    'spree_delhivery/controllers',
             preload: 'application-spree-delhivery'
