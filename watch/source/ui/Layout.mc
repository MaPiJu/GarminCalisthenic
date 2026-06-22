using Toybox.System;
using Toybox.Graphics;

// ---------------------------------------------------------------------------
// Relative layout + theme helpers. Everything is expressed as a fraction of the
// real screen size so the same code lays out correctly on every target screen
// (round AMOLED, round MIP, different diameters). No fixed pixel coordinates.
// ---------------------------------------------------------------------------

module Theme {
    // Black background suits both AMOLED (battery) and MIP (contrast).
    const BG       = Graphics.COLOR_BLACK;
    const FG       = Graphics.COLOR_WHITE;
    const DIM      = Graphics.COLOR_LT_GRAY;
    const ACCENT   = 0x00B0A0; // teal; maps to nearest palette colour on MIP
    const WARN     = Graphics.COLOR_RED;
}

module Layout {

    function settings() {
        return System.getDeviceSettings();
    }

    function w() {
        return settings().screenWidth;
    }

    function h() {
        return settings().screenHeight;
    }

    function cx() {
        return w() / 2;
    }

    function cy() {
        return h() / 2;
    }

    function isRound() {
        return settings().screenShape == System.SCREEN_SHAPE_ROUND;
    }

    function isTouch() {
        return settings().isTouchScreen;
    }

    // Absolute y for a fraction of the screen height.
    function fy(frac) {
        return (h() * frac).toNumber();
    }

    // Absolute x for a fraction of the screen width.
    function fx(frac) {
        return (w() * frac).toNumber();
    }

    // Clear the screen to the theme background.
    function clear(dc) {
        dc.setColor(Graphics.COLOR_TRANSPARENT, Theme.BG);
        dc.clear();
    }

    // Centered single line of text.
    function centerText(dc, frac, font, color, text) {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx(), fy(frac), font,
            text,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Format seconds as m:ss.
    function fmtClock(totalSeconds) {
        var m = totalSeconds / 60;
        var s = totalSeconds % 60;
        return m.format("%d") + ":" + s.format("%02d");
    }
}
