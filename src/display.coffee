# compares whether two arrays contain the same values
unorderedEquals = (arr1, arr2) -> _.difference(arr1, arr2).length == 0

class VisConnector
	constructor: ->
		chrome.runtime.onMessage.addListener (message, sender, sendResponse) =>
			if message.type == "syn"
				@initConnection(sender.tab.id)
				@dataSets = @processPayload(message.payload)
				@tableViews = []
				$.each @dataSets, (i, dataSet) =>
					dataSet.dataTypes = @inferTypes(dataSet.d3Data)
					dataSet.visTypes = @inferTypes(dataSet.visData)
					dataSet.mappings = getMappings(dataSet)
				angularScope = angular.element($('body')).scope()
				angularScope.$apply =>
					angularScope.mappings = getMappings(@dataSets[0])
					angularScope.dataSets = @dataSets
					
			else if message.type == "markUpdate"
				newMarkInfo = 
					'tag': message.payload.nodeText
					'css': message.payload.cssText
					'bbox': message.payload.bbox
				angularScope = angular.element($('body')).scope()
				angularScope.$apply =>
					#console.log "applying mark update for id: #{message.payload.id}"
					for dataSet, index in angularScope.dataSets
						markIndex = dataSet['ids'].indexOf(message.payload.id)
						if markIndex != -1
							#console.log "applying mark update, markIndex=#{markIndex}"
							angularScope.dataSets[index]['node'][markIndex] = newMarkInfo
							
			setupModal()
		
	initConnection: (tabId) =>
		@port = chrome.tabs.connect tabId, {name: 'd3annot'}
	
	sendUpdate: (message) =>
		@port.postMessage(message)
	
	getDataSetTable: (dataSetId) =>
		return @tableViews[dataSetId].dataTable

	inferTypes: (dataObj) ->
		dataTypes = {}
		for dataAttr of dataObj
			dataTypes[dataAttr] = @inferDataColType(dataObj[dataAttr])
			if dataTypes[dataAttr] == "numeric"
				newCol = _.map(dataObj[dataAttr], (d) -> +parseFloat(d).toFixed(3))
				dataObj[dataAttr] = newCol
		return dataTypes
		
	inferDataColType: (colData) ->
		isNum = true
		isNull = true
		for row in colData
			if row
				isNull = false
			if isNaN(parseFloat(row))
				isNum = false
		if isNum
			return "numeric"
		else if isNull
			return "null"
		else
			return "nominal"
				
	# How will we handle nonexistant fields?
	extractVisData: (node, nodeText, cssText, bbox) ->
		visRow = {}
		nodeAttrs = {}
		$.each node.attributes, (j, attr) ->
			nodeAttrs[attr.name] = attr.value
		node.style.cssText = cssText
		
		newNode = prepareMarkForDisplay(nodeText, cssText)
		svg = document.createElementNS("http://www.w3.org/2000/svg", "svg")
		canvasWidth = 20
		svg.setAttribute("width", "20")
		svg.setAttribute("height", "20")
		$('body')[0].appendChild(svg)
		svg.appendChild(newNode)
		styleFill = d3.select(newNode).style('fill')
		styleStroke = d3.select(newNode).style('stroke')
		$(svg).remove()
		
		visRow["shape"] = node.tagName.toLowerCase()

		if !styleFill
			visRow["color"] = nodeAttrs["fill"]			
		else
			visRow["color"] = styleFill
		if !styleStroke
			visRow["stroke"] = nodeAttrs["stroke"]
		else
			visRow["stroke"] = styleStroke
			
		visRow["stroke-width"] = nodeAttrs["stroke-width"]
		visRow["x-position"] = bbox.x
		visRow["y-position"] = bbox.y
		if visRow["shape"] == "circle"
			visRow["width"] = 2 * parseFloat(nodeAttrs["r"])
			visRow["height"] = 2 * parseFloat(nodeAttrs["r"])
			visRow["area"] = Math.PI * parseFloat(nodeAttrs["r"]) * parseFloat(nodeAttrs["r"])
		else
			visRow["width"] = bbox.width
			visRow["height"] = bbox.height
			visRow["area"] = bbox.width * bbox.height
			
		return visRow
		
	extractVisSchema: (node) ->
		shape = node.tagName.toLowerCase()
		return {"shape": [], "color": [], "stroke": [], \ 
							"stroke-width": [], "width": [], "height": [], "area": [], "x-position": [], "y-position": []}
		
	findSchema: (data, d3Data, tagName) ->
		thisSchema = null
		if d3Data instanceof Object
			thisSchema = Object.keys(d3Data)
		else
			thisSchema = ["scalar"]
			
		thisSchema.push(tagName)
		found = -1
		$.each data, (i, dataSet) ->
			if unorderedEquals(dataSet.schema, thisSchema)
				found = i
				return false
		return found
		
	processPayload: (payload) =>
		data = []
		schema_count = -1
	
		$.each payload, (i, obj) =>
			d3Data = obj.d3Data
			node = prepareMarkForDisplay(obj.nodeText, obj.cssText)
			schema = -1
			
			# object types require some schema thought
			if d3Data instanceof Object
				# check to see if we have a new schema	
				schema = @findSchema(data, d3Data, node.tagName)
				if schema == -1
					# if we find a property that isn't in a previous schema, create a new table.
					newSchema = Object.keys(d3Data)
					# schema should also contain the tagname/shape
					newSchema.push(node.tagName)
					schema_count++
					schema = schema_count
					data[schema] = {}
					data[schema].schema = newSchema
					# set the schema for data and visual attributes of this set
					data[schema].d3Data = {}
					data[schema].d3Data["d3_ID"] = []
					$.each Object.keys(d3Data), (j, key) ->
						data[schema].d3Data[key] = []
						
					data[schema].visData = @extractVisSchema(node)
					data[schema].visSchema = _.keys(data[schema].visData)
						
						
				# now let's add the data item to our structure
				$.each d3Data, (prop, val) ->
					data[schema].d3Data[prop].push(val)
				data[schema].d3Data["d3_ID"].push(obj.id)
			
			else
				if d3Data is undefined or d3Data is null
					return true
				# we just have a scalar data element
				schema = @findSchema(data, d3Data, node.tagName)
				if schema == -1
					schema_count++
					schema = schema_count
					data[schema] = {}
					data[schema].schema = ["scalar"]
					data[schema].d3Data = {"d3_ID": [obj.id], "scalar": [d3Data]}
					data[schema].visData = @extractVisSchema(node)
					data[schema].visSchema = _.keys(data[schema].visData)
				else
					data[schema].d3Data["scalar"].push(d3Data)
					data[schema].d3Data["d3_ID"].push(obj.id)
					
			
			# finally extract the visual attributes
			visRow = @extractVisData(node, obj.nodeText, obj.cssText, obj.bbox)
			$.each Object.keys(data[schema].visData), (j, key) ->
				data[schema].visData[key].push(visRow[key])
		
			# and add the node
			if data[schema].hasOwnProperty('node')
				data[schema]['node'].push({'tag': obj.nodeText, 'css': obj.cssText, 'bbox': obj.bbox})
			else
				data[schema]['node'] = [{'tag': obj.nodeText, 'css': obj.cssText, 'bbox': obj.bbox}]
		
			if data[schema].hasOwnProperty('ids')
				data[schema]['ids'].push(obj.id)
			else
				data[schema]['ids'] = [obj.id]
		
		$.each data, (i, dataSet) ->
			dataSet.numEls = dataSet.d3Data[dataSet.schema[0]].length
			
		return data

