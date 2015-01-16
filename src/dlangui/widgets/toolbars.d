// Written in the D programming language.

/**

This module implements support of tool bars.

ToolBarHost is layout to hold one or more toolbars.

ToolBar is bar with tool buttons and other controls arranged horizontally.

Synopsis:

----
import dlangui.widgets.toolbars;
----


Copyright: Vadim Lopatin, 2015
License:   Boost License 1.0
Authors:   Vadim Lopatin, coolreader.org@gmail.com
*/
module dlangui.widgets.toolbars;

import dlangui.widgets.widget;
import dlangui.widgets.layouts;
import dlangui.widgets.controls;

/// Layout with several toolbars
class ToolBarHost : HorizontalLayout {
    this(string ID) {
        super(ID);
    }
    this() {
        this("TOOLBAR_HOST");
        styleId = STYLE_TOOLBAR_HOST;
    }
    /// create and add new toolbar (returns existing one if already exists)
    ToolBar getOrAddToolbar(string ID) {
        ToolBar res = getToolbar(ID);
        if (!res) {
            res = new ToolBar(ID);
            addChild(res);
        }
        return res;
    }
    /// get toolbar by id; null if not found
    ToolBar getToolbar(string ID) {
        Widget res = childById(ID);
        if (res) {
            ToolBar tb = cast(ToolBar)res;
            return tb;
        }
        return null;
    }
    /// override to handle specific actions
	override bool handleAction(const Action a) {
        // route to focused control first, then to main widget
        return window.dispatchAction(a);
    }
}

/// image button for toolbar
class ToolBarImageButton : ImageButton {
    this(Action a) {
        super(a);
        styleId = STYLE_TOOLBAR_BUTTON;
        focusable = false;
    }
}

/// separator for toolbars
class ToolBarSeparator : ImageWidget {
    this() {
        super("separator", "toolbar_separator");
        styleId = STYLE_TOOLBAR_SEPARATOR;
    }
}

/// Layout with buttons
class ToolBar : HorizontalLayout {
    this(string ID) {
        super(ID);
        styleId = STYLE_TOOLBAR;
    }
    this() {
        this("TOOLBAR");
    }
    void addCustomControl(Widget widget) {
        addChild(widget);
    }
    /// adds image button to toolbar
    void addButtons(Action[] actions...) {
        foreach(a; actions) {
            if (a.isSeparator) {
                addChild(new ToolBarSeparator());
            } else {
                Widget btn;
                if (a.iconId) {
                    btn = new ToolBarImageButton(a);
                } else {
                    btn = new Button(a);
                    btn.styleId = STYLE_TOOLBAR_BUTTON;
                }
                addChild(btn);
            }
        }
    }

}
