/* ------------------------------------------------------------

   Copyright 2016 Esri

   Licensed under the Apache License, Version 2.0 (the 'License');
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at:
   http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an 'AS IS' BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.

--------------------------------------------------------------- */

require([
    'esri/Map',
    'esri/Graphic',
    'esri/geometry/Extent',
    'esri/geometry/SpatialReference',
    'esri/geometry/Point',
    'esri/geometry/ScreenPoint',
    'esri/views/MapView',
    'esri/layers/GraphicsLayer',
    'esri/symbols/SimpleFillSymbol',
    'esri/renderers/SimpleRenderer',
    'esri/widgets/Home',
    'esri/widgets/Search',
    'esri/portal/Portal',
    'esri/identity/OAuthInfo',
    'esri/identity/IdentityManager',
    'dojo/number',
    'dojo/domReady!'
],
function (
    Map,
    Graphic,
    Extent,
    SpatialReference,
    Point,
    ScreenPoint,
    MapView,
    GraphicsLayer,
    SimpleFillSymbol,
    SimpleRenderer,
    Home,
    Search,
    Portal,
    OAuthInfo,
    IdentityManager,
    number
    ) {
    $(document).ready(function () {
        // Enforce strict mode
        'use strict';

        // Constants
        var STATUSBAR_DURATION = 300; // Time for a statusbar to slide in/out.
        var LAYER_AOI = 'aoi';        // Graphic identifier for AOI.
        var LAYER_TILES = 'tiles';    // Graphic identifier for AOI.
        var TILE_SIZE_MIN = 1;        // Minimum tile size
        var TILE_SIZE_MAX = 10;       // Maximum tile size

        // Variables
        var _digitizing = false;      // Digitizing AOI.
        var _start = null;            // AOI originating map point.
        var _credentials = null;      // AGOL credentials.

        // Map view
        var _view = new MapView({
            container: 'map',
            extent: {
                xmin: -111.742,
                ymin: 36.161,
                xmax: -111.675,
                ymax: 36.199
            },
            ui: {
                components: [
                    'zoom',
                    'compass'
                ]
            },
            map: new Map({
                basemap: 'satellite',
                layers: [
                    new GraphicsLayer({
                        id: LAYER_TILES,
                        renderer: new SimpleRenderer({
                            symbol: new SimpleFillSymbol({
                                color: [0, 100, 100, 0.2],
                                style: 'solid',
                                outline: {
                                    color: [0, 0, 255, 0.5],
                                    width: 2,
                                    style: 'solid'
                                }
                            })
                        })
                    }),
                    new GraphicsLayer({
                        id: LAYER_AOI,
                        renderer: new SimpleRenderer({
                            symbol: new SimpleFillSymbol({
                                color: [255, 255, 255, 1],
                                style: 'none',
                                outline: {
                                    color: [255, 0, 0, 0.8],
                                    width: 3,
                                    style: 'long-dash'
                                }
                            })
                        })
                    })
                ]
            })
        });

        function connected() {
            $('#sign-in').popover('hide');
            $('#sign-in').hide();
            $('#profile').show();
            $('#left').delay(100).animate({
                'margin-left': '0'
            }, {
                duration: 400,
                easing: 'swing',
                queue: false,
                complete: function () {
                    $('#right').css({
                        'left': $('#left').width() + 'px'
                    });
                }
            });
        }
        function disconnected() {
            $('#left').css({
                'margin-left': -1 * $('#left').width() + 'px'
            });
            $('#right').css({
                'left': '0'
            });
            _credentials = null;
            $('#profile').hide();
            $('#sign-in').show();
            $('#sign-in').popover('show');
        }

        // Define Login Popover.
        $('#sign-in').popover({
            container: 'body',
            content: 'Please sign in with an ArcGIS Online organization or an ArcGIS Developer account.<br><i>If you don&apos;t have an account, you can sign up for a <a href="http://goto.arcgisonline.com/features/trial" target="_blank">free trial of ArcGIS</a> or a <a href="http://goto.arcgisonline.com/developers/signup" target="_blank">free ArcGIS Developer account</a>.</i>',
            html: true,
            placement: 'bottom',
            title: 'Sign into ArcGIS Online',
            trigger: 'manual'
        });

        // Add Search and Home widgets.
        _view.ui.add(new Search({
            view: _view
        }), {
            position: 'top-left',
            index: 0
        });
        _view.ui.add(new Home({
            view: _view
        }), {
            position: 'top-left',
            index: 2
        });

        // ArcGIS Online Registration and Login
        var info = new OAuthInfo({
            appId: 'RQTgTrvovjEersMw',
            popup: false
        });
        IdentityManager.registerOAuthInfos([info]);
        IdentityManager.checkSignInStatus(info.portalUrl + '/sharing').then(function (resolved) {
            var portal = new Portal({
                authMode: 'immediate'
            });
            portal.load().then(function () {
                // Check for non-organizational account
                if (!portal.isOrganization) {
                    IdentityManager.destroyCredentials();
                    $('#modalAccount').modal('show');
                    return;
                }
                // Store credentials
                _credentials = resolved;
                // Update UI
                $('#profile-name').html(portal.user.fullName);
                $('#profile-image').prop('src', portal.user.thumbnailUrl);
                $('#my-profile > a').prop('href', $.format(
                    'https://{0}.{1}/home/user.html', [
                        portal.urlKey,
                        portal.customBaseUrl
                    ])
                );
                $('#my-content > a').prop('href', $.format(
                    'https://{0}.{1}/home/content.html', [
                        portal.urlKey,
                        portal.customBaseUrl
                    ])
                );
                connected();
            });
        }).otherwise(function (error) {          
            disconnected();
        });

        // Show about dialog on startup
        //$('#modalAbout').modal('show');

        // User clicks the Sign In button
        $('#sign-in').click(function () {
            IdentityManager.getCredential(info.portalUrl + '/sharing');
        });

        // User clicks the Sign Out button
        $('#sign-out').click(function () {
            IdentityManager.destroyCredentials();
            disconnected();
        });

        // Elevation/Texture UI.
        $('#elevation-format button').click(function () {
            if ($(this).hasClass('active')) { return; }
            $(this).addClass('active').siblings().removeClass('active');
        });
        $('#texture-format button').click(function () {
            if ($(this).hasClass('active')) { return; }
            $(this).addClass('active').siblings().removeClass('active');
        });
        $('#elevation-resolution button, #texture-resolution button').click(function () {
            $(this).toggleClass('active');
        });
        $('.rc-spinner .btn').click(function () {
            var inc = $(this).attr('data-increment');
            var inp = $(this).parent().siblings('input');
            var val = $(inp).val();
            if (!$.isNumeric(val)) {
                $(inp).val(
                    $(inp).attr('data-value')
                );
                return;
            }
            var par = parseInt(val, 10);
            par += Number(inc);
            if (par < TILE_SIZE_MIN || par > TILE_SIZE_MAX) { return; }
            $(inp).attr('data-value', par).val(par);
            
            // Update tiles
            addTerrainTiles();
        });
        
        // Draw Area of Interest Rectangle.
        $('#box').click(function () {
            // Hide popover box (if any).
            $('#box').popover('hide');
            
            // Start digitizing.
            _view.popupManager.enabled = false;
            _view.gestureManager.inputManager.manager.options.enable = false;
            _digitizing = true;
            
            // Clear the tile size.
            $('#tile-size').html('0m');
        });

        // Remove AOI and Tiles.
        $('#clear').click(function () {
            // Remove AOI.
            var aoi = _view.map.findLayerById(LAYER_AOI);
            aoi.graphics.removeAll();

            // Remove all current terrain tiles.
            var tiles = _view.map.findLayerById(LAYER_TILES);
            tiles.graphics.removeAll();

            // Disable the EXPORT button.
            $('#export').addClass('disabled');
            
            // Clear the tile size.
            $('#tile-size').html('0m');
        });

        // Digitize area of interest
        $('#map').mousedown(function (e) {
            if (!_digitizing) { return; }
            
            // Remove previous tiles (if any).
            var tiles = _view.map.findLayerById(LAYER_TILES);
            tiles.graphics.removeAll();
            
            // Start location.
            _start = _view.toMap(new ScreenPoint({
                x: e.offsetX,
                y: e.offsetY
            }));
        });
        $('#map').mousemove(function (e) {
            if (!_digitizing) { return; }
            if (_start === null) { return; }

            // End location.
            var end = _view.toMap(new ScreenPoint({
                x: e.offsetX,
                y: e.offsetY
            }));

            // Remove previous AOI graphic (if any).
            var layer = _view.map.findLayerById(LAYER_AOI);
            layer.graphics.removeAll();

            // Add new AOI graphic.
            layer.add(
                new Graphic({
                    geometry: new Extent({
                        xmin: Math.min(_start.x, end.x),
                        ymin: Math.min(_start.y, end.y),
                        xmax: Math.max(_start.x, end.x),
                        ymax: Math.max(_start.y, end.y),
                        spatialReference: SpatialReference.WebMercator
                    })

                })
            );
            
            // Add terrain tiles
            addTerrainTiles();
        });
        $('#map').mouseup(function () {
            if (!_digitizing) { return; }
            if (_start === null) { return; }
            
            // Stop digitizing.
            _digitizing = false;
            _view.popupManager.enabled = true;
            _view.gestureManager.inputManager.manager.options.enable = true;
            _start = null;
        });

        // Update dropdown button text.
        $('#elevation-source .dropdown-menu li a, #texture-source .dropdown-menu li a').click(function () {
            // Exit if item already selected.
            if ($(this).parent().hasClass('active')) { return; }

            // Toggle enabled state for clicked item and siblings.
            $(this).parent().addClass('active').siblings().removeClass('active');

            // Update text in dropdown.
            $(this).closest('.btn-group').children().first().html(
                $(this).html()
            );
        });

        // Initiate a dowload of the current tiles as elevation and image files.
        $('#download').click(function () {
            // Check tiles created.
            var tiles = _view.map.findLayerById(LAYER_TILES);
            if (tiles.graphics.length === 0) {
                $('#box').popover({
                    container: '#left',
                    content: 'Click and drag the mouse on the map to indicate the area of interest.',
                    html: true,
                    placement: 'bottom',
                    title:'Draw Area of Interest',
                    trigger: 'manual'
                }).popover('show');
                return;
            }
            
            // Check AGOL connection.
            if (_credentials === null) {
                $('#modalAccount').modal('show');
                return;
            }

            // Create JSON object describing elevation and image tiles.
            var elevation = tiles.graphics.toArray().map(function (e, i) {
                return {
                    id: i,
                    source: $('#elevation-source li.active').attr('data-value'),
                    token: _credentials.token,
                    format: $('#elevation-format button.active').attr('data-value'),
                    resolution: $('#elevation-resolution button.active').map(function () {
                        return Number($(this).attr('data-value'));
                    }).toArray(),
                    extent: {
                        xmin: e.geometry.extent.xmin,
                        ymin: e.geometry.extent.ymin,
                        xmax: e.geometry.extent.xmax,
                        ymax: e.geometry.extent.ymax
                    }
                };
            });
            var texture = tiles.graphics.toArray().map(function (e, i) {
                return {
                    id: i,
                    source: $('#texture-source li.active').attr('data-value'),
                    token: _credentials.token,
                    format: $('#texture-format button.active').attr('data-value'),
                    resolution: $('#texture-resolution button.active').map(function () {
                        return Number($(this).attr('data-value'));
                    }).toArray(),
                    extent: {
                        xmin: e.geometry.extent.xmin,
                        ymin: e.geometry.extent.ymin,
                        xmax: e.geometry.extent.xmax,
                        ymax: e.geometry.extent.ymax
                    }
                };
            });
            var data = {
                elevation: elevation,
                texture: texture
            };

            // Show processing dialog.
            $('#modalProcessing').modal('show');

            $.post('export.ashx', JSON.stringify(data))
            .done(function (e) {
                $('#modalProcessing').modal('hide');
                $('body').append(
                    $(document.createElement('iframe')).attr({
                        src: e.url
                    }).css({
                        display: 'none'
                    })
                );
            })
            .fail(function (e) {
                $('#modalProcessing').modal('hide');
                $('#modalError').modal('show');
                $('#modalError .modal-body p').html(
                    e.responseText
                );
            });
        });

        // Add terrain tiles.
        function addTerrainTiles(){
            // Get AOI
            var aoi = _view.map.findLayerById(LAYER_AOI);
            if (aoi.graphics.length === 0) { return; }
            var extent = aoi.graphics.getItemAt(0).geometry;

            // Remove all current terrain tiles
            var tiles = _view.map.findLayerById(LAYER_TILES);
            tiles.graphics.removeAll();
            
            // Calculate terrain tile size
            var tilesx = $('#inputWidth').val();
            var tilesy = $('#inputHeight').val();
            var side = null;
            if (extent.width / extent.height > tilesx / tilesy) {
                side = extent.width / tilesx;
            }
            else {
                side = extent.height / tilesy;
            }

            // Add terrain tiles
            for (var y = 0; y < tilesy; y++) {
                for (var x = 0; x < tilesx; x++) {
                    tiles.add(
                        new Graphic({
                            geometry: new Extent({
                                xmin: extent.xmin + side * x,
                                ymin: extent.ymax - side * (y + 1),
                                xmax: extent.xmin + side * (x + 1),
                                ymax: extent.ymax - side * y,
                                spatialReference: SpatialReference.WebMercator
                            })
                        })
                    );
                }
            }
            
            //
            $('#tile-size').html(number.format(side, {
                places: 0
            }) + 'm');
        }

        // jQuery formatting function.
        $.format = function (f, e) {
            $.each(e, function (i) {
                f = f.replace(new RegExp('\\{' + i + '\\}', 'gm'), this);
            });
            return f;
        };
    });
});
