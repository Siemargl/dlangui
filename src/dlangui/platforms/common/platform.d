module dlangui.platforms.common.platform;

public import dlangui.core.events;
import dlangui.widgets.widget;
import dlangui.graphics.drawbuf;
import std.file;
private import dlangui.graphics.gldrawbuf;

class Window {
    protected int _dx;
    protected int _dy;
	protected uint _backgroundColor;
    protected Widget _mainWidget;
	@property uint backgroundColor() { return _backgroundColor; }
	@property void backgroundColor(uint color) { _backgroundColor = color; }
    @property int width() { return _dx; }
    @property int height() { return _dy; }
    @property Widget mainWidget() { return _mainWidget; }
    @property void mainWidget(Widget widget) { 
        if (_mainWidget !is null)
            _mainWidget.window = null;
        _mainWidget = widget; 
        if (_mainWidget !is null)
            _mainWidget.window = this;
    }
    abstract void show();
    abstract @property string windowCaption();
    abstract @property void windowCaption(string caption);
    void onResize(int width, int height) {
        if (_dx == width && _dy == height)
            return;
        _dx = width;
        _dy = height;
        if (_mainWidget !is null) {
            Log.d("onResize ", _dx, "x", _dy);
            long measureStart = currentTimeMillis;
            _mainWidget.measure(_dx, _dy);
            long measureEnd = currentTimeMillis;
            Log.d("measure took ", measureEnd - measureStart, " ms");
            _mainWidget.layout(Rect(0, 0, _dx, _dy));
            long layoutEnd = currentTimeMillis;
            Log.d("layout took ", layoutEnd - measureEnd, " ms");
        }
    }

    long lastDrawTs;

	this() {
		_backgroundColor = 0xFFFFFF;
	}
	~this() {
		if (_mainWidget !is null) {
			destroy(_mainWidget);
		_mainWidget = null;
		}
	}

    private void animate(Widget root, long interval) {
        if (root.visibility != Visibility.Visible)
            return;
        for (int i = 0; i < root.childCount; i++)
            animate(root.child(i), interval);
        if (root.animating)
            root.animate(interval);
    }

    void onDraw(DrawBuf buf) {
        if (_mainWidget !is null) {
            bool needDraw = false;
            bool needLayout = false;
            bool animationActive = false;
            checkUpdateNeeded(needDraw, needLayout, animationActive);
            if (needLayout || animationActive)
                needDraw = true;
            long ts = std.datetime.Clock.currStdTime;
            if (animationActive && lastDrawTs != 0) {
                animate(_mainWidget, ts - lastDrawTs);
                // layout required flag could be changed during animate - check again
                checkUpdateNeeded(needDraw, needLayout, animationActive);
            }
            if (needLayout) {
                long measureStart = currentTimeMillis;
                _mainWidget.measure(_dx, _dy);
                long measureEnd = currentTimeMillis;
                Log.d("measure took ", measureEnd - measureStart, " ms");
                _mainWidget.layout(Rect(0, 0, _dx, _dy));
                long layoutEnd = currentTimeMillis;
                Log.d("layout took ", layoutEnd - measureEnd, " ms");
                //checkUpdateNeeded(needDraw, needLayout, animationActive);
            }
            long drawStart = currentTimeMillis;
            _mainWidget.onDraw(buf);
            long drawEnd = currentTimeMillis;
            Log.d("draw took ", drawEnd - drawStart, " ms");
            lastDrawTs = ts;
            if (animationActive)
                scheduleAnimation();
        }
    }

    /// after drawing, call to schedule redraw if animation is active
    void scheduleAnimation() {
        // override if necessary
    }

    protected bool dispatchMouseEvent(Widget root, MouseEvent event) {
        // only route mouse events to visible widgets
        if (root.visibility != Visibility.Visible)
            return false;
        if (!root.isPointInside(event.x, event.y))
            return false;
        // offer event to children first
        for (int i = 0; i < root.childCount; i++) {
            Widget child = root.child(i);
            if (dispatchMouseEvent(child, event))
                return true;
        }
        // if not processed by children, offer event to root
        if (root.onMouseEvent(event)) {
            Log.d("MouseEvent is processed");
            if (event.action == MouseAction.ButtonDown && _mouseCaptureWidget is null) {
                Log.d("Setting active widget");
                _mouseCaptureWidget = root;
                _mouseCaptureButtons = event.flags & (MouseFlag.LButton|MouseFlag.RButton|MouseFlag.MButton);
            } else if (event.action == MouseAction.Move) {
                addTracking(root);
            }
            return true;
        }
        return false;
    }

