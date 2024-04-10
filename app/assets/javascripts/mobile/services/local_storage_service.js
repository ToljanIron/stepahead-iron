angular.module('workships-mobile.services').factory('localStorageService', function() {
    'use strict';

    var localStorageService = {};

    localStorageService.saveObject = function(key, value) {
        localStorage.setItem(key, JSON.stringify(value));
    };

    localStorageService.getObject = function(key) {
        var value = localStorage.getItem(key);
        return value ? JSON.parse(value) : null;
    };

    localStorageService.removeObject = function(key) {
        localStorage.removeItem(key);
    };

    return localStorageService;
});