getBBoxWithoutCanvas = (node) ->
	svg = document.createElementNS("http://www.w3.org/2000/svg", "svg")
	svg.appendChild(node)
	$('body')[0].appendChild(svg)
	bbox = node.getBBox()
	svg.remove()
	return bbox

getMappings = (dataSet) ->
	mappings = {}
	for dataAttr of dataSet.d3Data
		for visAttr of dataSet.visData
			mapping = getMapping(dataAttr, visAttr, dataSet)
			if mapping
				#console.log ("Found mapping between: " + dataAttr + " and " + visAttr)
				if mappings.hasOwnProperty(dataAttr)
					mappings[dataAttr].push([visAttr, mapping])
				else
					mappings[dataAttr] = [[visAttr, mapping]]
	
	#now that we have all mappings, filter out nominal for which there is also a linear
	visAttrsWithLinear = []
	for dataAttr, visAttrs of mappings
		for visAttrMap in visAttrs
			if visAttrMap[1].hasOwnProperty('isNumericMapping')
				if not (visAttrMap[0] in visAttrsWithLinear)
					visAttrsWithLinear.push(visAttrMap[0])
	
	console.log "linear maps: #{visAttrsWithLinear}"
	
	for dataAttr, visAttrs of mappings
		removed = 0
		for ind in [0..visAttrs.length-1]
			console.log visAttrs
			visAttrMap = visAttrs[ind-removed]
			if !visAttrMap[1].hasOwnProperty('isNumericMapping') and 
			visAttrMap[0] in visAttrsWithLinear
				console.log "removing..."
				console.log visAttrMap
				visAttrs.splice(ind-removed, 1)
				++removed;
	
	return mappings
	
