using Toybox.Attention;

// Haptic feedback, guarded so it is safe on devices without a vibration motor.
module Feedback {

    function vibrateEnd() {
        if ((Toybox has :Attention) && (Attention has :vibrate)) {
            try {
                Attention.vibrate([
                    new Attention.VibeProfile(75, 600)
                ]);
            } catch (ex) {
            }
        }
    }
}
