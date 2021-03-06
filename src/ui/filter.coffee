Util = require('../util')

$ = Util.$
_t = Util.TranslationString

NS = 'annotator-filter'


class Filter
  # Common classes used to change plugin state.
  classes:
    active: 'annotator-filter-active'
    hl:
      hide: 'annotator-hl-filtered'
      active: 'annotator-hl-active'

  # HTML templates for the plugin UI.
  html:
    element: """
      <div class="annotator-filter">
        <strong>#{_t('Navigate:')}</strong>
        <span class="annotator-filter-navigation">
          <button type="button"
                  class="annotator-filter-previous">#{_t('Previous')}</button>
          <button type="button"
                  class="annotator-filter-next">#{_t('Next')}</button>
        </span>
        <strong>#{_t('Filter by:')}</strong>
      </div>
      """
    filter: """
      <span class="annotator-filter-property">
        <label></label>
        <input/>
        <button type="button"
                class="annotator-filter-clear">#{_t('Clear')}</button>
      </span>
      """

  # Default options for the plugin.
  options:
    # A CSS selector or Element to append the plugin toolbar to.
    appendTo: 'body'

    # A CSS selector or Element to find and filter highlights in.
    filterElement: 'body'

    # An array of filters can be provided on initialisation.
    filters: []

    # Adds a default filter on annotations.
    addAnnotationFilter: true

    # Public: Determines if the property is contained within the provided
    # annotation property. Default is to split the string on spaces and only
    # return true if all keywords are contained in the string. This method
    # can be overridden by the user when initialising the plugin.
    #
    # string   - An input String from the fitler.
    # property - The annotation propery to query.
    #
    # Examples
    #
    #   plugin.option.getKeywords('hello', 'hello world how are you?')
    #   # => Returns true
    #
    #   plugin.option.getKeywords('hello bill', 'hello world how are you?')
    #   # => Returns false
    #
    # Returns an Array of keyword Strings.
    isFiltered: (input, property) ->
      return false unless input and property

      for keyword in (input.split /\s+/)
        return false if property.indexOf(keyword) == -1

      return true

  # Public: Creates a new instance of the Filter.
  #
  # options - An Object literal of options.
  #
  # Returns a new instance of the Filter plugin.
  constructor: (options) ->
    @options = $.extend(true, {}, @options, options)
    @element = $(@html.element).appendTo(@options.appendTo)

    @filter  = $(@html.filter)
    @filters = []
    @current  = 0

    for filter in @options.filters
      this.addFilter(filter)

    this.updateHighlights()

    filterInput = '.annotator-filter-property input'
    @element
      .on("focus.#{NS}", filterInput, this._onFilterFocus)
      .on("blur.#{NS}", filterInput, this._onFilterBlur)
      .on("keyup.#{NS}", filterInput, this._onFilterKeyup)
      .on("click.#{NS}", '.annotator-filter-previous', this._onPreviousClick)
      .on("click.#{NS}", '.annotator-filter-next', this._onNextClick)
      .on("click.#{NS}", '.annotator-filter-clear', this._onClearClick)

    this._insertSpacer()

    if @options.addAnnotationFilter == true
      this.addFilter {label: _t('Annotation'), property: 'text'}

  # Public: remove the filter plugin instance and unbind events.
  #
  # Returns nothing.
  destroy: ->
    html = $('html')
    currentMargin = parseInt(html.css('padding-top'), 10) || 0
    html.css('padding-top', currentMargin - @element.outerHeight())
    @element.off(".#{NS}")
    @element.remove()

  # Adds margin to the current document to ensure that the annotation toolbar
  # doesn't cover the page when not scrolled.
  #
  # Returns itself
  _insertSpacer: ->
    html = $('html')
    currentMargin = parseInt(html.css('padding-top'), 10) || 0
    html.css('padding-top', currentMargin + @element.outerHeight())
    this

  # Public: Adds a filter to the toolbar. The filter must have both a label
  # and a property of an annotation object to filter on.
  #
  # options - An Object literal containing the filters options.
  #           label      - A public facing String to represent the filter.
  #           property   - An annotation property String to filter on.
  #           isFiltered - A callback Function that recieves the field input
  #                        value and the annotation property value. See
  #                        @options.isFiltered() for details.
  #
  # Examples
  #
  #   # Set up a filter to filter on the annotation.user property.
  #   filter.addFilter({
  #     label: User,
  #     property: 'user'
  #   })
  #
  # Returns itself to allow chaining.
  addFilter: (options) ->
    filter = $.extend({
      label: ''
      property: ''
      isFiltered: @options.isFiltered
    }, options)

    # Skip if a filter for this property has been loaded.
    unless (f for f in @filters when f.property == filter.property).length
      filter.id = 'annotator-filter-' + filter.property
      filter.annotations = []
      filter.element = @filter.clone().appendTo(@element)
      filter.element.find('label')
        .html(filter.label)
        .attr('for', filter.id)
      filter.element.find('input')
        .attr({
          id: filter.id
          placeholder: _t('Filter by ') + filter.label + '\u2026'
        })
      filter.element.find('button').hide()

      # Add the filter to the elements data store.
      filter.element.data 'filter', filter

      @filters.push filter

    this

  # Public: Updates the filter.annotations property. Then updates the state
  # of the elements in the DOM. Calls the filter.isFiltered() method to
  # determine if the annotation should remain.
  #
  # filter - A filter Object from @filters
  #
  # Examples
  #
  #   filter.updateFilter(myFilter)
  #
  # Returns itself for chaining
  updateFilter: (filter) ->
    filter.annotations = []

    this.updateHighlights()
    this.resetHighlights()
    input = $.trim filter.element.find('input').val()

    if input
      annotations = @highlights.map -> $(this).data('annotation')

      for annotation in $.makeArray(annotations)
        property = annotation[filter.property]
        if filter.isFiltered input, property
          filter.annotations.push annotation

      this.filterHighlights()

  # Public: Updates the @highlights property with the latest highlight
  # elements in the DOM.
  #
  # Returns a jQuery collection of the highlight elements.
  updateHighlights: =>
    # Ignore any hidden highlights.
    @highlights = $(@options.filterElement).find('.annotator-hl:visible')
    @filtered   = @highlights.not(@classes.hl.hide)

  # Public: Runs through each of the filters and removes all highlights not
  # currently in scope.
  #
  # Returns itself for chaining.
  filterHighlights: ->
    activeFilters = $.grep @filters, (filter) -> !!filter.annotations.length

    filtered = activeFilters[0]?.annotations || []
    if activeFilters.length > 1
      # If there are more than one filter then only annotations matched in every
      # filter should remain.
      annotations = []


      $.each activeFilters, ->
        $.merge(annotations, this.annotations)

      uniques  = []
      filtered = []
      $.each annotations, ->
        if $.inArray(this, uniques) == -1
          uniques.push this
        else
          filtered.push this


    highlights = @highlights
    for annotation, index in filtered
      highlights = highlights.not(annotation._local.highlights)

    highlights.addClass(@classes.hl.hide)

    @filtered = @highlights.not(@classes.hl.hide)
    this

  # Public: Removes hidden class from all annotations.
  #
  # Returns itself for chaining.
  resetHighlights: ->
    @highlights.removeClass(@classes.hl.hide)
    @filtered = @highlights
    this

  # Updates the filter field on focus.
  #
  # event - A focus Event object.
  #
  # Returns nothing
  _onFilterFocus: (event) =>
    input = $(event.target)
    input.parent().addClass(@classes.active)
    input.next('button').show()

  # Updates the filter field on blur.
  #
  # event - A blur Event object.
  #
  # Returns nothing.
  _onFilterBlur: (event) =>
    unless event.target.value
      input = $(event.target)
      input.parent().removeClass(@classes.active)
      input.next('button').hide()

  # Updates the filter based on the id of the filter element.
  #
  # event - A keyup Event
  #
  # Returns nothing.
  _onFilterKeyup: (event) =>
    filter = $(event.target).parent().data('filter')
    this.updateFilter filter if filter

  # Locates the next/previous highlighted element in @highlights from the
  # current one or goes to the very first/last element respectively.
  #
  # previous - If true finds the previously highlighted element.
  #
  # Returns itself.
  _findNextHighlight: (previous) ->
    return this unless @highlights.length

    offset      = if previous then 0    else -1
    resetOffset = if previous then -1   else 0
    operator    = if previous then 'lt' else 'gt'

    active  = @highlights.not('.' + @classes.hl.hide)
    current = active.filter('.' + @classes.hl.active)
    current = active.eq(offset) unless current.length

    annotation = current.data 'annotation'

    index = active.index current[0]
    next  = active.filter(":#{operator}(#{index})")
                  .not(annotation._local.highlights)
                  .eq(resetOffset)
    next  = active.eq(resetOffset) unless next.length

    this._scrollToHighlight next.data('annotation')._local.highlights

  # Locates the next highlighted element in @highlights from the current one
  # or goes to the very first element.
  #
  # event - A click Event.
  #
  # Returns nothing
  _onNextClick: (event) =>
    this._findNextHighlight()

  # Locates the previous highlighted element in @highlights from the current one
  # or goes to the very last element.
  #
  # event - A click Event.
  #
  # Returns nothing
  _onPreviousClick: (event) =>
    this._findNextHighlight true

  # Scrolls to the highlight provided. An adds an active class to it.
  #
  # highlight - Either highlight Element or an Array of elements. This value
  #             is usually retrieved from annotation._local.highlights.
  #
  # Returns nothing.
  _scrollToHighlight: (highlight) ->
    highlight = $(highlight)

    @highlights.removeClass(@classes.hl.active)
    highlight.addClass(@classes.hl.active)

    $('html, body').animate({
      scrollTop: highlight.offset().top - (@element.height() + 20)
    }, 150)

  # Clears the relevant input when the clear button is clicked.
  #
  # event - A click Event object.
  #
  # Returns nothing.
  _onClearClick: (event) ->
    $(event.target).prev('input').val('').keyup().blur()


exports.Filter = Filter
