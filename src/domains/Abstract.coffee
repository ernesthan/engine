# Transforms variables into tracked variables

Domain = require('../concepts/Domain')

class Abstract extends Domain
  url: undefined
  
  constructor: ->
    if @running
      @compile()
    super

class Abstract::Methods

  get:
    command: (operation, continuation, scope, meta, object, property, contd) ->
      if typeof object == 'string'
        id = object

      # Get document property
      else if object.absolute is 'window' || object == document
        id = '::window'

      # Get element property
      else if object.nodeType
        id = @identity.provide(object)

      unless property
        # Get global variable
        id = ''
        property = object
        object = undefined

      if object
        if prop = @properties[property]
          unless prop.matcher
            return prop.call(@, object, @getContinuation(continuation || contd || ''))
      getter = ['get', id, property, @getContinuation(continuation || contd || '')]
      if scope && scope != @scope
        getter.push(@identity.provide(scope))
      return getter

  set:
    onAnalyze: (operation) ->
      parent = operation.parent
      closest = undefined
      while parent
        if parent.name == 'rule'
          farthest = parent
          closest ||= parent   
        parent = parent.parent
      if farthest
        operation.sourceIndex = farthest.assignments = (farthest.assignments || 0) + 1
        (closest.properties ||= []).push operation.sourceIndex

    command: (operation, continuation, scope, meta, property, value) ->
      if @intrinsic
        @intrinsic.restyle scope, property, value, continuation, operation
      else
        @assumed.set scope, property, value
      return

  suggest:
    command: ->
      @assumed.set.apply(@assumed, arguments)

  value: (value, continuation, string, exported) ->
    if exported
      op = string.split(',')
      scope = op[1]
      property = op[2]
      @engine.values[@engine.getPath(scope, property)] = value
    return value

# Proxy math for axioms
for op in ['+', '-', '*', '/']
  do (op) ->
    Abstract::Methods::[op] = (a, b) ->
      return [op, a, b]

module.exports = Abstract