#!/usr/bin/env python3
"""Curates the Baymax exercise library (Module 3) from the open free-exercise-db dataset.

  python curate_exercises.py --dataset <free-exercise-db dist/exercises.json> --library ../../assets/data/exercises.json

Source: free-exercise-db (https://github.com/yuhonas/free-exercise-db), Unlicense / public domain, 876 exercises.
What is taken from the dataset: the exercise identity, its target muscles, mechanic (compound / isolation) and a difficulty
level. What is NOT taken: its instructions (several are written for gyms: Smith machines, benches, "jump as high as
possible", "as far as possible"), so every technique cue here is written by the project team and the entry is labelled so.

Selection rules (hand-reviewed list below): bodyweight only, no gym equipment, no partner, nothing that needs a bar or bench,
nothing expert-level, no maximal-effort or athletic-drill wording. 188 no-equipment entries were reviewed; 41 were kept.

Fields added by the team (NOT in the dataset; pending review by a qualified trainer / physiotherapist):
  joints      body regions the movement loads: knee, wrist, shoulder, lowerBack, ankle
  position    standing | seated | floor (how hard it is to get into and out of)
  complexity  1-3 coordination demand
  met         taken from the CLOSEST class already used in the library (2024 Adult Compendium codes, marked with *)
The 32 original entries keep their energy values, steps and sources; they only gain the four team fields above (ORIGINAL_ATTRS). Nothing is invented for energy: a new exercise gets the MET of its movement class.
"""
import argparse
import json

# Energy classes: (MET, Compendium code). All already used in the library; a trailing * means "closest listed activity".
CLASS = {
    'resist': (3.0, '02056*'),     # light/moderate bodyweight resistance
    'calis': (3.8, '02022*'),      # calisthenics, moderate effort
    'core': (2.8, '02024*'),       # abdominal / mat work
    'backcore': (3.5, '02030*'),
    'stretch': (2.3, '02101*'),    # stretching, mild
    'jump': (6.5, '02057*'),
    'vigorous': (7.5, '02020*'),
}
ICON = {'push': '💪', 'legs': '🦵', 'core': '🧘', 'cardio': '🏃', 'mobility': '🤸', 'back': '🏋️'}

