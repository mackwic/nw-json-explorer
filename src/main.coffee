angular.module('ui.bootstrap', [
  'ui.bootstrap.accordion'
  'ui.bootstrap.alert'
  'ui.bootstrap.bindHtml'
  'ui.bootstrap.buttons'
  'ui.bootstrap.carousel'
  'ui.bootstrap.collapse'
  'ui.bootstrap.dateparser'
  'ui.bootstrap.datepicker'
  'ui.bootstrap.dropdown'
  'ui.bootstrap.modal'
  'ui.bootstrap.pagination'
  'ui.bootstrap.popover'
  'ui.bootstrap.position'
  'ui.bootstrap.progressbar'
  'ui.bootstrap.rating'
  'ui.bootstrap.tabs'
  'ui.bootstrap.timepicker'
  'ui.bootstrap.tooltip'
  'ui.bootstrap.transition'
  'ui.bootstrap.typeahead'
])

angular.module 'jsonExplorer', [
  'ngAnimate'
  'ngSanitize'
  'ngRoute'
  'ui.bootstrap'
  'pasvaz.bindonce'
  'gd.ui.jsonexplorer'
]

module = angular.module('jsonExplorer')
_ = require 'lodash'
Promise = require 'bluebird'
fs = Promise.promisifyAll require 'fs-extra'

module.config ($routeProvider) ->
  $routeProvider.when '/', {
    controller: 'rootCtrl'
    templateUrl: 'root.html'
  }

module.controller 'rootCtrl', ($scope) ->
  $scope.data = {
    'name': 'Json Explorer',
    'qty': 10,
    'has_data': true,
    'arr': [
        10,
        'str',
        {
            'nested': 'object'
        }
    ],
    'obj': {
      'hello': 'world'
    }
  }

  window.ondragover =  -> false
  window.ondrop = (event) ->
    console.log 'drop event !'
    fs.readFileAsync(event.dataTransfer.files[0].path)
      .then (data) ->
        console.log 'file readen !'
        $scope.data = data
        $scope.$apply()
    false