getMapping = (dataAttr, visAttr, dataSet) ->
	dataAttrType = dataSet.dataTypes[dataAttr]
	visAttrType = dataSet.visTypes[visAttr]
	dataAttrCol = dataSet.d3Data[dataAttr]
	visAttrCol = dataSet.visData[visAttr]
	if dataAttrType is "null" or visAttrType is "null"
		# null data, don't even check
		return false
	else if not(dataAttrType is visAttrType) or 
	(dataAttrType is "nominal")
		# nominal
		return getMappingNominal(dataAttrCol, visAttrCol, dataSet['ids'])
	else
		# quantitative/numeric
		return getMappingNumeric(dataAttrCol, visAttrCol, dataSet['ids'])
	return null
			
getMappingNominal = (col1, col2, ids) ->
	mapping = {}
	mapping_ids = {}
	for row1, index in col1
		if mapping.hasOwnProperty(row1)
			mapping[row1].push(col2[index])
			mapping_ids[row1].push(ids[index])
		else
			mapping[row1] = [col2[index]]
			mapping_ids[row1] = [ids[index]]
	for val of mapping
		mapping[val] = _.uniq(mapping[val])
		if mapping[val].length > 1
			return false
	mappedVals = _.flatten(_.values(mapping))
	if _.uniq(mappedVals).length < mappedVals.length
		return false
	for attr of mapping
		mapping[attr] = [mapping[attr], mapping_ids[attr]]
	return mapping
	
hasMappingNominal = (col1, col2) ->
	return if getMappingNominal(col1, col2) then true else false
	
getMappingNumeric = (col1, col2, ids) ->
	mapping = {}
	col1 = _.map(col1, (v) -> parseFloat(v))
	col2 = _.map(col2, (v) -> parseFloat(v))
	zipped = _.zip(col1, col2)
	linear_regression_line = ss.linear_regression().data(zipped).line()
	rSquared = ss.r_squared(zipped, linear_regression_line)
	#console.log rSquared
	if jStat.stdev(col1) is 0 or jStat.stdev(col2) is 0
		return false
	if rSquared > 0.95 and not(isNaN(rSquared))
		#console.log "NUMERIC!"
		mapping.dataMin = _.min(col1)
		mapping.dataMinIndex = col1.indexOf(mapping.dataMin)
		mapping.dataMax = _.max(col1)
		mapping.dataMaxIndex = col1.indexOf(mapping.dataMax)
		mapping.visMin = _.min(col2)
		mapping.visMinIndex = col2.indexOf(mapping.visMin)
		mapping.visMax = _.max(col2)
		mapping.visMaxIndex = col2.indexOf(mapping.visMax)
		mapping.isNumericMapping = true
		mapping.ids = ids
		return mapping
	#else if not _.some(col2, (val) -> if val % 1 is 0 then true else false)
	return getMappingNominal(col1, col2, ids)

getSelectedSet = (dataSet) ->
	newDataSet = $.extend(true, {}, dataSet)
	for key of newDataSet.d3Data
		newList = []
		for sel in newDataSet.selections
			newList.push(newDataSet.d3Data[key][sel])
		newDataSet.d3Data[key] = newList
	for key of newDataSet.visData
		newList = []
		for sel in newDataSet.selections
			newList.push(newDataSet.visData[key][sel])
		newDataSet.visData[key] = newList
	for id in newDataSet['ids']
		newList = []
		for sel in newDataSet.selections
			newList.push(newDataSet['ids'][sel])
		newDataSet['ids'][key] = newList
	return newDataSet

