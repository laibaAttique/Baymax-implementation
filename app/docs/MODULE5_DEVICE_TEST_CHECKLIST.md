# Real-device test checklist — 8 major movement patterns

One exercise per pattern validates every exercise that uses the pattern. About 3–4 minutes per pattern; all eight
take about half an hour. Results go into [MODULE5_DEVICE_VALIDATION.md](MODULE5_DEVICE_VALIDATION.md).

## Before you start (once)

- [ ] Phone on a stand at about hip height, 2–3 m away (floor level for push-up, plank and bridge).
- [ ] Good light from the front or side, not behind you. Plain background if possible.
- [ ] Fitted clothes, so hips, knees and elbows are visible.
- [ ] Open Baymax → **Posture check** → **Exercise library** (or your plan) → pick the exercise → Camera Detection.
- [ ] Optional (helps me tune thresholds): keep the phone connected by USB, and I can read the angle log
      (`adb logcat -s flutter`; numbers only, never images).
- [ ] If possible, a second person to count reps and watch your form. Otherwise prop up a second phone and record
      yourself, then count from the video.

For every exercise, write down:
- reps the app counted vs. reps you did (or the hold time it showed vs. a stopwatch);
- every correction that appeared, and whether your form really had that fault;
- the FPS shown in the corner;
- anything odd (skeleton jumping, losing you, wrong side).

**Pass** = reps within ±1 per set, each deliberate fault caught on at least 8 of 10 reps, and wrong corrections on at
most 1 of 10 correct reps.

---

## 1. Squat — *Bodyweight Squat* (re-confirm; it is the reference)
Camera: side-on, whole body.
- [ ] 10 correct squats, thighs about parallel. Expect 10 reps and no corrections.
- [ ] 10 squats leaning your chest far forward. Expect "Keep your back straight — lift your chest".
- [ ] 5 half squats (stop high). Expect them not counted, and "Lower your hips more".
- [ ] Facing the camera, 5 squats letting your knees cave in. Expect "Push your knees out over your toes".

## 2. Push-up — *Push-Ups* (curated) and *Wide Push-Up* (dataset-style hip check)
Camera: floor level, side-on.
- [ ] 10 correct push-ups. Expect 10 reps and no corrections.
- [ ] 10 with your hips sagging toward the floor. Expect "Raise your hips slightly — don't let them sag" (Wide Push-Up),
      or the body-line cue (Push-Ups).
- [ ] 10 with your hips piked up. Expect "Lower your hips into a straight line".
- [ ] 5 shallow reps (chest stays high). Expect them not counted.

## 3. Lunge — *Lunges*
Camera: side-on.
- [ ] 10 correct lunges, torso upright. Expect 10 reps and no corrections.
- [ ] 10 leaning forward over the front knee. Expect "Keep your torso upright".
- [ ] 5 short lunges (back knee stays high). Expect them not counted.

## 4. Plank — *Plank Hold*
Camera: floor level, side-on.
- [ ] Hold 30 s in a straight line (time it). Expect the hold timer to be within ±2 s, and "Holding — …".
- [ ] Let your hips sag for 10 s. Expect "Raise your hips slightly", and the timer pauses once out of position.
- [ ] Pike your hips up for 10 s. Expect "Lower your hips into a straight line".
- [ ] Stand up. Expect the timer to stop.

## 5. Glute bridge — *Glute Bridge*
Camera: floor level, side-on.
- [ ] 10 correct bridges, feet about a shin's length from your hips. Expect 10 reps and no corrections.
- [ ] 5 with your feet far from your hips. Expect "Bring your heels a little closer to your hips".
- [ ] 5 with your heels right under your hips. Expect "Move your feet a little further from your hips".
- [ ] 5 small lifts (hips barely rise). Expect them not counted.

## 6. Biceps curl — *Dumbbell Bicep Curl* (or a water bottle)
Camera: side-on, upper body and hips.
- [ ] 10 correct curls, elbows by your sides. Expect 10 reps and no corrections.
- [ ] 10 swinging the elbows forward. Expect "Keep your upper arm still, close to your body".
- [ ] 10 leaning back to lift. Expect "Keep your body still — don't swing".
- [ ] 5 half curls. Expect them not counted.

## 7. Overhead press — *Dumbbell Shoulder Press* (or bottles)
- [ ] Side-on: 10 correct presses. Expect 10 reps and no corrections.
- [ ] Side-on: 10 leaning back while pressing. Expect "Stand tall — don't lean back".
- [ ] Facing the camera: 10 with one arm lagging. Expect "Move both arms evenly".
- [ ] 5 presses stopping at head height. Expect them not counted.

## 8. Row — *Bent Over Two-Dumbbell Row* (or a resistance band)
Camera: side-on.
- [ ] 10 correct rows, torso still. Expect 10 reps and no corrections.
- [ ] 10 heaving with your torso. Expect "Keep your torso still — pull with your arms".
- [ ] 5 short pulls (elbows stay low). Expect them not counted.

---

## Also check once (any exercise)
- [ ] Step half out of frame. Expect "Can't see your … — …" and no reps counted.
- [ ] Turn the wrong way. Expect the setup hint.
- [ ] Pause, then resume. Expect the camera to stop and restart.
- [ ] Finish a planned exercise's full target from **Today's workout**. Expect "Done today" in Posture Detection and
      the Workout tab.
- [ ] Ask the voice assistant "How many reps?" and "What's my posture score?" during a set.

## Results to send me

For each pattern: exercise, reps counted / done, which corrections fired (true / false), FPS, and pass or fail.
For example: "Curl: 10/10; upper-arm 9 of 10 caught, 0 false; sway 7 of 10 caught; 15 FPS; fail on sway". I'll record
it, tune any check that misses, and promote the patterns that pass.
