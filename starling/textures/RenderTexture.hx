// =================================================================================================
//
//	Starling Framework
//	Copyright Gamua GmbH. All Rights Reserved.
//
//	This program is free software. You can redistribute and/or modify it
//	in accordance with the terms of the accompanying license agreement.
//
// =================================================================================================

package starling.textures;

import openfl.display3D.textures.TextureBase;
import openfl.display3D.Context3DCompareMode;
import openfl.display3D.Context3DTriangleFace;
import openfl.errors.IllegalOperationError;
import openfl.geom.Matrix;
import openfl.geom.Rectangle;
import openfl.geom.Vector3D;

import starling.core.Starling;
import starling.display.BlendMode;
import starling.display.DisplayObject;
import starling.display.Image;
import starling.filters.FragmentFilter;
import starling.rendering.Painter;
import starling.rendering.RenderState;

/** A RenderTexture is a dynamic texture onto which you can draw any display object.
 * 
 *  <p>After creating a render texture, just call the <code>draw</code> method to render 
 *  an object directly onto the texture. The object will be drawn onto the texture at its current
 *  position, adhering its current rotation, scale and alpha properties.</p> 
 *  
 *  <p>Drawing is done very efficiently, as it is happening directly in graphics memory. After 
 *  you have drawn objects onto the texture, the performance will be just like that of a normal 
 *  texture — no matter how many objects you have drawn.</p>
 *  
 *  <p>If you draw lots of objects at once, it is recommended to bundle the drawing calls in 
 *  a block via the <code>drawBundled</code> method, like shown below. That will speed it up 
 *  immensely, allowing you to draw hundreds of objects very quickly.</p>
 *  
 * 	<pre>
 *  renderTexture.drawBundled(function():void
 *  {
 *     for (var i:int=0; i&lt;numDrawings; ++i)
 *     {
 *         image.rotation = (2 &#42; Math.PI / numDrawings) &#42; i;
 *         renderTexture.draw(image);
 *     }   
 *  });
 *  </pre>
 *  
 *  <p>To erase parts of a render texture, you can use any display object like a "rubber" by
 *  setting its blending mode to <code>BlendMode.ERASE</code>. To wipe it completely clean,
 *  use the <code>clear</code> method.</p>
 * 
 *  <strong>Persistence</strong>
 *
 *  <p>Older devices may require double buffering to support persistent render textures. Thus,
 *  you should disable the <code>persistent</code> parameter in the constructor if you only
 *  need to make one draw operation on the texture. The static <code>useDoubleBuffering</code>
 *  property allows you to customize if new textures will be created with or without double
 *  buffering.</p>
 *
 *  <strong>Context Loss</strong>
 *
 *  <p>Unfortunately, render textures are wiped clean when the render context is lost.
 *  This means that you need to manually recreate all their contents in such a case.
 *  One way to do that is by using the <code>root.onRestore</code> callback, like here:</p>
 *
 *  <listing>
 *  renderTexture.root.onRestore = function():void
 *  {
 *      var quad:Quad = new Quad(100, 100, 0xff00ff);
 *      renderTexture.clear(); // required on texture restoration
 *      renderTexture.draw(quad);
 *  });</listing>
 *
 *  <p>For example, a drawing app would need to store information about all draw operations
 *  when they occur, and then recreate them inside <code>onRestore</code> on a context loss
 *  (preferably using <code>drawBundled</code> instead).</p>
 *
 *  <p>However, there is one problem: when that callback is executed, it's very likely that
 *  not all of your textures are already available, since they need to be restored, too (and
 *  that might take a while). You probably loaded your textures with the "AssetManager".
 *  In that case, you can listen to its <code>TEXTURES_RESTORED</code> event instead:</p>
 *
 *  <listing>
 *  assetManager.addEventListener(Event.TEXTURES_RESTORED, function():void
 *  {
 *      var brush:Image = new Image(assetManager.getTexture("brush"));
 *      renderTexture.draw(brush);
 *  });</listing>
 *
 *  <p>[Note that this time, there is no need to call <code>clear</code>, because that's the
 *  default behavior of <code>onRestore</code>, anyway — and we didn't modify that.]</p>
 *
 */