restylingApp = angular.module('restylingApp', [])

restylingApp.controller 'MappingListCtrl', ($scope, orderByFilter) ->
	$scope._ = _
	$scope.currentDataSet = 0
	$scope.chosenMappings = null
	$scope.addMappingDialog = false
	$scope.addForm = { }
	
	$scope.removeMapping = (dataField, mappedAttr) ->
		dataSet = $scope.dataSets[$scope.currentDataSet]
		for mapping in dataSet.mappings[dataField]
			if mapping[0] == mappedAttr[0]
				ind = dataSet.mappings[dataField].indexOf(mapping)
				dataSet.mappings[dataField].splice(ind, 1)
				break
		
		for ind in [0..dataSet.visData[mappedAttr[0]]-1]
			dataSet.visData[mappedAttr[0]][ind] = dataSet.visData[mappedAttr[0]][0]
		
		message = 
			type: "update"
			attr: mappedAttr[0]
			val: dataSet.visData[mappedAttr[0]][0]
			nodes: dataSet['ids']
		console.log message
		window.connector.sendUpdate(message)
	
	$scope.getSelections = ->
		sels = $scope.dataSets[$scope.currentDataSet].selections
		if (not sels) or sels.length == 0
			return $scope.dataSets[$scope.currentDataSet]['ids']
		else
			return sels
	
	$scope.submitValChange = ->
		message = 
			type: "update"
			attr: $scope.addForm.changeAttr
			val: $scope.addForm.changedAttrValue
			nodes: $scope.getSelections()
		window.connector.sendUpdate(message)
		$scope.updateData(message)
		
	$scope.updateData = (updateMessage) ->
		attr = updateMessage.attr
		val = updateMessage.val
		ids = updateMessage.nodes
		for id in ids
			dataSet = $scope.dataSets[$scope.currentDataSet]
			ind = dataSet['ids'].indexOf(id)
			if attr in ["x-position", "y-position", "width", "height"]
				val = parseFloat(val)
			dataSet.visData[attr][ind] = val
			#console.log "setting #{attr} to #{val}"
	
	$scope.setChosenMappings = ->
		$scope.addMappingDialog = false
		$scope.chosenMappings = $scope.dataSets[$scope.currentDataSet].mappings
		#console.log $scope.dataSets
		#console.log $scope.chosenMappings
	
	$scope.getIndexForDataVal = (attr, val) ->
		dataSet = $scope.dataSets[$scope.currentDataSet]
		return dataSet.d3Data[attr].indexOf(val)
		
	$scope.submitAttrClassChange = ($event, attrClass, attrName) ->
		if $event.keyCode is 13 #enter key
			dataSet = $scope.dataSets[$scope.currentDataSet]
			newVal = angular.element($event.target).val()
			inds = []
			for val, i in dataSet.visData[attrName]
				if val == attrClass
					inds.push(i)
			
			ids = _.map(inds, (ind) -> dataSet['ids'][ind])
			message =
				type: "update"
				attr: attrName
				val: newVal
				nodes: ids
			window.connector.sendUpdate(message)
		
	$scope.submitNewLinearMapping = ($event) ->
		if $event.keyCode is 13
			data = $scope.dataSets[$scope.currentDataSet]
			dataMin = _.min(data.d3Data[$scope.addForm.mapDataAttr])
			dataMax = _.max(data.d3Data[$scope.addForm.mapDataAttr])
			newMin = null
			newMax = null
			if $scope.addForm.mapVisAttr is "color" or $scope.addForm.MapVisAttr is "stroke"
				line = d3.scale.linear().domain([dataMin,dataMax]).range([$scope.addForm.newMin, $scope.addForm.newMax])
			else
				newMin = [dataMin, parseFloat($scope.addForm.newMin)]
				newMax = [dataMax, parseFloat($scope.addForm.newMax)]
				regression = ss.linear_regression().data([newMin, newMax])
				line = regression.line()
			for id in $scope.getSelections()
				ind = data['ids'].indexOf(id)
				dataVal = data.d3Data[$scope.addForm.mapDataAttr][ind]
				newAttrVal = line(dataVal)
				message = 
					type: "update"
					attr: $scope.addForm.mapVisAttr
					val: newAttrVal
					nodes: [id]
				#console.log message
				window.connector.sendUpdate(message)
	
	$scope.submitLinearMappingChange = ($event, dataAttr, mapping) ->
		if $event.keyCode is 13
			newMin = [mapping[1].dataMin, parseFloat(mapping[1].visMin)]
			newMax = [mapping[1].dataMax, parseFloat(mapping[1].visMax)]
			regression = ss.linear_regression().data([newMin, newMax])
			line = regression.line()
			currDataSet = $scope.dataSets[$scope.currentDataSet]
			for id in mapping[1].ids
				ind = currDataSet['ids'].indexOf(id)
				dataVal = currDataSet.d3Data[dataAttr][ind]
				newAttrVal = line(dataVal)
				message = 
					type: "update"
					attr: mapping[0]
					val: newAttrVal
					nodes: [id]
				#console.log message
				window.connector.sendUpdate(message)
	
	$scope.isMapped = (visAttr) ->
		dataSet = $scope.dataSets[$scope.currentDataSet]
		console.log dataSet.mappings
		for dataField of dataSet.mappings
			for mapping in dataSet.mappings[dataField]
				if mapping[0] == visAttr
					console.log "#{mapping} -- #{visAttr}"
					return true
		return false
			
	$scope.submitNominalMappingChange = ($event, dataAttr, mappedAttr, mapped_to) ->
		if $event.keyCode is 13 #enter key
			newCategoryVal = angular.element($event.target).val()
			newIds = mapped_to[1]
			mapped_to[0][0] = newCategoryVal
			message =
				type: "update"
				attr: mappedAttr
				val: newCategoryVal
				nodes: newIds
			window.connector.sendUpdate(message)
			
	$scope.selectDataSet = (dataSet) ->
		$scope.currentDataSet = $scope.dataSets.indexOf(dataSet)
		$scope.setChosenMappings()
		$scope.currentDialog = "viewMappingDialog"
	
	$scope.getMappings = ->
		#$scope.currentMappings = []
		#console.log $scope.dataSets[$scope.currentDataSet].selections
		#console.log $scope.dataSets[$scope.currentDataSet]
		#if (not $scope.dataSets[$scope.currentDataSet].selections) or 
		#		$scope.dataSets[$scope.currentDataSet].selections.length == 0
		$scope.dataSets[$scope.currentDataSet].mappings = 
			getMappings($scope.dataSets[$scope.currentDataSet])
		###
		else
			selectedSet = getSelectedSet($scope.dataSets[$scope.currentDataSet])
			console.log selectedSet
			$scope.selectedSet = selectedSet
			$scope.dataSets[$scope.currentDataSet].mappings = 
				getMappings(selectedSet)
		###
	
	$scope.toggleSelect = (dataSet, elemIndex) ->
		if not dataSet.selections
			dataSet.selections = [elemIndex]
		else
			if elemIndex in dataSet.selections
				dataSet.selections = _.without(dataSet.selections, elemIndex)
			else
				dataSet.selections.push(elemIndex)
		console.log dataSet.selections
		#$scope.getMappings()
		
	$scope.itemClass = (dataSet, elemIndex) ->
		if not dataSet.hasOwnProperty('selections')
			return undefined
			
		if elemIndex in dataSet.selections
			return 'selected'
		return undefined

