Parser = require('ccss-compiler')
Command = require('../Command')

class Stylesheet extends Command
  type: 'Stylesheet'
  
  signature: [
    'source': ['Selector', 'String', 'Node']
    [
      'type': ['String']
      'text': ['String']
    ]
  ]

  @define
    # Evaluate stylesheet
    "eval": (node, type, text, engine, operation, continuation, scope) ->
      engine.Stylesheet.add engine.engine, operation, continuation, node, type, node.textContent
      return



    # Load & evaluate stylesheet
    "load": (node, type, method, engine, operation, continuation, scope) ->
        src = node.href || node.src || node
        type ||= node.type || 'text/gss'
        xhr = new XMLHttpRequest()
        engine.Stylesheet.block(engine)
        xhr.onreadystatechange = =>
          if xhr.readyState == 4 && xhr.status == 200
            engine.Stylesheet.add(engine, operation, continuation, node, type, xhr.responseText)
            if engine.Stylesheet.unblock(engine)
              engine.Stylesheet.complete(engine)
        xhr.open('GET', method && method.toUpperCase() || src)
        xhr.send()
      
  @mimes:
    "text/gss-ast": (source) ->
      return JSON.parse(source)

    "text/gss": (source) ->
      return Parser.parse(source)?.commands
    
  # Insert stylesheet into a collection
  @add: (engine, operation, continuation, stylesheet, type, source) ->
    type = stylesheet.getAttribute('type') || 'text/gss'


    if stylesheet.operations
      engine.queries.clean(@prototype.delimit(stylesheet.continuation))
      if (old = engine.stylesheets[stylesheet.continuation]) != stylesheet
        engine.stylesheets.splice(engine.stylesheets.indexOf(old), 1)
    else
      stylesheet.continuation = @prototype.delimit(continuation, @prototype.DESCEND)
    stylesheet.command = @
    stylesheet.operations = engine.clone @mimes[type](source)

    stylesheets = engine.engine.stylesheets ||= []
    engine.console.row('parse', stylesheet.operations, stylesheet.continuation)

    if stylesheets.indexOf(stylesheet) == -1
      for el, index in stylesheets
        break unless engine.queries.comparePosition(el, stylesheet, operation, operation)
      stylesheets.splice index, 0, stylesheet
    engine.stylesheets[stylesheet.continuation] = stylesheet
    stylesheet.dirty = true

    return


  @operations: [
    ['eval',  ['[*=]', ['tag', 'style'], 'type', 'text/gss']]
    ['load',  ['[*=]', ['tag', 'link' ], 'type', 'text/gss']]
  ]

  @perform: (engine) ->
    if engine.stylesheets
      for stylesheet in engine.stylesheets
        @evaluate(engine, stylesheet)
    @

  @evaluate: (engine, stylesheet) ->
    return unless stylesheet.dirty
    stylesheet.dirty = undefined
    if stylesheet.getAttribute('scoped')?
      scope = stylesheet.parentNode

    engine.solve(stylesheet.operations, stylesheet.continuation, scope)

  @complete: (engine) ->
    @perform(engine)
    if engine.blocking == 0
      engine.blocking = undefined
      engine.engine.commit(undefined, undefined, true)

  @compile: (engine) ->
    @CanonicalizeSelectorRegExp = new RegExp(
      "[$][a-z0-9]+[" + engine.queries.DESCEND + "]\s*", "gi"
    )
    @CleanupSelectorRegExp = new RegExp(engine.queries.DESCEND, 'g') 
    
    engine.engine.solve 'Document', 'stylesheets', @operations

    if !engine.blocking && engine.stylesheets
      @complete(engine)

  @update: (engine, operation, property, value, stylesheet, rule) ->
    watchers = @getWatchers(engine, stylesheet)
    dump = @getStylesheet(engine, stylesheet)
    sheet = dump.sheet
    needle = @getOperation(operation, watchers, rule)
    previous = []

    for item, index in watchers
      break if index >= needle
      if ops = watchers[index]
        other = @getRule(watchers[ops[0]][0])
        if previous.indexOf(other) == -1
          previous.push(other)
    unless sheet
      if dump.parentNode
        dump.parentNode.removeChild(dump)
      return 
    rules = sheet.rules || sheet.cssRules
    

    if needle != operation.index || value == ''
      generated = rules[previous.length]
      generated.style[property] = value

      next = undefined
      if needle == operation.index
        needle++
      for index in [needle ... watchers.length]
        if ops = watchers[index]
          next = @getRule(watchers[ops[0]][0])
          if next != rule
            sheet.deleteRule(previous.length)
          break
      if !next
        sheet.deleteRule(previous.length)
    else
      body = property + ':' + value
      selectors = @getSelector(operation)
      index = sheet.insertRule(selectors + "{" + body + "}", previous.length)
    return true


  @getRule: (operation) ->
    rule = operation
    while rule = rule.parent
      if rule[0] == 'rule'
        return rule
    return

  @getStylesheet: (engine, stylesheet) ->
    unless sheet = (engine.stylesheets.dumps ||= {})[stylesheet._gss_id]
      sheet = engine.stylesheets.dumps[stylesheet._gss_id]= document.createElement('STYLE')
      stylesheet.parentNode.insertBefore(sheet, stylesheet.nextSibling)
    return sheet

  @getWatchers: (engine, stylesheet) ->
    return (engine.stylesheets.watchers ||= {})[stylesheet._gss_id] ||= []

  @getOperation: (operation, watchers, rule) ->
    needle = operation.index
    for other in rule.properties
      if watchers[other]?.length
        needle = other
        break
    return needle

  # dump style into native stylesheet rule
  @set: (engine, operation, continuation, stylesheet, element, property, value) ->
    if rule = @getRule(operation)
      if @watch engine, operation, continuation, stylesheet
        if @update engine, operation, property, value, stylesheet, rule
          engine.engine.restyled = true

      return true

  @block: (engine) ->
    engine.blocking = (engine.blocking || 0) + 1

  @unblock: (engine) ->
    return --engine.blocking == 0

  @remove: (engine, continuation) ->
    if engine.stylesheets
      for stylesheet in engine.stylesheets
        if watchers = @getWatchers(engine, stylesheet)
          if operations = watchers[continuation]
            for operation in operations by -1
              @unwatch(engine, operation, continuation, stylesheet, watchers)
    return

  @watch: (engine, operation, continuation, stylesheet) ->
    watchers = @getWatchers(engine, stylesheet)

    meta = (watchers[operation.index] ||= [])
    if meta.indexOf(continuation) > -1
      return
    (watchers[continuation] ||= []).push(operation)
    return meta.push(continuation) == 1

  @unwatch: (engine, operation, continuation, stylesheet, watchers) ->
    watchers ?= @getWatchers(engine, stylesheet)

    index = operation.index

    meta = watchers[index]
    meta.splice meta.indexOf(continuation), 1

    observers = watchers[continuation]
    observers.splice observers.indexOf(operation), 1

    unless observers.length
      delete watchers[continuation]

    unless meta.length
      delete watchers[index]
      @update engine, operation, operation[1], '', stylesheet, @getRule(operation)
  
  @export: ->
    sheet = []
    for id, style of engine.stylesheets.dumps
      for rule in (style.sheet.rules || style.sheet.cssRules)
        text = rule.cssText.replace /\[matches~="(.*?)"\]/g, (m, selector) ->
          selector.replace(/@\d+/g, '').replace(/↓/g, ' ')
        sheet.push text

    return sheet.join('')

  @getSelector: (operation) ->
    return @getSelectors(operation).join(', ')

  @getSelectors: (operation) ->
    parent = operation
    results = wrapped = custom = undefined

    # Iterate rules
    while parent

      # Append condition id to path
      if parent[0] == 'if'
        if results
          for result, index in results
            if result.substring(0, 11) != '[matches~="'
              result = @getCustomSelector(result)
            results[index] = result.substring(0, 11) + parent.uid + @prototype.DESCEND + result.substring(11)
      
      # Add rule selector to path
      else if parent[0] == 'rule'
        cmd = parent[1].command
        selectors = cmd.path

        if parent[1][0] == ','
          paths = parent[1].slice(1).map (item) -> 
            return item.command.selector || item.command.path
          groups = cmd.selector?.split(',') || []
        else
          paths = [selectors]
          groups = [cmd.selector || (cmd.key == cmd.path && cmd.key)]

        # Prepend selectors with selectors of a parent rule
        if results?.length
          bits = selectors.split(',')

          update = []
          for result in results
            if result.substring(0, 11) == '[matches~="'
              update.push result.substring(0, 11) + selectors + @prototype.DESCEND + result.substring(11)
            else
              for bit, index in bits
                if groups[index] != bit
                  update.push @getCustomSelector(selectors) + ' ' + result
                else 
                  update.push bit + ' ' + result

          results = update
        # Return all selectors
        else 

          results = selectors.split(',').map (path, index) =>
            if path != groups[index]
              @getCustomSelector(selectors)
            else
              path
      parent = parent.parent

    for result, index in results
      results[index] = results[index].replace(@CleanupSelectorRegExp, '')
    return results

  @getCustomSelector: (selector) ->
    return '[matches~="' + selector.replace(/\s+/, @prototype.DESCEND) + '"]'

  @getCanonicalSelector: (selector) ->
    selector = selector.trim()
    selector = selector.
      replace(@CanonicalizeSelectorRegExp, ' ').
      replace(/\s+/g, @prototype.DESCEND)#.
      #replace(@engine.Operation.CleanupSelectorRegExp, '')
    return selector

    
module.exports = Stylesheet