class RenderTexture extends SubTexture
{
    private static inline var USE_DOUBLE_BUFFERING_DATA_NAME:String =
        "starling.textures.RenderTexture.useDoubleBuffering";

    private var _activeTexture:Texture;
    private var _bufferTexture:Texture;
    private var _helperImage:Image;
    private var _drawing:Bool;
    private var _bufferReady:Bool;
    private var _isPersistent:Bool;

    // helper object
    private static var sClipRect:Rectangle = new Rectangle();
    
    #if commonjs
    private static function __init__ () {
        
        untyped Object.defineProperties (RenderTexture.prototype, {
            "isPersistent": { get: untyped __js__ ("function () { return this.get_isPersistent (); }") },
        });
        
        untyped Object.defineProperties (RenderTexture, {
            "useDoubleBuffering": { get: untyped __js__ ("function () { return RenderTexture.get_useDoubleBuffering (); }"), set: untyped __js__ ("function (v) { return RenderTexture.set_useDoubleBuffering (v); }") },
        });
        
    }
    #end
    
    /** Creates a new RenderTexture with a certain size (in points). If the texture is
     *  persistent, its contents remains intact after each draw call, allowing you to use the
     *  texture just like a canvas. If it is not, it will be cleared before each draw call.
     *
     *  <p>Non-persistent textures can be used more efficiently on older devices; on modern
     *  hardware, it does not make a difference. For more information, have a look at the
     *  documentation of the <code>useDoubleBuffering</code> property.</p>
     */
    public function new(width:Int, height:Int, persistent:Bool=true,
                        scale:Float=-1, format:String="bgra")
    {
        _isPersistent = persistent;
        _activeTexture = Texture.empty(width, height, true, false, true, scale, format);
        _activeTexture.root.onRestore = function(textureRoot:ConcreteTexture):Void {textureRoot.clear();};

        super(_activeTexture, new Rectangle(0, 0, width, height), true, null, false);

        if (persistent && useDoubleBuffering)
        {
            _bufferTexture = Texture.empty(width, height, true, false, true, scale, format);
            _bufferTexture.root.onRestore = function(textureRoot:ConcreteTexture):Void {textureRoot.clear();};
            _helperImage = new Image(_bufferTexture);
            _helperImage.textureSmoothing = TextureSmoothing.NONE; // solves some aliasing-issues
        }
    }
    
    /** @inheritDoc */
    public override function dispose():Void
    {
		// if _ownsParent is true _activeTexture will be disposed by the super.dispose() call
		if (!_ownsParent) {
			_activeTexture.dispose();	
		}
        
        if (isDoubleBuffered)
        {
            _bufferTexture.dispose();
            _helperImage.dispose();
        }
        
        super.dispose();
    }
    
    /** Draws an object into the texture.
     * 
     *  @param object       The object to draw.
     *  @param matrix       If 'matrix' is null, the object will be drawn adhering its 
     *                      properties for position, scale, and rotation. If it is not null,
     *                      the object will be drawn in the orientation depicted by the matrix.
     *  @param alpha        The object's alpha value will be multiplied with this value.
     *  @param antiAliasing Values range from 0 (no antialiasing) to 4 (best quality).
     *                      Beginning with AIR 22, this feature is supported on all platforms
     *                      (except for software rendering mode).
     *  @param cameraPos    When drawing a 3D object, you can optionally pass in a custom
     *                      camera position. If left empty, the camera will be placed with
     *                      its default settings (centered over the texture, fov = 1.0).
     */
    public function draw(object:DisplayObject, matrix:Matrix=null, alpha:Float=1.0,
                         antiAliasing:Int=0, cameraPos:Vector3D=null):Void
    {
        if (object == null) return;
        
        if (_drawing)
            __render(object, matrix, alpha);
        else
            __renderBundled(__render, object, matrix, alpha, antiAliasing, cameraPos);
    }
    
