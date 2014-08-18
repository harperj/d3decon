"use strict";

var VisUpdater = require('./VisUpdater.js');
var VisDeconstruct = require('./VisDeconstruct.js');
var $ = require('jquery');

var updater;

pageDeconstruct();

///** Binds right click to initiate deconstruction on the root SVG node. **/
//$(document).bind("contextmenu", function (event) {
//    var ancestorSVG = $(event.target).closest("svg");
//    if (ancestorSVG.length > 0) {
//        event.preventDefault();
//        pageDeconstruct();
//        return visDeconstruct(ancestorSVG);
//    }
//});

document.addEventListener("updateEvent", function(event) {
    var updateMessage = event.detail;
    updater.updateNodes(updateMessage.ids, updateMessage.attr, updateMessage.val);
});

document.addEventListener("createEvent", function(event) {
    var createMessage = event.detail;
    updater.createNodes(createMessage.ids);
});

/**
 * Accepts a top level SVG node and deconstructs it by extracting data, marks, and the
 * mappings between them.
 * @param svgNode - Top level SVG node of a D3 visualization.
 */
function visDeconstruct(svgNode) {
    var deconstructed = VisDeconstruct.deconstruct(svgNode);

    updater = new VisUpdater(svgNode, deconstructed.dataNodes.nodes, deconstructed.dataNodes.ids,
        deconstructed.schematizedData);

    console.log(deconstructed.schematizedData);

    var deconData = {
        schematized: deconstructed.schematizedData,
        ids: deconstructed.dataNodes.ids
    };

    // Now send a custom event with dataNodes to the content script
    var evt = document.createEvent("CustomEvent");
    evt.initCustomEvent("deconDataEvent", true, true, deconData);
    document.dispatchEvent(evt);
}


function pageDeconstruct() {
    var svgNodes = $('svg');
    var deconstructed = [];
    $.each(svgNodes, function(i, svgNode) {
        var children = $(svgNode).find('*');
        var isD3Node = false;
        $.each(children, function(i, child) {
            if (child.__data__) {
                isD3Node = true;
                return false;
            }
        });

        if (isD3Node) {
            var decon = VisDeconstruct.deconstruct(svgNode);
            decon = {
                schematized: decon.schematizedData,
                ids: decon.dataNodes.ids
            };
            deconstructed.push(decon);
        }
    });
    var evt = document.createEvent("CustomEvent");
    evt.initCustomEvent("deconDataEvent", true, true, deconstructed);
    document.dispatchEvent(evt);
}