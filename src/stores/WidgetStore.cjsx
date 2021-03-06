Reflux = require("reflux")

GridOptionStore = require("stores/GridOptionStore.cjsx")
LibraryStore    = require("stores/LibraryStore.cjsx")

Actions = require("actions.cjsx")
WidgetActions = Actions.WidgetActions
GridActions = Actions.GridActions

WidgetStore = Reflux.createStore
    storeName: "WidgetStore"
    # actions this store listens to
    listenables: [WidgetActions]

    mixins: [Reflux.connect(LibraryStore, "library")]

    # default state
    widgets: [
        #{
        #    widgetKind: "timer"
        #    layouts:
        #        large:
        #            position: {x: 0, y: 0}
        #            dimension: {x: 2, y: 1}
        #    uuid: "fake-uuid"
        #}
    ]

    getWidgetClass: (widgetInstance) ->
        console.log this
        #return this.library.getWidgetClass(widgetInstance)
        #switch widgetInstance.widgetKind
        #    when "timer"    then return require "widgets/Time.cjsx"
        #    when "mail"     then return require "widgets/Mail.cjsx"
        #    when "weather"  then return require "widgets/Weather.cjsx"
        #    when "picture"  then return require "widgets/Picture.cjsx"
        #    when "dynamic" then return this.getDynamicWidget "dynamic"
        #    # when "dynamic" then return require "widgets/DynamicWidget.cjsx"
        #    else return require "widgets/Time.cjsx"

    getWidgetById: (widgetId) ->
      found = (i for i in this.widgets when i.uuid is widgetId)[0]
      if found
        return found
      else
        return null

    getInvalidWidgets: (grid, ignoreWidgets) ->
      relevantWidgets =
          (w for w in this.widgets when w.uuid not in ignoreWidgets)

      isOpen = (x,y) ->
          0 <= x and x < grid.gridDim.x and
          0 <= y and y < grid.gridDim.y
      badWidgets = []
      for widget in relevantWidgets
          wl = widget.layouts[grid.settingName]
          if wl?
              if not isOpen(wl.dimension.x + (wl.position.x - 1), wl.dimension.y + (wl.position.y - 1))
                  badWidgets.push(widget.uuid)
      return badWidgets


    findOccupiedSpaces: (grid, ignoreWidgets) ->
        # init OccupiedSpaces
        occupiedSpaces = new Array(grid.gridDim.x)
        for ix in [0 .. (grid.gridDim.x - 1)]
            occupiedSpaces[ix] = new Array(grid.gridDim.y)
            for iy in [0 .. (grid.gridDim.y - 1)]
                occupiedSpaces[ix][iy] = false

        # fill spaces occuupied by widgets
        relevantWidgets =
            (w for w in this.widgets when w.uuid not in ignoreWidgets)
        for widget in relevantWidgets
            wl = widget.layouts[grid.settingName]
            if wl?
                for ix in [0..wl.dimension.x - 1]
                    for iy in [0..wl.dimension.y - 1]
                        xo = wl.position.x + ix
                        yo = wl.position.y + iy
                        occupiedSpaces[xo][yo] = true
        return occupiedSpaces

    # the initial state of the store from localstorage
    # if that fails, use the default
    getInitialState: ->
        storageState = window.localStorage.getItem("widgets")
        if storageState
            this.widgets = JSON.parse(storageState)
        return this.widgets

    generateUUID: () ->
        # Doesn't actually conform to the uuid spec
        # These IDs are just "unique enough" to be unique widget IDs
        # We also assume collisions are unlikely enough to not matter
        genHexString = (length) ->
            return (Math.floor(Math.pow(16, length) * Math.random())).toString(16)

        return genHexString(8) + "-" +
            genHexString(4) + "-" +
            genHexString(4) + "-" +
            genHexString(4) + "-" +
            genHexString(12)
        # Closer to UUID spec, but it feels unnecessarily complicated
        #genY = () ->
        #    return ["8", "9", "a", "b"][Math.floor(Math.random() * 4)]
        #return (genHexString(8) + "-" + genHexString(4) + "-4" + genHexString(3) + "-" + genY() + genHexString(3) + "-" + genHexString(12)



    onAddWidget: (kind) ->
        console.log "Trying to add widget", kind
        grid = GridOptionStore.getCurrentGrid()
        gridDim = grid.gridDim
        # TOTALLY ARBITRARY
        widgetDim = {x: 2, y: 1}

        # Populate occupation grid
        console.log gridDim
        occupied = new Array(gridDim.x)
        for i in [0..gridDim.x]
            occupied[i] = new Array(gridDim.y).fill(0)

        for w in this.widgets
            pos = w.layouts.large.position
            dim = w.layouts.large.dimension
            for x in [0..dim.x - 1]
                for y in [0..dim.y - 1]
                    occupied[pos.x + x][pos.y + y] = 1

        # Find the top-left-most space to put the widget in
        wx = -1
        wy = -1
        # This is disgusting and I hate myself
        # Y first to prefer up to left
        for y in [0..gridDim.y - 1]
            feasible = true
            gridRestricted = false
            for x in [0..gridDim.x - widgetDim.x]
                feasible = true
                console.log y, x
                for i in [0..widgetDim.x - 1]
                    for j in [0..widgetDim.y - 1]
                        if occupied[x + i][y + j] == 1
                            feasible = false
                if feasible or (y == gridDim.y - 1 and feasible)
                    wx = x
                    wy = y
                    break

            if y == gridDim.y - 1 and feasible
                console.log "semi-feasible", y, x

            if feasible
                break

        if wx == -1 and wy == -1
            wx = 0
            wy = gridDim.y

        widget = {
            widgetKind: kind
            layouts:
                large:
                    position: {x: wx, y: wy}
                    desiredPosition: {x: wx, y: wy}
                    dimension: widgetDim
            uuid: this.generateUUID()
        }

        if wy + widgetDim.y > gridDim.y
            # Assuming the grid is wide enough for the new widget,
            # Grow the grid
            gridDim = {
                x: gridDim.x
                y: wy + widgetDim.y
            }
            grid.gridDim = gridDim
            # 0 should be the current layout instead
            GridActions.changeGridOptions(0, grid)


        this.widgets.push(widget)
        this.cacheAndTrigger()

    # moves a widget so its top left corner is at grid position x,y
    # assumes safe to move
    onMoveWidget: (widgetID, layout, x, y) ->
        for widget in this.widgets
            if widget.uuid == widgetID
                widget.layouts[layout].position =
                    x: x
                    y: y
                console.log "moved widget '#{widgetID}'"
                console.log this.widgets
                break
        this.cacheAndTrigger()

    onRemoveWidget: (widgetID) ->
        console.log("trying to remove widget", widgetID)
        for widgetIndex in [0..this.widgets.length]
            if this.widgets[widgetIndex].uuid == widgetID
                console.log("removing widget with ID", widgetID)
                this.widgets.splice(widgetIndex, 1)
                this.cacheAndTrigger()
                break

    onResizeWidget: (widgetID, layout, width, height) ->
        console.log("resizing widget", widgetID)
        for widget in this.widgets
            if widget.uuid == widgetID
                widget.layouts[layout].dimension =
                    {x: width, y:height}
                this.trigger(this.widgets)
                return

    cacheAndTrigger: () ->
        this.trigger(this.widgets)
        window.localStorage.setItem(
            "widgets",
            JSON.stringify(this.widgets))



module.exports = WidgetStore