    /** Bundles several calls to <code>draw</code> together in a block. This avoids buffer 
     *  switches and allows you to draw multiple objects into a non-persistent texture.
     *  Note that the 'antiAliasing' setting provided here overrides those provided in
     *  individual 'draw' calls.
     *  
     *  @param drawingBlock  a callback with the form: <pre>function():void;</pre>
     *  @param antiAliasing  Values range from 0 (no antialiasing) to 4 (best quality).
     *                       Beginning with AIR 22, this feature is supported on all platforms
     *                       (except for software rendering mode).
     *  @param cameraPos     When drawing a 3D object, you can optionally pass in a custom
     *                       camera position. If left empty, the camera will be placed with
     *                       its default settings (centered over the texture, fov = 1.0).
     */
    public function drawBundled(drawingBlock:Void->Void, antiAliasing:Int=0,
                                cameraPos:Vector3D=null):Void
    {
        var renderBlockFunc = function(object:DisplayObject, matrix:Matrix, alpha:Float):Void {drawingBlock();};
        __renderBundled(renderBlockFunc, null, null, 1.0, antiAliasing, cameraPos);
    }
    
    private var haxegonpreviousRenderTarget:Texture;
    public function bundlelock(antiAliasing:Int = 0, cameraPos:Vector3D=null):Void
    {   
        thisbundlepainer = Starling.current.painter;
        var state:RenderState = thisbundlepainer.state;

        if (!Starling.current.contextValid) return;

        // switch buffers
        if (isDoubleBuffered)
        {
            var tmpTexture:Texture = _activeTexture;
            _activeTexture = _bufferTexture;
            _bufferTexture = tmpTexture;
            _helperImage.texture = _bufferTexture;
        }

        thisbundlepainer.pushState();

        var rootTexture:Texture = _activeTexture.root;
        state.setProjectionMatrix(0, 0, rootTexture.width, rootTexture.height,
            width, height, cameraPos);

        // limit drawing to relevant area
        sClipRect.setTo(0, 0, _activeTexture.width, _activeTexture.height);

        state.clipRect = sClipRect;
        state.setRenderTarget(_activeTexture, true, antiAliasing);

        thisbundlepainer.prepareToDraw();
        thisbundlepainer.context.setStencilActions( // should not be necessary, but fixes mask issues
            Context3DTriangleFace.FRONT_AND_BACK, Context3DCompareMode.ALWAYS);

        if (isDoubleBuffered || !isPersistent || !_bufferReady)
            thisbundlepainer.clear();

        // draw buffer
        if (isDoubleBuffered && _bufferReady)
            _helperImage.render(thisbundlepainer);
        else
            _bufferReady = true;
        
        _drawing = true;
    }
    
		private var thisbundlepainer:Painter;
    public function bundleunlock():Void
    {
        _drawing = false;
        thisbundlepainer.popState();
		}
    
    private function __render(object:DisplayObject, matrix:Matrix=null, alpha:Float=1.0):Void
    {
        var painter:Painter = Starling.current.painter;
        var state:RenderState = painter.state;
        var wasCacheEnabled:Bool = painter.cacheEnabled;
        var filter:FragmentFilter = object.filter;
        var mask:DisplayObject = object.mask;

        painter.cacheEnabled = false;
        painter.pushState();

        state.alpha = object.alpha * alpha;
        state.setModelviewMatricesToIdentity();
        state.blendMode = object.blendMode == BlendMode.AUTO ?
            BlendMode.NORMAL : object.blendMode;

        if (matrix != null) state.transformModelviewMatrix(matrix);
        else        state.transformModelviewMatrix(object.transformationMatrix);

        if (mask != null)   painter.drawMask(mask, object);

        if (filter != null) filter.render(painter);
        else        object.render(painter);

        if (mask != null)   painter.eraseMask(mask, object);

        painter.popState();
        painter.cacheEnabled = wasCacheEnabled;
    }
    