# id, dataset id, name, group, level, impact, class, tags, joints, position, complexity, timed, reps, seconds, equipment, steps
E = [
    # ---- push (incline versions are the easier ones, the close/wide push-ups the harder ones)
    ('incline_pushup', 'Incline_Push-Up', 'Incline Push-Up', 'push', 1, 'low', 'resist', [], ['wrist', 'shoulder'], 'standing', 1, False, 10, 0, 'sturdy table, counter or wall',
     ['Place your hands on a sturdy table, counter or sofa edge, a little wider than your shoulders, and step your feet back until your body is one straight line.',
      'Bend your elbows to lower your chest toward the surface, then press back up. Keep your tummy gently tight.',
      'Use a higher surface to make it easier and a lower one to make it harder.']),
    ('incline_pushup_wide', 'Incline_Push-Up_Wide', 'Wide Incline Push-Up', 'push', 1, 'low', 'resist', [], ['wrist', 'shoulder'], 'standing', 1, False, 10, 0, 'sturdy table, counter or wall',
     ['Place your hands on a sturdy table or counter, clearly wider than your shoulders, and walk your feet back into a straight line.',
      'Lower your chest between your hands, keeping your elbows slightly angled back, then press up.',
      'Stop if you feel pinching at the front of your shoulders.']),
    ('incline_pushup_close', 'Incline_Push-Up_Close-Grip', 'Close-Hand Incline Push-Up', 'push', 1, 'low', 'resist', [], ['wrist', 'shoulder'], 'standing', 1, False, 10, 0, 'sturdy table, counter or wall',
     ['Place your hands close together under your chest on a sturdy table or counter and walk your feet back into a straight line.',
      'Lower your chest toward your hands with your elbows close to your sides, then press up.',
      'This works the backs of the arms more than a standard push-up.']),
    ('pushup_wide', 'Push-Up_Wide', 'Wide Push-Up', 'push', 2, 'low', 'calis', [], ['wrist', 'shoulder'], 'floor', 1, False, 8, 0, 'none',
     ['Start in a plank with your hands wider than your shoulders and your body in one straight line.',
      'Lower your chest toward the floor, then press back up without letting your hips sag.',
      'If this is too hard, do it on your knees or with your hands on a table.']),
    ('pushup_close', 'Push-Ups_-_Close_Triceps_Position', 'Close-Hand Push-Up', 'push', 2, 'low', 'calis', [], ['wrist', 'shoulder'], 'floor', 1, False, 8, 0, 'none',
     ['Start in a plank with your hands closer than shoulder width and your body in one straight line.',
      'Lower your chest toward your hands, keeping your elbows close to your sides, then press back up.',
      'If this is too hard, do it on your knees or with your hands on a table.']),
    # ---- legs
    ('single_leg_bridge', 'Single_Leg_Glute_Bridge', 'Single-Leg Glute Bridge', 'legs', 2, 'low', 'resist', [], [], 'floor', 2, False, 8, 0, 'none',
     ['Lie on your back with your knees bent and feet flat, then lift one leg so your knee points up.',
      'Press through the planted heel to lift your hips until your body is a straight line from shoulders to knee.',
      'Lower slowly. Finish all repetitions on one side, then switch.']),
    ('glute_kickback', 'Glute_Kickback', 'Kneeling Glute Kickback', 'legs', 1, 'low', 'resist', [], ['knee', 'wrist'], 'floor', 1, False, 10, 0, 'mat or folded towel',
     ['Get on your hands and knees on a mat, hands under shoulders and knees under hips.',
      'Keeping your knee bent, lift one leg until your thigh is in line with your back, squeezing your buttock. Do not arch your lower back.',
      'Lower with control and finish all repetitions on one side before switching.']),
    # ---- core
    ('crunch', 'Crunches', 'Crunch', 'core', 1, 'low', 'core', [], ['lowerBack'], 'floor', 1, False, 12, 0, 'none',
     ['Lie on your back with your knees bent and feet flat, hands lightly at the sides of your head with your elbows wide.',
      'Breathe out and curl your head and shoulders a short way off the floor, keeping your chin off your chest.',
      'Lower slowly. Do not pull on your neck.']),
    ('reverse_crunch', 'Reverse_Crunch', 'Reverse Crunch', 'core', 1, 'low', 'core', [], ['lowerBack'], 'floor', 1, False, 10, 0, 'none',
     ['Lie on your back with your arms by your sides and your knees bent above your hips.',
      'Breathe out and curl your hips a short way off the floor, bringing your knees toward your chest.',
      'Lower slowly without swinging your legs.']),
    ('oblique_crunch_floor', 'Oblique_Crunches_-_On_The_Floor', 'Side Crunch', 'core', 1, 'low', 'core', [], ['lowerBack'], 'floor', 1, False, 10, 0, 'none',
     ['Lie on one side with your knees slightly bent and your top hand lightly behind your head.',
      'Breathe out and lift your top shoulder toward your hip, using the side of your tummy.',
      'Lower slowly. Finish all repetitions on one side, then switch.']),
    ('cross_body_crunch', 'Cross-Body_Crunch', 'Cross-Body Crunch', 'core', 1, 'low', 'core', [], ['lowerBack'], 'floor', 1, False, 10, 0, 'none',
     ['Lie on your back with your knees bent and feet flat, hands lightly behind your head.',
      'Breathe out, lift one shoulder and turn to bring it toward the opposite knee.',
      'Lower and alternate sides.']),
    ('heel_touches', 'Alternate_Heel_Touchers', 'Heel Touches', 'core', 1, 'low', 'core', [], [], 'floor', 1, False, 16, 0, 'none',
     ['Lie on your back with your knees bent and feet flat, about shoulder width apart, arms by your sides.',
      'Lift your head and shoulders slightly and reach your right hand toward your right heel.',
      'Return to centre and reach toward the left heel. Keep the movement small and controlled.']),
    ('russian_twist', 'Russian_Twist', 'Seated Twist', 'core', 2, 'low', 'core', [], ['lowerBack'], 'seated', 2, False, 12, 0, 'none',
     ['Sit with your knees bent and feet on the floor, lean back slightly with a long straight back and your hands together in front of your chest.',
      'Turn your chest to one side, then the other, in a slow controlled way.',
      'Keep your feet on the floor to make it easier. Stop if your lower back complains.']),
    ('hip_raise_bent_knee', 'Bent-Knee_Hip_Raise', 'Bent-Knee Leg Lift', 'core', 1, 'low', 'core', [], ['lowerBack'], 'floor', 1, False, 10, 0, 'none',
     ['Lie on your back with your arms by your sides and your knees bent about 90 degrees.',
      'Lift your feet a few centimetres off the floor, keeping your lower back gently pressed down.',
      'Lower slowly. Do not let your back arch.']),
    ('spider_crawl', 'Spider_Crawl', 'Plank Knee Drive', 'core', 2, 'low', 'core', [], ['wrist', 'shoulder'], 'floor', 2, False, 10, 0, 'none',
     ['Start in a straight-arm plank with your hands under your shoulders.',
      'Lift one foot and bring that knee out toward the same elbow, then return it.',
      'Alternate sides slowly, keeping your hips level.']),
    # ---- cardio (the only high-impact additions; they are removed automatically for anyone the safety rules protect)
    ('star_jump', 'Star_Jump', 'Star Jump', 'cardio', 3, 'high', 'vigorous', ['hiit', 'plyo'], ['knee', 'ankle'], 'standing', 2, True, 0, 30, 'none',
     ['Stand with your feet together and your arms by your sides.',
      'Hop and spread your arms and legs out wide, then hop back to the start. Land softly on the balls of your feet with your knees slightly bent.',
      'Stop and rest if you feel any pain in your knees or ankles.']),
    ('split_jump', 'Split_Jump', 'Jumping Lunge', 'cardio', 3, 'high', 'jump', ['hiit', 'plyo'], ['knee', 'ankle'], 'standing', 3, True, 0, 30, 'none',
     ['Stand in a lunge position with one foot forward and your hands on your hips.',
      'Hop and switch your legs in the air, landing softly in a lunge with the other foot forward. Keep your front knee over your foot.',
      'Keep the hops low and controlled. Use a regular lunge instead if your knees or balance are a concern.']),
    # ---- mobility / stretches (hold times are gentle; stop at mild tension, never pain)
    ('hip_circles', 'Standing_Hip_Circles', 'Standing Hip Circles', 'mobility', 1, 'low', 'stretch', ['dynamic'], [], 'standing', 2, True, 0, 30, 'wall or chair for support',
     ['Stand holding a wall or chair, lift one knee to about hip height.', 'Slowly draw circles with your knee, five in each direction.', 'Switch legs.']),
    ('arm_circles', 'Arm_Circles', 'Arm Circles', 'mobility', 1, 'low', 'stretch', ['dynamic'], ['shoulder'], 'standing', 1, True, 0, 30, 'none',
     ['Stand tall with your arms out to the sides at shoulder height.', 'Make slow circles about the size of a dinner plate, breathing normally.', 'Reverse direction halfway.']),
    ('shoulder_rolls', 'Shoulder_Circles', 'Shoulder Rolls', 'mobility', 1, 'low', 'stretch', ['dynamic'], [], 'standing', 1, True, 0, 30, 'none',
     ['Stand or sit tall with your arms loose.', 'Roll your shoulders forward, up, back and down in a slow circle.', 'Reverse direction halfway.']),
    ('ankle_circles', 'Ankle_Circles', 'Ankle Circles', 'mobility', 1, 'low', 'stretch', ['dynamic'], ['ankle'], 'standing', 1, True, 0, 30, 'wall or chair for support',
     ['Hold a wall or chair and lift one foot slightly off the floor.', 'Draw slow circles with your toes, five in each direction.', 'Switch feet.']),
    ('wrist_circles', 'Wrist_Circles', 'Wrist Circles', 'mobility', 1, 'low', 'stretch', ['dynamic'], ['wrist'], 'standing', 1, True, 0, 30, 'none',
     ['Hold your arms out in front of you with relaxed fists.', 'Rotate your wrists slowly, five circles in each direction.', 'Keep the rest of your body still.']),
    ('childs_pose', 'Childs_Pose', "Child's Pose", 'mobility', 1, 'low', 'stretch', [], ['knee'], 'floor', 1, True, 0, 30, 'mat',
     ['Kneel on a mat and sit back toward your heels, then reach your hands forward along the floor.', 'Let your head rest and breathe slowly into your back.', 'If your knees complain, place a folded towel behind them or skip this one.']),
    ('hamstring_stretch_lying', 'Hamstring_Stretch', 'Lying Hamstring Stretch', 'mobility', 1, 'low', 'stretch', [], [], 'floor', 1, True, 0, 30, 'towel or belt',
     ['Lie on your back and loop a towel or belt around the ball of one foot.', 'Gently straighten that leg toward the ceiling until you feel a mild stretch behind the thigh.', 'Hold, breathe, then switch legs.']),
    ('calf_stretch_wall', 'Calf_Stretch_Hands_Against_Wall', 'Calf Stretch at the Wall', 'mobility', 1, 'low', 'stretch', [], ['ankle'], 'standing', 1, True, 0, 30, 'wall',
     ['Stand facing a wall with your hands on it and one foot stepped back, heel flat on the floor.', 'Bend the front knee and lean in until you feel a mild stretch in the back calf.', 'Hold, then switch legs.']),
    ('kneeling_hip_flexor', 'Kneeling_Hip_Flexor', 'Kneeling Hip Flexor Stretch', 'mobility', 1, 'low', 'stretch', [], ['knee'], 'floor', 1, True, 0, 30, 'mat',
     ['Kneel on a mat with one foot forward in a lunge position.', 'Tuck your tailbone under and shift forward until you feel a stretch at the front of the back hip.', 'Hold, then switch sides. Pad your knee with a towel if needed.']),
    ('standing_hip_flexor', 'Standing_Hip_Flexors', 'Standing Hip Flexor Stretch', 'mobility', 1, 'low', 'stretch', [], [], 'standing', 1, True, 0, 30, 'none',
     ['Stand with one foot a step in front of the other and your knees slightly bent.', 'Tuck your tailbone under and press your hips gently forward until you feel a stretch at the front of the back hip.', 'Hold, then switch sides.']),
    ('side_quad_stretch', 'On_Your_Side_Quad_Stretch', 'Side-Lying Quad Stretch', 'mobility', 1, 'low', 'stretch', [], ['knee'], 'floor', 1, True, 0, 30, 'mat',
     ['Lie on one side with your bottom knee bent for balance.', 'Bend your top knee and hold your foot or ankle, bringing your heel gently toward your buttock.', 'Hold, then roll over and switch sides.']),
    ('knee_across_body', 'Knee_Across_The_Body', 'Lying Glute Twist', 'mobility', 1, 'low', 'stretch', [], [], 'floor', 1, True, 0, 30, 'none',
     ['Lie on your back with one leg straight and the other knee bent.', 'Guide the bent knee across your body toward the floor with the opposite hand, keeping your shoulders down.', 'Hold, then switch sides.']),
    ('knee_to_chest', 'One_Knee_To_Chest', 'Single Knee to Chest', 'mobility', 1, 'low', 'stretch', [], [], 'floor', 1, True, 0, 30, 'none',
     ['Lie on your back and pull one knee toward your chest, holding behind the thigh (not on the kneecap).', 'Keep the other leg relaxed and your lower back resting on the floor.', 'Hold, then switch legs.']),
    ('hug_knees', 'Hug_Knees_To_Chest', 'Both Knees to Chest', 'mobility', 1, 'low', 'stretch', [], [], 'floor', 1, True, 0, 30, 'none',
     ['Lie on your back and bring both knees toward your chest.', 'Hold behind your thighs, not on your kneecaps, and breathe slowly.', 'Release gently.']),
    ('seated_hamstring_stretch', 'Seated_Floor_Hamstring_Stretch', 'Seated Hamstring Stretch', 'mobility', 1, 'low', 'stretch', [], [], 'floor', 1, True, 0, 30, 'mat',
     ['Sit with one leg straight and the other foot resting against your inner thigh.', 'Lean forward from your hips with a long back until you feel a mild stretch behind the straight leg.', 'Hold, then switch legs.']),
    ('triceps_stretch', 'Triceps_Stretch', 'Triceps Stretch', 'mobility', 1, 'low', 'stretch', [], ['shoulder'], 'standing', 1, True, 0, 30, 'none',
     ['Reach one hand behind your head and down your back.', 'Use the other hand to ease your elbow gently back and up.', 'Hold, then switch arms.']),
    ('shoulder_cross_stretch', 'Shoulder_Stretch', 'Cross-Body Shoulder Stretch', 'mobility', 1, 'low', 'stretch', [], ['shoulder'], 'standing', 1, True, 0, 30, 'none',
     ['Bring one arm straight across your chest.', 'Hold it with the other hand just above the elbow and draw it gently closer.', 'Hold, then switch arms.']),
    ('chest_opener', 'Elbows_Back', 'Standing Chest Opener', 'mobility', 1, 'low', 'stretch', [], [], 'standing', 1, True, 0, 30, 'none',
     ['Stand tall and place your hands on your lower back with your elbows out.', 'Draw your elbows gently back and lift your chest until you feel a mild stretch across the front.', 'Hold and breathe normally.']),
    ('upper_back_stretch', 'Upper_Back_Stretch', 'Upper Back Stretch', 'mobility', 1, 'low', 'stretch', [], [], 'standing', 1, True, 0, 30, 'none',
     ['Clasp your hands in front of you with your palms turned out.', 'Reach forward and round your upper back, letting your head drop gently.', 'Hold and breathe normally.']),
    ('seated_twist', 'Spinal_Stretch', 'Seated Spinal Twist', 'mobility', 1, 'low', 'stretch', [], [], 'seated', 1, True, 0, 30, 'chair',
     ['Sit tall on a chair with your feet flat on the floor.', 'Turn your upper body to one side, holding the chair back or your thigh, keeping your hips facing forward.', 'Hold, then switch sides.']),
    ('side_bend', 'Standing_Lateral_Stretch', 'Standing Side Bend', 'mobility', 1, 'low', 'stretch', [], [], 'standing', 1, True, 0, 30, 'none',
     ['Stand with your feet a little wider than your hips and your knees soft.', 'Reach one arm overhead and lean gently to the opposite side, with your other hand on your hip.', 'Hold, then switch sides.']),
    ('overhead_reach', 'Overhead_Stretch', 'Overhead Reach', 'mobility', 1, 'low', 'stretch', [], [], 'standing', 1, True, 0, 30, 'none',
     ['Stand tall and interlace your fingers, turning your palms up toward the ceiling.', 'Reach up with your shoulders relaxed and your ribs gently drawn in.', 'Hold and breathe normally.']),
    ('inchworm', 'Inchworm', 'Inchworm', 'mobility', 2, 'low', 'stretch', ['dynamic'], ['wrist', 'shoulder'], 'standing', 2, True, 0, 30, 'none',
     ['Stand tall, then bend forward and place your hands on the floor (bend your knees as much as you need).', 'Walk your hands forward to a plank, pause, then walk them back to your feet.', 'Stand up slowly.']),
    ('worlds_greatest_stretch', 'Worlds_Greatest_Stretch', 'Lunge with Rotation', 'mobility', 2, 'low', 'stretch', ['dynamic'], ['knee', 'wrist'], 'floor', 3, True, 0, 30, 'mat',
     ['Step into a long lunge and place both hands on the floor inside your front foot.', 'Lift the inside hand toward the ceiling, turning your chest open, and follow it with your eyes.', 'Return the hand to the floor, then switch sides.']),
]

