"""Movement-pattern classification for free-exercise-db records (Module 5 camera tracking).

Each record gets ONE movement pattern. The pattern decides which camera tracker follows it
(lib/services/posture/movement_patterns.dart), or it is `none` with a reason when the movement cannot be followed
reliably from one phone camera with MediaPipe's 33 body landmarks.

Rules are ordered and the first match wins. They use the dataset's own fields (category, force, primary muscles) and
the exercise name, the only field that names the movement itself (as in the MET mapping). Every result carries the id of
the rule that produced it. Team rules, pending review; nothing here judges exercise quality or safety.
"""
import re

PATTERNS = {
    'squat', 'lunge', 'hinge', 'hipExtension', 'pushup', 'benchPress', 'dip', 'overheadPress', 'armRaise', 'row',
    'pulldown', 'curl', 'tricepsExtension', 'tricepsPushdown', 'legExtension', 'legCurl', 'sitUp', 'legRaise',
    'kneeLift', 'jumpingJack', 'plankHold', 'wallSitHold', 'none',
}

# Reasons for `none`; the user-facing texts are in movement_patterns.dart.
NONE_REASONS = {'stretch', 'machineCardio', 'locomotion', 'smallMovement', 'rotation', 'complex', 'alternating',
                'noTracker'}


def _has(name, *patterns):
    return any(re.search(p, name) for p in patterns)


