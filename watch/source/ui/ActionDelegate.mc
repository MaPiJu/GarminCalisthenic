using Toybox.WatchUi;
using Toybox.System;

// ---------------------------------------------------------------------------
// Input abstraction. This is the single place that knows about physical input.
//
// It collapses BOTH button input (onKey) AND touch input (onTap) onto four
// semantic actions: action / adjustUp / adjustDown / cancel. Touch handling is
// gated by isTouchScreen checked AT RUNTIME (not compile time) because the
// Fenix 8 can run in either mode.
//
//   Buttons : ENTER = action, UP = adjustUp, DOWN = adjustDown, ESC -> onBack = cancel
//   Touch   : top third = adjustUp, bottom third = adjustDown, middle = action;
//             back swipe -> onBack = cancel
//
// Subclasses (here: ScreenDelegate) override the four onXxx() hooks. Returning
// true consumes the event.
// ---------------------------------------------------------------------------

class ActionDelegate extends WatchUi.BehaviorDelegate {

    private var _isTouch;

    function initialize() {
        BehaviorDelegate.initialize();
        // Runtime check — do NOT assume a single interaction mode.
        _isTouch = System.getDeviceSettings().isTouchScreen;
    }

    // ----- Button input ----------------------------------------------------
    function onKey(evt) {
        var key = evt.getKey();
        if (key == WatchUi.KEY_ENTER) {
            return onAction();
        } else if (key == WatchUi.KEY_UP) {
            return onAdjustUp();
        } else if (key == WatchUi.KEY_DOWN) {
            return onAdjustDown();
        }
        // ESC is not handled here so it falls through to onBack() (below),
        // which also covers the touch back-swipe — one path for "cancel".
        return false;
    }

    function onBack() {
        return onCancel();
    }

    // ----- Touch input -----------------------------------------------------
    function onTap(evt) {
        if (!_isTouch) {
            return false;
        }
        var coord = evt.getCoordinates();
        var y = coord[1];
        var height = System.getDeviceSettings().screenHeight;
        if (y < height * 0.28) {
            return onAdjustUp();
        } else if (y > height * 0.72) {
            return onAdjustDown();
        }
        return onAction();
    }

    // ----- Semantic hooks (override in subclasses) -------------------------
    protected function onAction() {
        return false;
    }

    protected function onAdjustUp() {
        return false;
    }

    protected function onAdjustDown() {
        return false;
    }

    protected function onCancel() {
        return false;
    }
}

// ---------------------------------------------------------------------------
// One forwarding delegate for every screen: it routes the four semantic actions
// to whatever view is currently active. Views implement the handleXxx() methods
// they care about (returning true if handled). This keeps a single input class
// instead of one delegate subclass per screen.
// ---------------------------------------------------------------------------
class ScreenDelegate extends ActionDelegate {

    private var _target;

    function initialize(target) {
        ActionDelegate.initialize();
        _target = target;
    }

    protected function onAction() {
        return _target.handleAction();
    }

    protected function onAdjustUp() {
        return _target.handleUp();
    }

    protected function onAdjustDown() {
        return _target.handleDown();
    }

    protected function onCancel() {
        return _target.handleCancel();
    }
}
