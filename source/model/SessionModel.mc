using Toybox.Lang;

// ---------------------------------------------------------------------------
// Plain data model + parser for a workout session.
//
// These objects are produced from a Dictionary that has the shape of the
// session JSON contract (see CLAUDE.md). The Dictionary may come from the
// bundled mock resource today, or from makeWebRequest later — the parser does
// not care about the source.
// ---------------------------------------------------------------------------

class Exercise {
    public var name;                // String
    public var sets;                // Number (>= 1)
    public var targetReps;          // Number or null
    public var targetHoldSeconds;   // Number or null
    public var restSeconds;         // Number (>= 0)

    function initialize(name, sets, targetReps, targetHoldSeconds, restSeconds) {
        self.name = name;
        self.sets = sets;
        self.targetReps = targetReps;
        self.targetHoldSeconds = targetHoldSeconds;
        self.restSeconds = restSeconds;
    }

    // Isometric hold exercise vs. reps exercise.
    function isHold() {
        return targetHoldSeconds != null && targetHoldSeconds > 0;
    }
}

class Block {
    public var name;        // String
    public var exercises;   // Array<Exercise>

    function initialize(name, exercises) {
        self.name = name;
        self.exercises = exercises;
    }
}

class Session {
    public var id;          // String
    public var name;        // String
    public var blocks;      // Array<Block>

    function initialize(id, name, blocks) {
        self.id = id;
        self.name = name;
        self.blocks = blocks;
    }
}

// Coerce a JSON value to a Number with a fallback (handles null / Float).
function numOr(value, fallback) {
    if (value == null) {
        return fallback;
    }
    return value.toNumber();
}

// Build a Session from a Dictionary matching the JSON data contract.
function parseSession(dict) {
    var blocks = [];
    var rawBlocks = dict.get("blocks");
    if (rawBlocks != null) {
        for (var i = 0; i < rawBlocks.size(); i++) {
            var rb = rawBlocks[i];
            var exercises = [];
            var rawExercises = rb.get("exercises");
            if (rawExercises != null) {
                for (var j = 0; j < rawExercises.size(); j++) {
                    var re = rawExercises[j];
                    exercises.add(new Exercise(
                        re.get("name"),
                        numOr(re.get("sets"), 1),
                        re.get("target_reps"),
                        re.get("target_hold_seconds"),
                        numOr(re.get("rest_seconds"), 0)
                    ));
                }
            }
            blocks.add(new Block(rb.get("block_name"), exercises));
        }
    }
    return new Session(dict.get("session_id"), dict.get("session_name"), blocks);
}