    private function __renderBundled(renderBlock:DisplayObject->Matrix->Float->Void, object:DisplayObject=null,
                                     matrix:Matrix=null, alpha:Float=1.0,
                                     antiAliasing:Int=0, cameraPos:Vector3D=null):Void
    {
        var painter:Painter = Starling.current.painter;
        var state:RenderState = painter.state;

        if (!Starling.current.contextValid) return;

        // switch buffers
        if (isDoubleBuffered)
        {
            var tmpTexture:Texture = _activeTexture;
            _activeTexture = _bufferTexture;
            _bufferTexture = tmpTexture;
            _helperImage.texture = _bufferTexture;
        }

        painter.pushState();

        var rootTexture:Texture = _activeTexture.root;
        state.setProjectionMatrix(0, 0, rootTexture.width, rootTexture.height,
            width, height, cameraPos);

        // limit drawing to relevant area
        sClipRect.setTo(0, 0, _activeTexture.width, _activeTexture.height);

        state.clipRect = sClipRect;
        state.setRenderTarget(_activeTexture, true, antiAliasing);

        painter.prepareToDraw();
        painter.context.setStencilActions( // should not be necessary, but fixes mask issues
            Context3DTriangleFace.FRONT_AND_BACK, Context3DCompareMode.ALWAYS);

        if (isDoubleBuffered || !isPersistent || !_bufferReady)
            painter.clear();

        // draw buffer
        if (isDoubleBuffered && _bufferReady)
            _helperImage.render(painter);
        else
            _bufferReady = true;
        
        try
        {
            _drawing = true;
            renderBlock(object, matrix, alpha);
        }
        catch (e:Dynamic) {}
        
        _drawing = false;
        painter.popState();
    }
    
    /** Clears the render texture with a certain color and alpha value. Call without any
     *  arguments to restore full transparency. */
    public function clear(color:UInt=0, alpha:Float=0.0):Void
    {
        _activeTexture.root.clear(color, alpha);
        _bufferReady = true;
    }

    // properties

    /** Indicates if the render texture is using double buffering. This might be necessary for
     *  persistent textures, depending on the runtime version and the value of
     *  'forceDoubleBuffering'. */
    private var isDoubleBuffered(get, never):Bool;
    private function get_isDoubleBuffered():Bool { return _bufferTexture != null; }

    /** Indicates if the texture is persistent over multiple draw calls. */
    public var isPersistent(get, never):Bool;
    private function get_isPersistent():Bool { return _isPersistent; }
    
    /** @inheritDoc */
    private override function get_base():TextureBase { return _activeTexture.base; }
    
    /** @inheritDoc */
    private override function get_root():ConcreteTexture { return _activeTexture.root; }

    /** Indicates if new persistent textures should use double buffering. Single buffering
     *  is faster and requires less memory, but is not supported on all hardware.
     *
     *  <p>By default, applications running with the profile "baseline" or "baselineConstrained"
     *  will use double buffering; all others use just a single buffer. You can override this
     *  behavior, though, by assigning a different value at runtime.</p>
     *
     *  @default true for "baseline" and "baselineConstrained", false otherwise
     */
    public static var useDoubleBuffering(get, set):Bool;
    private static function get_useDoubleBuffering():Bool
    {
        if (Starling.current != null)
        {
            var painter:Painter = Starling.current.painter;
            var sharedData = painter.sharedData;

            if (sharedData.exists(USE_DOUBLE_BUFFERING_DATA_NAME))
            {
                return sharedData[USE_DOUBLE_BUFFERING_DATA_NAME];
            }
            else
            {
                var profile:String = painter.profile != null ? painter.profile : "baseline";
                var value:Bool = profile == "baseline" || profile == "baselineConstrained";
                sharedData[USE_DOUBLE_BUFFERING_DATA_NAME] = value;
                return value;
            }
        }
        else return false;
    }

    private static function set_useDoubleBuffering(value:Bool):Bool
    {
        if (Starling.current == null)
            throw new IllegalOperationError("Starling not yet initialized");
        else
            Starling.current.painter.sharedData[USE_DOUBLE_BUFFERING_DATA_NAME] = value;
        return value;
    }
}