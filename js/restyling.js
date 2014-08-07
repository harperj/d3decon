var angular = require('../lib/angular');

var restylingApp = angular.module('restylingApp', []);

require('./services');
require('./directives');
require('./models/SchemaModel');
require('./controllers/RestylingAppController');
require('./controllers/AddMappingsController');
require('./controllers/AddTableController');
require('./controllers/DataTableController');
require('./controllers/MappingsListController');

restylingApp.filter('range', function() {
    return function(input, total) {
        total = parseInt(total);
        for (var i=0; i<total; i++)
            input.push(i);
        return input;
    };
});