    /// widget which tracks Move events
    //protected Widget _mouseTrackingWidget;
    protected Widget[] _mouseTrackingWidgets;
    private void addTracking(Widget w) {
        for(int i = 0; i < _mouseTrackingWidgets.length; i++)
            if (w is _mouseTrackingWidgets[i])
                return;
        //foreach(widget; _mouseTrackingWidgets)
        //    if (widget is w)
        //       return;
        //Log.d("addTracking ", w.id, " items before: ", _mouseTrackingWidgets.length);
        _mouseTrackingWidgets ~= w;
        //Log.d("addTracking ", w.id, " items after: ", _mouseTrackingWidgets.length);
    }
    private bool checkRemoveTracking(MouseEvent event) {
        import std.algorithm;
        bool res = false;
        for(int i = _mouseTrackingWidgets.length - 1; i >=0; i--) {
            Widget w = _mouseTrackingWidgets[i];
            if (!_mainWidget.isChild(w)) {
                // std.algorithm.remove does not work for me
                //_mouseTrackingWidgets.remove(i);
                for (int j = i; j < _mouseTrackingWidgets.length - 1; j++)
                    _mouseTrackingWidgets[j] = _mouseTrackingWidgets[j + 1];
                _mouseTrackingWidgets.length--;
                continue;
            }
            if (event.action == MouseAction.Leave || !w.isPointInside(event.x, event.y)) {
                // send Leave message
                MouseEvent leaveEvent = new MouseEvent(event);
                leaveEvent.changeAction(MouseAction.Leave);
                res = w.onMouseEvent(leaveEvent) || res;
                // std.algorithm.remove does not work for me
                //Log.d("removeTracking ", w.id, " items before: ", _mouseTrackingWidgets.length);
                //_mouseTrackingWidgets.remove(i);
                //_mouseTrackingWidgets.length--;
                for (int j = i; j < _mouseTrackingWidgets.length - 1; j++)
                    _mouseTrackingWidgets[j] = _mouseTrackingWidgets[j + 1];
                _mouseTrackingWidgets.length--;
                //Log.d("removeTracking ", w.id, " items after: ", _mouseTrackingWidgets.length);
            }
        }
        return res;
    }

    /// widget which tracks all events after processed ButtonDown
    protected Widget _mouseCaptureWidget;
	protected ushort _mouseCaptureButtons;
    protected bool _mouseCaptureFocusedOut;
	/// does current capture widget want to receive move events even if pointer left it
    protected bool _mouseCaptureFocusedOutTrackMovements;
	
	protected bool dispatchCancel(MouseEvent event) {
    	event.changeAction(MouseAction.Cancel);
        bool res = _mouseCaptureWidget.onMouseEvent(event);
		_mouseCaptureWidget = null;
		_mouseCaptureFocusedOut = false;
		return res;
	}
	
