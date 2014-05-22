"use strict";

(function () {
    var restylingApp = angular.module('restylingApp', []);

    restylingApp.factory('chromeMessageService', function() {
        return function (callback) {
            chrome.runtime.onMessage.addListener(function (message) {
                if (message.type === "restylingData") {
                    var data = message.data;
                    data = $.extend([], data);
                    callback(data);
                }
            });
        };
    });

    restylingApp.controller('RestylingAppController', ['$scope', 'chromeMessageService',
        function($scope, chromeMessageService) {
            $scope.selectedSchema = 0;
            $scope.data = [];

            // Load data from the visualization as it arrives
            chromeMessageService(function (data) {
                _.each(data, function(schema, i) {
                    data[i].numNodes = schema.ids.length;
                });
                $scope.data = data;
                $scope.$apply();
            });

            $scope.selectSchema = function(schema) {
                console.log($scope.data);
                $scope.selectedSchema = $scope.data.indexOf(schema);
                console.log($scope.selectedSchema);
            };

        }]);

    restylingApp.controller('DataTableController', ['$scope', 'orderByFilter', function($scope, orderByFilter) {

    }]);

    restylingApp.controller('MappingsListController', ['$scope', function($scope) {

    }]);

    restylingApp.controller('AddMappingsController', ['$scope', function($scope) {
        $scope.dataFieldSelected = "";
        $scope.attrSelected = "";
    }]);

    restylingApp.directive('svgInject', function($compile) {
        return {
            scope: {
                schema: "=schema",
                ind: "=ind"
            },
            restrict: 'E',
            link: function(scope, element, attrs, controller) {
                scope.$watch("", function(newValue, oldValue) {

                    var svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
                    var canvasWidth = 20;
                    svg.setAttribute("width", canvasWidth.toString());
                    svg.setAttribute("height", canvasWidth.toString());
                    _.each(element[0].children, function() {
                        $(this).remove();
                    }, true);

                    var maxWidth = _.max(scope.schema.attrs["width"]);
                    var maxHeight= _.max(scope.schema.attrs["height"]);
                    var scaleDimVal = maxHeight;
                    if (maxWidth > maxHeight) {
                        scaleDimVal = maxWidth;
                    }

                    var markNode = document.createElementNS("http://www.w3.org/2000/svg", scope.schema.attrs["shape"][scope.ind]);

                    var nodeAttrs = scope.schema.nodeAttrs[scope.ind];
                    for (var nodeAttr in nodeAttrs) {
                        if (nodeAttrs.hasOwnProperty(nodeAttr) && nodeAttrs[nodeAttr] !== null) {
                            if (nodeAttr === "text") {
                                $(markNode).text(nodeAttrs[nodeAttr]);
                            }
                            else {
                                d3.select(markNode).attr(nodeAttr, nodeAttrs[nodeAttr]);
                            }
                        }
                    }

                    // Setup non-geometric attributes
                    var geomAttrs = ["width", "height", "area", "shape", "xPosition", "yPosition"];
                    for (var attr in scope.schema.attrs) {
                        var isGeom = false;
                        _.each(geomAttrs, function(geomAttr) {
                            if (attr === geomAttr) {
                                isGeom = true;
                                return -1;
                            }
                        });
                        if (!isGeom && scope.schema.attrs[attr][scope.ind] !== 'none') {
                            d3.select(markNode).style(attr, scope.schema.attrs[attr][scope.ind]);
                        }
                    }

                    markNode.setAttribute("vector-effect", "non-scaling-stroke");
                    if (markNode.tagName == "circle") {
                        markNode.setAttribute("r", "1");
                    }

                    svg.appendChild(markNode);
                    element[0].appendChild(svg);

                    var newTranslate = svg.createSVGTransform();
                    newTranslate.setTranslate(canvasWidth / 2, canvasWidth / 2);
                    var newScale = svg.createSVGTransform();
                    var originalWidthScale = scope.schema.attrs["width"][scope.ind] /
                        transformedBoundingBox(markNode).width;
                    var originalHeightScale = scope.schema.attrs["height"][scope.ind] /
                        transformedBoundingBox(markNode).height;

                    if (isNaN(originalWidthScale)) {
                        originalWidthScale = 1;
                    }
                    if (isNaN(originalHeightScale)) {
                        originalHeightScale = 1;
                    }

                    newScale.setScale(originalWidthScale * ((canvasWidth-2) / scaleDimVal),
                            originalHeightScale * (canvasWidth-2) / scaleDimVal);
                    markNode.transform.baseVal.appendItem(newTranslate);
                    markNode.transform.baseVal.appendItem(newScale);

                });
            }
        }
    });



    var transformedBoundingBox = function (el, to) {
        var bb = el.getBBox();
        var svg = el.ownerSVGElement;
        if (!to) {
            to = svg;
        }
        var m = el.getTransformToElement(to);
        var pts = [svg.createSVGPoint(), svg.createSVGPoint(), svg.createSVGPoint(), svg.createSVGPoint()];
        pts[0].x = bb.x;
        pts[0].y = bb.y;
        pts[1].x = bb.x + bb.width;
        pts[1].y = bb.y;
        pts[2].x = bb.x + bb.width;
        pts[2].y = bb.y + bb.height;
        pts[3].x = bb.x;
        pts[3].y = bb.y + bb.height;

        var xMin = Infinity;
        var xMax = -Infinity;
        var yMin = Infinity;
        var yMax = -Infinity;

        for (var i = 0; i < pts.length; i++) {
            var pt = pts[i];
            pt = pt.matrixTransform(m);
            xMin = Math.min(xMin, pt.x);
            xMax = Math.max(xMax, pt.x);
            yMin = Math.min(yMin, pt.y);
            yMax = Math.max(yMax, pt.y);
        }
        bb.x = xMin;
        bb.width = xMax - xMin;
        bb.y = yMin;
        bb.height = yMax - yMin;
        return bb;
    };
})();