# Team-assigned body-load attributes for the 32 original entries: joints, position, complexity, mechanic, equipment.
ORIGINAL_ATTRS = {
    'warmup': ([], 'standing', 1, '', 'none'), 'cooldown': ([], 'standing', 1, '', 'none'),
    'brisk_walk': ([], 'standing', 1, '', 'none'), 'march': ([], 'standing', 1, '', 'none'),
    'step_ups': (['knee'], 'standing', 2, 'compound', 'sturdy step'), 'shadow_boxing': (['shoulder'], 'standing', 2, '', 'none'),
    'jumping_jacks': (['knee', 'ankle'], 'standing', 2, '', 'none'), 'high_knees': (['knee', 'ankle'], 'standing', 2, '', 'none'),
    'mountain_climbers': (['wrist', 'shoulder'], 'floor', 2, 'compound', 'none'), 'burpees': (['knee', 'wrist', 'shoulder'], 'floor', 3, 'compound', 'none'),
    'jump_squats': (['knee', 'ankle'], 'standing', 2, 'compound', 'none'),
    'chair_squat': (['knee'], 'standing', 1, 'compound', 'chair'), 'squat': (['knee'], 'standing', 1, 'compound', 'none'),
    'lunge': (['knee'], 'standing', 2, 'compound', 'none'), 'glute_bridge': ([], 'floor', 1, '', 'none'),
    'calf_raise': (['ankle'], 'standing', 1, 'isolation', 'none'), 'wall_sit': (['knee'], 'standing', 1, '', 'wall'),
    'wall_pushup': (['wrist', 'shoulder'], 'standing', 1, 'compound', 'wall'), 'knee_pushup': (['wrist', 'knee'], 'floor', 1, 'compound', 'none'),
    'pushup': (['wrist', 'shoulder'], 'floor', 1, 'compound', 'none'), 'tricep_dip': (['wrist', 'shoulder'], 'seated', 1, 'compound', 'chair'),
    'shoulder_taps': (['wrist', 'shoulder'], 'floor', 2, '', 'none'), 'superman': (['lowerBack'], 'floor', 1, '', 'none'),
    'bird_dog': (['wrist', 'knee'], 'floor', 2, '', 'none'), 'reverse_snow_angel': (['shoulder', 'lowerBack'], 'floor', 1, '', 'none'),
    'dead_bug': ([], 'floor', 2, '', 'none'), 'plank': (['wrist', 'shoulder'], 'floor', 1, '', 'none'),
    'bicycle_crunch': (['lowerBack'], 'floor', 2, '', 'none'), 'leg_raise': (['lowerBack'], 'floor', 1, '', 'none'),
    'side_plank_knee': (['wrist', 'shoulder', 'knee'], 'floor', 1, '', 'none'), 'cat_cow': (['wrist', 'knee'], 'floor', 1, '', 'none'),
    'single_leg_balance': ([], 'standing', 2, '', 'wall or chair for support'),
}