def classify(rec):
    """Returns (pattern, reason or None, rule id)."""
    name = rec['name'].lower()
    cat = rec.get('category')
    primary = set(rec.get('primaryMuscles') or [])
    force = rec.get('force')

    def none(reason, rule):
        return ('none', reason, rule)

    # --- not followable ------------------------------------------------------------------------------------------
    if cat == 'stretching' or _has(name, r'\bsmr\b', 'stretch'):
        return none('stretch', 'stretch')
    if cat in ('powerlifting', 'olympic weightlifting', 'strongman'):
        return none('complex', 'lifting-sport')
    if cat == 'cardio':
        if _has(name, 'bicycl', 'bike', 'treadmill', 'elliptical', 'stair', 'step mill', 'rowing', 'recumbent', 'skating',
                'trail', 'running', 'jogging', 'walking'):
            return none('machineCardio', 'cardio-machine-or-travel')
        return none('complex', 'cardio-other')
    if _has(name, 'walk', 'carry', 'crawl', 'carioca', r'\bsleds?\b', 'yoke', 'farmer', 'march', 'step-up', 'step up', 'stepup'):
        return none('locomotion', 'travel-or-step')
    if _has(name, 'burpee', 'clean', 'snatch', 'jerk', 'thruster', 'get-up', 'get up', 'turkish', 'man maker'):
        return none('complex', 'multi-phase')
    if cat == 'plyometrics' and not _has(name, 'squat', 'lunge', 'split', 'jack', 'push-up', 'pushup', 'high knee'):
        return none('complex', 'plyometric-other')
    if _has(name, 'wrist', 'finger', 'pinch', 'gripper', 'forearm') or primary <= {'forearms'}:
        return none('smallMovement', 'small-forearm')
    if _has(name, 'shrug') or primary <= {'traps'}:
        return none('smallMovement', 'small-shrug')
    if _has(name, 'calf', 'calves', 'heel raise', 'toe raise', 'tibialis') or primary <= {'calves'}:
        return none('smallMovement', 'small-calf')
    if _has(name, 'neck exercise', 'isometric neck', '^neck', 'neck press'):
        return none('smallMovement', 'small-neck')
    if _has(name, 'adduct', 'abduct', 'hip circle', 'clam', 'fire hydrant') or primary <= {'adductors'} or primary <= {'abductors'}:
        return none('smallMovement', 'small-hip-sideways')
    if _has(name, 'rotation', 'twist', 'russian', 'woodchop', 'wood chop', 'windmill', 'chop', 'halo', 'figure 8',
            'oblique', 'bicycle', 'cross-body crunch', 'cross body crunch', 'side bend', 'saxon', 'pallof', 'around the world'):
        return none('rotation', 'rotation')
    if _has(name, 'crunch'):
        # Lifting the shoulder blades is a small angle change; counting it from landmarks is unreliable.
        return none('smallMovement', 'crunch')
    if _has(name, 'fly', 'flye', 'crossover', 'pec deck', 'pullover', 'face pull', 'upright', 'rear delt', 'rear lateral',
            'reverse fly', 'scaption', r'\by raise', r'\bt raise', 'bent over .*(raise|lateral)', 'bent-over .*(raise|lateral)'):
        return none('smallMovement', 'shoulder-horizontal')
    if _has(name, 'straight-arm .*pull', 'straight arm .*pull'):
        return none('noTracker', 'straight-arm-pull')

    # --- static holds --------------------------------------------------------------------------------------------
    if _has(name, 'plank') and force in ('static', None):
        return ('plankHold', None, 'plank')
    if _has(name, 'wall sit'):
        return ('wallSitHold', None, 'wall-sit')

    # --- legs and hips -------------------------------------------------------------------------------------------
    if _has(name, 'lunge', 'split squat', 'split jump', 'bulgarian'):
        return ('lunge', None, 'lunge')
    if _has(name, 'leg press', 'squat'):
        return ('squat', None, 'squat')
    if _has(name, 'leg extension'):
        return ('legExtension', None, 'leg-extension')
    if _has(name, 'leg curl', 'hamstring curl', 'glute ham raise', 'glute-ham raise', 'nordic'):
        return ('legCurl', None, 'leg-curl')
    if _has(name, 'bridge', 'hip thrust', 'hip lift', 'butt lift', 'glute lift', 'hyperextension', 'back extension'):
        return ('hipExtension', None, 'hip-extension')
    if _has(name, 'deadlift', 'good morning', 'romanian', 'stiff-leg', 'stiff leg', 'pull through', 'pull-through'):
        return ('hinge', None, 'hinge')

    # --- upper body ----------------------------------------------------------------------------------------------
    if _has(name, 'push-up', 'pushup', 'push up'):
        return ('pushup', None, 'pushup')
    if _has(name, r'\bdips?\b'):
        return ('dip', None, 'dip')
    if _has(name, 'pushdown', 'push-down', 'pressdown', 'press-down', 'bent-over .*triceps', 'bent over .*triceps') or (
            _has(name, 'kickback') and ('triceps' in primary or _has(name, 'tricep'))):
        return ('tricepsPushdown', None, 'triceps-pushdown')
    if _has(name, 'triceps extension', 'tricep extension', 'skull', 'lying triceps', 'french press', 'overhead triceps',
            'triceps overhead extension'):
        return ('tricepsExtension', None, 'triceps-extension')
    if _has(name, 'lateral raise', 'side lateral', 'side raise', 'arm raise', 'deltoid raise', 'front .*raise',
            '(dumbbell|barbell|plate|cable) raise'):
        return ('armRaise', None, 'arm-raise')
    if _has(name, 'shoulder press', 'overhead press', 'military press', 'arnold', 'push press', 'seated press',
            'standing press', 'landmine press') or ('shoulders' in primary and force == 'push' and _has(name, 'press')):
        return ('overheadPress', None, 'overhead-press')
    if _has(name, 'bench press', 'chest press', 'dumbbell bench', 'floor press', 'board press', 'decline press',
            'incline press', 'smith machine press') or (('chest' in primary or 'triceps' in primary) and force == 'push'
                                                        and _has(name, 'press')):
        return ('benchPress', None, 'bench-press')
    if _has(name, 'pull-up', 'pullup', 'pull up', 'chin-up', 'chinup', 'chin up', 'pulldown', 'pull-down', 'pull down'):
        return ('pulldown', None, 'vertical-pull')
    if _has(name, r'\brows?\b'):
        return ('row', None, 'row')
    if (_has(name, 'curl') and 'biceps' in primary) or _has(name, 'hammer curl', 'preacher', 'zottman'):
        return ('curl', None, 'biceps-curl')

    # --- core ----------------------------------------------------------------------------------------------------
    if _has(name, 'sit-up', 'situp', 'sit up', 'jackknife', 'jack-knife'):
        return ('sitUp', None, 'sit-up')
    if _has(name, 'leg raise', 'knee raise', 'leg lift', 'hanging leg'):
        return ('legRaise', None, 'leg-raise')

    # --- whole-body rhythm ---------------------------------------------------------------------------------------
    if _has(name, 'jumping jack', 'star jump'):
        return ('jumpingJack', None, 'jumping-jack')
    if _has(name, 'high knee'):
        return ('kneeLift', None, 'knee-lift')

    return none('noTracker', 'no-tracker')
