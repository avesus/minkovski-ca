"use strict";

bigInt = require "big-integer"
M = require "./matrix2.coffee"
B = require "./bigmatrix.coffee"

{convexQuadPoints} = require "./geometry.coffee"
{qform}  = require "./mathutil.coffee"
{Coord, makeCoord} = require "./world.coffee"
{drawAllBranches} = require "./ode_curve_drawing.coffee"
#CA = require "./ca.coffee"


# meaning of the coordinates:
#
#  Global: integer coordinates, large ints.
#
#  local: integer. local = bigViewMatrix * (global - center)
#
#      where
#         bigViewMatrix : det1 big int matrix, power of the lattice invariant matrix.
#
#  graphical: float coordinate on the screen, relative to the view center.
#        graphical = viewMatrix * latticeMatrix * local
#
#      where
#          viewMatrix : flat matrix, either pure rotation or pure pseudo-rotation
#  

exports.View = class View
  constructor: (@world) ->
    @viewMatrix = M.eye()
    @viewMatrixBig = B.eye()
    @center = makeCoord 0, 0
    @integerRotationsCount = 0
    @angle = 0.0
    @scale = 8
    @cellSize = 4
    
    @palette = ["#000000", "#fe8f0f", "#f7325e", "#7dc410", "#0264ed"]
    @equidistantColor = "#808080"
    @emptyCellColor = "#c0c0c0"
    @connectionLineColor = "rgba(127,127,127,0.5)"
    
    @selectedCell = [0,0] #null or [ix, iy] pair. Small integers, relative to the view center.
    @highlightedCell = null
    @showConnection = true
    @showEmpty = false

    @styleConnectionLine = "#efe"
    @selectionBox = null
    
    @pasteLocation = null
    @pasteSelection = null

  setSelectionBox: (p1, p2) -> @selectionBox = [p1,p2]
  clearSelectionBox: -> @selectionBox = null
  copySelection: (canvas)->
    if @selectionBox is null then return null
    dx = canvas.width/2
    dy = canvas.height/2
    [[x1,y1], [x2,y2]] = @selectionBox
    x1 -= dx
    y1 -= dy
    x2 -= dx
    y2 -= dy
    T = @_combinedViewMatrix()
    invT = M.inv T
    #quad in the screen coordinates
    quad = [ [x1, y1], [x2, y1], [x2, y2], [x1, y2]]

    #transform it to the integer lattice
    iquad  = (M.mulv(invT, vi) for vi in quad)
    
    invViewBig = B.adjoint @viewMatrixBig

    points = []
    sumx = 0
    sumy = 0
    convexQuadPoints iquad, (ix, iy) =>
      # [ix,iy] is in the "local" coordinates.
      cellCoord = @local2global [ix, iy]
      cellState = @world.getCell(cellCoord)    
      if cellState isnt 0
        points.push [ix, iy, cellState]
        sumx += ix
        sumy += iy
    if points.length isnt 0
      xc = (sumx/points.length)|0
      yc = (sumy/points.length)|0
      points = ([x-xc,y-yc,s] for [x,y,s] in points)
    return points
    
  setHighlightCell: (v)-> @highlightedCell = v
  incrementAngle: (da) ->
    @angle += da
    if @angle < -0.51*@world.angle
      @angle += @world.angle
      @integerRotationsCount += 1
      @_premultiplyViewMatrixBy @world.m
    else if @angle > 0.51*@world.angle
      @angle -= @world.angle
      @integerRotationsCount -= 1
      @_premultiplyViewMatrixBy M.adjoint @world.m
      
    @setAngle @angle

  #moltiply view matrix by a given small matrix (it could only be a power of world.m)
  _premultiplyViewMatrixBy: (p)->
    @viewMatrixBig = B.mul B.tobig(p), @viewMatrixBig
    
    #update other parameters that depend on view matrix
    if @selectedCell isnt null
      @selectedCell = M.mulv p, @selectedCell
      if Math.abs(@selectedCell[0]) + Math.abs(@selectedCell[1]) > 1000000
        console.log "Selection lost because of too big skew"
        @selectedCell = null
        
  getTotalAngle: -> @angle + @integerRotationsCount*@world.angle

  setLocation: (newCenter, fullAngle) ->
    @center = newCenter
    nRotations = fullAngle / @world.angle
    fullRoations = Math.round(nRotations)|0
    @setAngle fullAngle - fullRoations*@world.angle
    @viewMatrixBig = if fullRoations >= 0
      B.pow @world.m, fullRoations
    else
      B.pow B.adjoint(@world.m), -fullRoations
    
    
  
  setAngle: (v)->
    @angle = v
    @viewMatrix = if @world.isEuclidean
        M.rot v
      else
        k = Math.exp v
        M.diag k, 1.0/k
  #translate center in "local" integer coordinates. dv must be a small integer vector
  translateCenterLocal: (dv)->
    dvGlobal = B.mulv B.adjoint(@viewMatrixBig), dv
    @center = @center.translate dvGlobal
    if @selectedCell isnt null
      @selectedCell = M.vcombine @selectedCell, -1, dv
    
  #cpnvert screen coordinates to integer translation relative to view center.
  screen2localInteger: (canvas, sxy) ->
    w = canvas.width
    h = canvas.height
    T = M.smul @scale, M.mul @viewMatrix, M.inv(@world.latticeMatrix)
    invT = M.inv T
    [sx,sy] = sxy
    [ix,iy] = M.mulv invT, [sx-w*0.5,sy-h*0.5]
    [Math.round(ix) | 0, Math.round(iy) | 0]

  #convert local integer coordinates to global Coord instance
  local2global: (xy) ->
    @center.translate B.mulv B.adjoint(@viewMatrixBig), xy
    
    
  drawEquidistant: (canvas, context, x0, y0, xy)->

    #x ranges from 0 to width
    # y = y0 + xy/(x-x0)
    #
    # y=a/x
    #
      # dx should be proportional to y''/(1+y'^2)
      # 
    w = canvas.width
    h = canvas.height
    context.save()
    context.translate x0, y0

    #A, x0, y0, x1, y1, step
    context.beginPath()
    if @world.isEuclidean
      k = -1.0/(xy*@scale**2)
      mtx = [k, 0, 0, k]
    else
      k = -1.0/(xy*@scale**2)
      mtx = [0,k,k,0]
    
    for segment in drawAllBranches(mtx, -x0, -y0, w-x0, h-y0, 0.1)
      for [x,y],i in segment
        if i is 0
          context.moveTo x, y
        else
          context.lineTo x, y
    context.strokeStyle = @equidistantColor
    context.setLineDash [5, 5]
    context.stroke()
    
    #find intersection points
    context.restore()

  drawControls: (canvas, context)->
    width = canvas.width
    height = canvas.height

    dx = width * 0.5
    dy = height * 0.5
    T = @_combinedViewMatrix()
    #invT = M.inv T

    context.clearRect(0, 0, canvas.width, canvas.height)
    
    if @selectedCell isnt null
      [selx, sely] = M.mulv T, @selectedCell
      for ci in @world.c
        @drawEquidistant canvas, context, selx+dx, sely+dy, ci
      
      context.beginPath();
      context.arc(selx+dx, sely+dy, @cellSize*1.5, 0, Math.PI*2, true)
      context.closePath()
      context.strokeStyle = "green"
      context.stroke()
    if @highlightedCell isnt null
      [hx, hy] = M.mulv T, @highlightedCell
      
      context.beginPath();
      context.arc(hx+dx, hy+dy, @cellSize*1.5, 0, Math.PI*2, true)
      context.closePath()
      context.strokeStyle = "#0808ff"
      context.stroke()
    if @pasteLocation isnt null and @pasteSelection isnt null
      [px, py]=@pasteLocation
      for [x,y,s] in @pasteSelection
        [sx,sy] = M.mulv T, [x+px, y+py]

        context.beginPath();
        context.arc(sx+dx, sy+dy, @cellSize, 0, Math.PI*2, true)
        context.closePath()
        context.strokeStyle = @getStateColor s
        context.stroke()
      
    if @selectionBox isnt null
      [[x1,y1],[x2,y2]] = @selectionBox
      context.fillStyle = "rgba(0,0,255,0.3)"
      context.fillRect x1, y1, x2-x1, y2-y1
      
    #context.save()
    #context.translate width/2, height/2
    #context.restore()

  #map "local" to "screen"
  _combinedViewMatrix: -> M.smul @scale, M.mul @viewMatrix, M.inv(@world.latticeMatrix)
  setPasteLocation: (localCell, selection)->
    @pasteLocation = localCell
    @pasteSelection = selection

  getStateColor: (s) -> @palette[(s-1)%@palette.length]
  
  drawGrid: (canvas, context)->
    scale = @scale
    width = canvas.width
    height = canvas.height

    dx = width * 0.5
    dy = height * 0.5

    #Combined transformation matrix, from integer lattice to screen
    T = @_combinedViewMatrix()
    invT = M.inv T

    #quad in the screen coordinates
    quad = [ [-dx, dy], [-dx, -dy], [dx, -dy], [dx, dy]]

    #transform it to the integer lattice
    iquad  = (M.mulv(invT, vi) for vi in quad)

    context.clearRect(0, 0, canvas.width, canvas.height)
    #get points and draw them

    invViewBig = B.adjoint @viewMatrixBig
    context.save()
    context.translate width/2, height/2
    convexQuadPoints iquad, (ix, iy) =>
      # [ix,iy] is in the "local" coordinates.
      # 
      #convert integer points back to screen coordinates
      [sx, sy] = M.mulv T, [ix,iy]

      cellCoord = @local2global [ix, iy]
      cellState = @world.getCell(cellCoord)
      if cellState is 0
        if @showEmpty
          context.strokeStyle =@emptyCellColor
          context.beginPath()
          context.arc(sx, sy, @cellSize, 0, Math.PI*2, true)
          context.closePath()
          context.stroke()        
      else
        context.beginPath();
        context.arc(sx, sy, @cellSize, 0, Math.PI*2, true)
        context.closePath()
        context.fillStyle = @getStateColor cellState
        context.fill()
        if @showConnection and (@world.connections isnt null)
          ccell = @world.connections.get cellCoord, null

          context.strokeStyle = @connectionLineColor

          if ccell isnt null
            #iterate over alive neighbors of a cell
            for neighbor in ccell.neighbors
              #to avoid double lines
              continue if neighbor.coord.hash > cellCoord.hash
              continue if @world.getCell(neighbor.coord) is 0
              
              #find coordinates of the neighbor in screen coords
              [nix,niy] = B.mulv @viewMatrixBig, @center.offset neighbor.coord
              #if neighbor is relatively close
              if nix.isSmall and niy.isSmall
                #coordinates of the neighbor on the screen
                [nx, ny] = M.mulv T, [nix.value, niy.value]
                #draw the line
                context.beginPath()
                context.moveTo sx, sy
                context.lineTo nx, ny
                context.stroke()
    context.restore()
      
    