DS_MUSCLE = {'abdominals': 'Core', 'quadriceps': 'Quads', 'lower back': 'Lower back', 'middle back': 'Upper back', 'lats': 'Back',
             'hamstrings': 'Hamstrings', 'glutes': 'Glutes', 'chest': 'Chest', 'triceps': 'Triceps', 'shoulders': 'Shoulders',
             'calves': 'Calves', 'adductors': 'Inner thighs', 'abductors': 'Hips', 'forearms': 'Forearms', 'biceps': 'Biceps', 'traps': 'Upper back', 'neck': 'Neck'}
STRETCH_FALLBACK = {'hip_circles': ['Hips'], 'arm_circles': ['Shoulders'], 'shoulder_rolls': ['Shoulders'], 'ankle_circles': ['Calves'], 'wrist_circles': ['Forearms'],
                    'childs_pose': ['Lower back'], 'inchworm': ['Hamstrings', 'Shoulders']}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--dataset', required=True)
    ap.add_argument('--library', required=True)
    args = ap.parse_args()
    ds = {x['id']: x for x in json.load(open(args.dataset))}
    lib = json.load(open(args.library))
    items = lib if isinstance(lib, list) else lib['exercises']
    curated_ids = {e[0] for e in E}
    base = [i for i in items if i['id'] not in curated_ids]       # the original team library
    for i in base:
        if i['id'] not in ORIGINAL_ATTRS:
            raise SystemExit(f"no body-load attributes for original exercise {i['id']}")
        i['joints'], i['position'], i['complexity'], i['mechanic'], i['equipment'] = ORIGINAL_ATTRS[i['id']]
    have = {i['id'] for i in base}
    used_ref = {i.get('referenceId') for i in base}
    added = []
    for (eid, dsid, name, group, level, impact, cls, tags, joints, position, cx, timed, reps, secs, equip, steps) in E:
        if eid in have:
            raise SystemExit(f'duplicate id {eid}')
        if dsid not in ds:
            raise SystemExit(f'dataset id not found: {dsid}')
        if dsid in used_ref:
            raise SystemExit(f'dataset entry already used by the existing library: {dsid}')
        x = ds[dsid]
        if x.get('equipment') not in ('body only', None):
            raise SystemExit(f'{dsid} needs equipment: {x.get("equipment")}')
        muscles = [DS_MUSCLE.get(m, m.title()) for m in x['primaryMuscles'] + x['secondaryMuscles']]
        muscles = muscles or STRETCH_FALLBACK.get(eid, [])
        muscles = list(dict.fromkeys(muscles))[:4]
        met, code = CLASS[cls]
        added.append({
            'id': eid, 'name': name, 'icon': ICON[group], 'group': group, 'muscles': muscles, 'impact': impact, 'level': level,
            'met': met, 'compendium': code, 'timed': timed, 'baseReps': reps or 10, 'baseSeconds': secs or 30,
            'tags': tags, 'steps': steps, 'techniqueSource': 'free-exercise-db', 'referenceId': dsid, 'referenceMatch': 'related',
            'joints': joints, 'position': position, 'complexity': cx, 'mechanic': x.get('mechanic') or '', 'equipment': equip,
            'curated': 'free-exercise-db, reviewed 2026-10-13',
        })
    out = base + added
    json.dump(out if isinstance(lib, list) else {**lib, 'exercises': out}, open(args.library, 'w'), indent=1, ensure_ascii=False)
    by = {}
    for a in added:
        by[a['group']] = by.get(a['group'], 0) + 1
    print(f'library: {len(base)} original + {len(added)} curated = {len(out)}; added by group: {by}')


if __name__ == '__main__':
    main()
