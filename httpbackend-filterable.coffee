'use strict'

angular = require('angular')
_ = require('lodash')

module = angular.module('httpbackend-filterable', []).config ($provide, $httpProvider) ->

  # In Angular 1.2, httpBackend does not provide a way of conditionally
  # resolving requests, so we maintain a queue and conditionally resolve
  # ourselves
  queuedResponses = []

  # In Angular 1.2, httpBackend does not provide a nice way of asserting
  # if certain requests have been made.
  requests = []

  queueResponse = (deferred, type, response) ->
    queuedResponses.push
      deferred: deferred
      response: response
      type: type
    deferred.promise

  $httpProvider.interceptors.push ($q) ->
    responseError: (response) ->
      queueResponse($q.defer(), 'reject', response)
    response: (response) ->
      url = response.config.url
      wasCached = response.config.cache and angular.isDefined(response.config.cache.get(url))
      if wasCached then response else queueResponse($q.defer(), 'resolve', response)
    request: (request) ->
      # Production code is free to modify the objects passed as request dat
      # once it's sent, so to assert on values at the time they're sent, we
      # must clone
      requestClone = _.cloneDeep(request)
      requests.push(requestClone)
      requestClone

  $provide.decorator '$httpBackend', ($delegate, $q, $rootScope) ->
    originalFlush = $delegate.flush

    # We try to match the behaviour of $httpBackend.flush as best as we can
    # - Repeatedly flushing until nothing is left to flush
    # - Throwing an error if there is nothing to flush
    NO_PENDING_REQUEST_TO_FLUSH_MESSAGE = 'No pending request to flush !'
    _flush = (predicate, allowEmpty) ->
      try
        originalFlush()
      catch e
        if e.message != NO_PENDING_REQUEST_TO_FLUSH_MESSAGE
          throw e
      toResolve = _.filter(queuedResponses, (response) -> predicate(response.response))
      if toResolve.length == 0 and not allowEmpty
        throw new Error(NO_PENDING_REQUEST_TO_FLUSH_MESSAGE)
      queuedResponses = _.reject(queuedResponses, (response) -> predicate(response.response))
      _.each toResolve, (response) ->
        response.deferred[response.type](response.response)

      if toResolve.length
        $rootScope.$apply()
        # Recursion, but is a tail call, and in strict mode,
        # we might have tail call optimization
        _flush(predicate, true)
      else
        undefined

    $delegate.filteredFlush = (predicate) ->
      _flush(predicate, false)

    $delegate.filteredRequests = (predicate) ->
      _.filter(requests, predicate)

    # Change what $httpBackend.flush to work when this module is
    # included. Otherwise, the interceptor above will queue all
    # requests, and the original $httpBackend has no knowledge of
    # and won't clear it.
    # Only the non-argument version is supported: it flushes all
    # responses. We _could_ make a version that worked with the
    # "count" argument, but suspect it's not worth it, since
    # filteredFlush is so far more useful and clear
    $delegate.flush = () ->
      $delegate.filteredFlush(_.constant(true))

    $delegate

