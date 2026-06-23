// Import from zod/v4 to match the type universe of the Anthropic SDK's
// zodOutputFormat helper (which imports `zod/v4`); mixing v3 and v4 types
// breaks the structured-output inference.
import { z } from "zod/v4";

// ---------------------------------------------------------------------------
// The single source of truth shared with the watch (see ../README.md and the
// root CLAUDE.md contract). The Zod schema both (a) constrains Claude's output
// via structured outputs and (b) validates anything we serve.
//
// Rule: target_hold_seconds != null && > 0  => isometric hold exercise;
//       otherwise a reps exercise (target_reps may be null = "to failure").
// ---------------------------------------------------------------------------

export const ExerciseSchema = z.object({
  name: z.string(),
  sets: z.number().int(),
  target_reps: z.number().int().nullable(),
  target_hold_seconds: z.number().int().nullable(),
  rest_seconds: z.number().int(),
});

export const BlockSchema = z.object({
  block_name: z.string(),
  exercises: z.array(ExerciseSchema),
});

export const SessionSchema = z.object({
  session_id: z.string(),
  session_name: z.string(),
  blocks: z.array(BlockSchema),
});

export type Session = z.infer<typeof SessionSchema>;

// Stable id so the watch's local log key (`log:<session_id>`) and offline cache
// are deterministic for a given athlete + day.
export function sessionIdFor(userId: string, date = new Date()): string {
  return `${userId}-${date.toISOString().slice(0, 10)}`;
}

// Built-in session used when no ANTHROPIC_API_KEY is set, or as a last-resort
// fallback if generation fails — the endpoint must never leave the watch
// without a usable plan.
export function sampleSession(userId: string): Session {
  return {
    session_id: sessionIdFor(userId),
    session_name: "Push & Core",
    blocks: [
      {
        block_name: "Warm-up",
        exercises: [
          { name: "Scapular Pulls", sets: 2, target_reps: 10, target_hold_seconds: null, rest_seconds: 30 },
          { name: "Plank", sets: 1, target_reps: null, target_hold_seconds: 30, rest_seconds: 30 },
        ],
      },
      {
        block_name: "Push",
        exercises: [
          { name: "Push-ups", sets: 4, target_reps: 12, target_hold_seconds: null, rest_seconds: 90 },
          { name: "Pike Push-ups", sets: 3, target_reps: 8, target_hold_seconds: null, rest_seconds: 90 },
        ],
      },
      {
        block_name: "Core",
        exercises: [
          { name: "Hollow Hold", sets: 3, target_reps: null, target_hold_seconds: 20, rest_seconds: 60 },
          { name: "Leg Raises", sets: 3, target_reps: 12, target_hold_seconds: null, rest_seconds: 45 },
        ],
      },
    ],
  };
}

// ---------------------------------------------------------------------------
// Phase C — logged-history contract (additive, optional). After a workout the
// watch POSTs what the athlete actually did, per set, to
//   POST {BASE_URL}/sessions/log   (Authorization: Bearer <token>)
// The backend stores it (history.json) and feeds a compact summary back to
// Claude so the NEXT day's session adapts: progress when targets are met, hold
// or regress when they are missed. Generation still works with no history.
// ---------------------------------------------------------------------------

export const SetResultSchema = z.object({
  exercise: z.string(),
  target_reps: z.number().int().nullable(),
  target_hold_seconds: z.number().int().nullable(),
  achieved_reps: z.number().int().nullable(),
  achieved_hold_seconds: z.number().int().nullable(),
  completed: z.boolean(),
});

export const LogPayloadSchema = z.object({
  user_id: z.string(),
  session_id: z.string(),
  results: z.array(SetResultSchema),
});

export type SetResult = z.infer<typeof SetResultSchema>;
export type LogPayload = z.infer<typeof LogPayloadSchema>;