prepareMarkForDisplay = (nodeText, cssText) ->
	htmlNode = $(nodeText)[0]
	svgNode = document.createElementNS("http://www.w3.org/2000/svg", htmlNode.tagName.toLowerCase());
	htmlNode.style.cssText = cssText
	tagName = $(htmlNode).prop("tagName").toLowerCase()  #lower case b/c jquery inconsistency
		
	for attr in htmlNode.attributes
		svgNode.setAttribute(attr.name, attr.value)
	
	d3.select(svgNode).attr("transform", undefined)
	# circle case
	if tagName == "circle" or tagName == "ellipse"
		r = d3.select(svgNode).attr "r"
		d3.select(svgNode).attr "cx", 0
		d3.select(svgNode).attr "cy", 0
	else
		d3.select(svgNode).attr "x", 0
		d3.select(svgNode).attr "y", 0
	return svgNode
		

restylingApp.directive 'svgInject', ($compile) ->
	return {
		scope: {
			ind: '=ind',
			data: '=data'
		}
		link: (scope, element, attrs, controller) ->
			scope.$watch "data['node'][ind]", ((newValue, oldValue) -> 
				svg = document.createElementNS("http://www.w3.org/2000/svg", "svg")
				canvasWidth = 20
				svg.setAttribute("width", "20")
				svg.setAttribute("height", "20")
				$.each element[0].children, (e, i) ->
					$(this).remove()
				element[0].appendChild(svg)
				
				markInfo = scope.data['node'][scope.ind]

				maxWidth = _.max(scope.data.visData['width'])
				maxHeight = _.max(scope.data.visData['height'])
				mark = prepareMarkForDisplay(markInfo['tag'], markInfo['css'])
				#mark = prepareMarkFromVisData(scope.dataSet['node'].visData, scope.i)
				svg.appendChild(mark)
				scaleDimVal = maxHeight
				#maxNode = maxHeightNode
				if maxWidth > maxHeight
					#maxNode = maxWidthNode
					scaleDimVal = maxWidth
				
				#console.log transformedBoundingBox(mark)
				#console.log scaleDimVal
				newTranslate = svg.createSVGTransform()
				newTranslate.setTranslate(canvasWidth / 2, canvasWidth / 2)
				newScale = svg.createSVGTransform()
				newScale.setScale((canvasWidth-5) / scaleDimVal, (canvasWidth-5) / scaleDimVal)
				mark.transform.baseVal.appendItem(newTranslate)
				scaleNode(mark, scope.data.visData['width'][scope.ind], scope.data.visData['height'][scope.ind], svg)
				mark.transform.baseVal.appendItem(newScale)
				#d3.select(mark).attr("transform", newTranslate + newScale)
				#console.log transformedBoundingBox(mark)
				), true
		}