    /// dispatch mouse event to window content widgets
    bool dispatchMouseEvent(MouseEvent event) {
        // ignore events if there is no root
        if (_mainWidget is null)
            return false;

        // check if _mouseCaptureWidget and _mouseTrackingWidget still exist in child of root widget
        if (_mouseCaptureWidget !is null && !_mainWidget.isChild(_mouseCaptureWidget))
            _mouseCaptureWidget = null;

        //Log.d("dispatchMouseEvent ", event.action, "  (", event.x, ",", event.y, ")");

        bool res = false;
		ushort currentButtons = event.flags & (MouseFlag.LButton|MouseFlag.RButton|MouseFlag.MButton);
        if (_mouseCaptureWidget !is null) {
            // try to forward message directly to active widget
            if (event.action == MouseAction.Move) {
                if (!_mouseCaptureWidget.isPointInside(event.x, event.y)) {
					if (currentButtons != _mouseCaptureButtons)
						return dispatchCancel(event);
                    // point is no more inside of captured widget
                    if (!_mouseCaptureFocusedOut) {
                        // sending FocusOut message
                        event.changeAction(MouseAction.FocusOut);
                        _mouseCaptureFocusedOut = true;
						_mouseCaptureButtons = currentButtons;
                        _mouseCaptureFocusedOutTrackMovements = _mouseCaptureWidget.onMouseEvent(event);
                        return true;
                    } else if (_mouseCaptureFocusedOutTrackMovements) {
						// pointer is outside, but we still need to track pointer
                        return _mouseCaptureWidget.onMouseEvent(event);
                    }
					// don't forward message
                    return true;
                } else {
                    // point is inside widget
                    if (_mouseCaptureFocusedOut) {
                        _mouseCaptureFocusedOut = false;
						if (currentButtons != _mouseCaptureButtons)
							return dispatchCancel(event);
                       	event.changeAction(MouseAction.FocusIn); // back in after focus out
                    }
                    return _mouseCaptureWidget.onMouseEvent(event);
                }
            } else if (event.action == MouseAction.Leave) {
                if (!_mouseCaptureFocusedOut) {
                    // sending FocusOut message
                    event.changeAction(MouseAction.FocusOut);
                    _mouseCaptureFocusedOut = true;
					_mouseCaptureButtons = event.flags & (MouseFlag.LButton|MouseFlag.RButton|MouseFlag.MButton);
                    return _mouseCaptureWidget.onMouseEvent(event);
                }
                return true;
            }
            // other messages
            res = _mouseCaptureWidget.onMouseEvent(event);
            if (!currentButtons) {
                // usable capturing - no more buttons pressed
                Log.d("unsetting active widget");
                _mouseCaptureWidget = null;
            }
            return res;
        }
        bool processed = false;
        if (event.action == MouseAction.Move || event.action == MouseAction.Leave) {
            processed = checkRemoveTracking(event);
        }
        if (!res) {
            res = dispatchMouseEvent(_mainWidget, event);
        }
        return res || processed;
    }

    /// checks content widgets for necessary redraw and/or layout
    protected void checkUpdateNeeded(Widget root, ref bool needDraw, ref bool needLayout, ref bool animationActive) {
        if (!root.visibility == Visibility.Visible)
            return;
        needDraw = root.needDraw || needDraw;
        if (!needLayout) {
            needLayout = root.needLayout || needLayout;
            if (needLayout) {
                Log.d("need layout: ", root.id);
            }
        }
        animationActive = root.animating || animationActive;
        for (int i = 0; i < root.childCount; i++)
            checkUpdateNeeded(root.child(i), needDraw, needLayout, animationActive);
    }
    /// checks content widgets for necessary redraw and/or layout
    bool checkUpdateNeeded(ref bool needDraw, ref bool needLayout, ref bool animationActive) {
        needDraw = needLayout = animationActive = false;
        if (_mainWidget is null)
            return false;
        checkUpdateNeeded(_mainWidget, needDraw, needLayout, animationActive);
        return needDraw || needLayout || animationActive;
    }
    /// requests update for window (unless force is true, update will be performed only if layout, redraw or animation is required).
    void update(bool force = false) {
        if (_mainWidget is null)
            return;
        bool needDraw = false;
        bool needLayout = false;
        bool animationActive = false;
        if (checkUpdateNeeded(needDraw, needLayout, animationActive) || force) {
            Log.d("Requesting update");
            invalidate();
        }
        Log.d("checkUpdateNeeded returned needDraw=", needDraw, " needLayout=", needLayout, " animationActive=", animationActive);
    }
    /// request window redraw
    abstract void invalidate();
}

class Platform {
    static __gshared Platform _instance;
    static void setInstance(Platform instance) {
        _instance = instance;
    }
    static Platform instance() {
        return _instance;
    }
    abstract Window createWindow(string windowCaption, Window parent);
    abstract int enterMessageLoop();
}

version (USE_OPENGL) {
    private __gshared bool _OPENGL_ENABLED = false;
    /// check if hardware acceleration is enabled
    @property bool openglEnabled() { return _OPENGL_ENABLED; }
    /// call on app initialization if OpenGL support is detected
    void setOpenglEnabled() {
        _OPENGL_ENABLED = true;
	    glyphDestroyCallback = &onGlyphDestroyedCallback;
    }
}

version (Windows) {
    immutable char PATH_DELIMITER = '\\';
} else {
    immutable char PATH_DELIMITER = '/';
}

/// returns current executable path only, including last path delimiter
string exePath() {
    string path = thisExePath();
    int lastSlash = 0;
    for (int i = 0; i < path.length; i++)
        if (path[i] == PATH_DELIMITER)
            lastSlash = i;
    return path[0 .. lastSlash + 1];
}