# Calculate the bounding box of an element with respect to its parent element
transformedBoundingBox = (el, to) ->
	bb = el.getBBox()
	svg = el.ownerSVGElement
	unless to
		to = svg
	m = el.getTransformToElement(to)
	
	# Create an array of all four points for the original bounding box
	pts = [
    svg.createSVGPoint(), svg.createSVGPoint(),
    svg.createSVGPoint(), svg.createSVGPoint()
	]
	
	pts[0].x=bb.x
	pts[0].y=bb.y
	pts[1].x=bb.x+bb.width
	pts[1].y=bb.y
	pts[2].x=bb.x+bb.width
	pts[2].y=bb.y+bb.height
	pts[3].x=bb.x
	pts[3].y=bb.y+bb.height;

  # Transform each into the space of the parent,
  # and calculate the min/max points from that.    
	xMin=Infinity
	xMax=-Infinity
	yMin=Infinity
	yMax=-Infinity
	for pt in pts
		pt = pt.matrixTransform(m)
		xMin = Math.min(xMin,pt.x)
		xMax = Math.max(xMax,pt.x)
		yMin = Math.min(yMin,pt.y)
		yMax = Math.max(yMax,pt.y)

  # Update the bounding box with the new values
	bb.x = xMin
	bb.width  = xMax-xMin
	bb.y = yMin
	bb.height = yMax-yMin
	return bb

window.transformedBoundingBox = transformedBoundingBox

scaleNode = (node, width, height, svg) ->
	scale = svg.createSVGTransform()
	bbox = window.transformedBoundingBox(node)
	
	#console.log "scaling: #{width}, #{height}"
	#console.log bbox
	if bbox.width == 0
		scale.setScale(1, height / bbox.height)
	else if bbox.height == 0
		scale.setScale(width / bbox.width, 1)
	else
		#console.log "width: #{width}, height: #{height}"
		scale.setScale((width / bbox.width), (height / bbox.height))
	node.transform.baseVal.appendItem(scale)
	bbox = window.transformedBoundingBox(node)

updateNode = (origNode, origBBox, attr, val) ->
	parentNode = origNode.parentElement
	svg = getRootSVG(origNode)
	clone = null
	currentTag = origNode.tagName.toLowerCase()
	
	if attr is "shape"
		clone = getNodeFromShape(val)
	else if currentTag is "polygon"
		clone = getNodeFromShape(currentTag, origNode.getAttribute("points"))
	else
		clone = getNodeFromShape(currentTag)
		
	parentNode.appendChild(clone)
	bbox = transformedBoundingBox(clone, svg)
	#console.log bbox
	#console.log clone
	
	for currAttr in origNode.attributes
		if not (currAttr.name in ["id", "cx", "cy", "x", "y", "r", "transform", "points", "clip-path", "requiredFeatures", "systemLanguage", "requiredExtensions", "vector-effect"])
			clone.setAttribute(currAttr.name, currAttr.value)
	clone.setAttribute("vector-effect", "non-scaling-stroke")

	if attr is "color"
		attr = "fill"
		d3.select(clone).style("fill", val)			
	else if not (attr in ["x-position", "y-position", "shape", "width", "height"])
		d3.select(clone).attr(attr, val)
	
	translate = svg.createSVGTransform()
	parentTrans = origNode.getTransformToElement(svg)
	trans = clone.getTransformToElement(svg)
	parentOffset = [0, 0]
	if currentTag is "circle"
		cx = parseFloat(d3.select(origNode).attr("cx"))
		cy = parseFloat(d3.select(origNode).attr("cy"))
		if cx then parentOffset[0] = cx
		if cy then parentOffset[1] = cy
	else if currentTag is "rect"
		x = parseFloat(d3.select(origNode).attr("x"))
		y = parseFloat(d3.select(origNode).attr("y"))
		if x then parentOffset[0] = x
		if y then parentOffset[1] = y
	translate.setTranslate(parentTrans.e-trans.e+parentOffset[0], parentTrans.f-trans.f+parentOffset[1])
	clone.transform.baseVal.appendItem(translate)
		
	if attr is "x-position"
		newX = parseFloat(val)
		xtranslate = svg.createSVGTransform()
		xtranslate.setTranslate(newX-origBBox.x, 0)
		clone.transform.baseVal.appendItem(xtranslate)
	else if attr is "y-position"
		newY = parseFloat(val)
		ytranslate = svg.createSVGTransform()
		ytranslate.setTranslate(0, newY-origBBox.y)
		clone.transform.baseVal.appendItem(ytranslate)
		
	scale = svg.createSVGTransform()
	if val is "circle"
		if origBBox.width < origBBox.height
			scale.setScale(origBBox.width / bbox.width,origBBox.width / bbox.width)
		else
			scale.setScale(origBBox.height / bbox.height,origBBox.height / bbox.height)
	else if attr is "width"
		newWidth = parseFloat(val)
		scale.setScale((newWidth / bbox.width), (origBBox.height / bbox.height))
	else if attr is "height"
		newHeight = parseFloat(val)
		scale.setScale((origBBox.width / bbox.width), (newHeight / bbox.height))			
	else 
		scale.setScale((origBBox.width / bbox.width), (origBBox.height / bbox.height))
	clone.transform.baseVal.appendItem(scale)
	
	#console.log clone
	

###		
prepareMarkFromVisData = (visData, i) ->
	newNode = document.createElementNS("http://www.w3.org/2000/svg", visData["shape"][i])
	d3.select(newNode).style("fill", visData["color"][i])
	d3.select(newNode).style("stroke", visData["stroke"][i])
	d3.select(newNode).attr("stroke-width", visData["stroke-width"][i])
	
	newTranslate = "translate(" + canvasWidth / 2 + "," + canvasWidth / 2 + ")"
	
	return {"shape": [], "color": [], "stroke": [], \ 
						"stroke-width": [], "width": [], "height": [], "area": [], "x-position": [], "y-position": []}
###
		
$(document).ready () ->
	connector = new VisConnector()
	remappingForm = null
	window.connector = connector
	
setupModal = () ->
	$('table').on 'contextmenu', (event) ->
		event.preventDefault()
		scope = angular.element(event.target).scope()
		console.log scope.dataSet
		scope.$apply () ->
			#scope.currentDataSet = scope.dataSets.indexOf(dataSet)
			scope.selectDataSet(scope.dataSet)
		
		$("#attrEditor").modal()