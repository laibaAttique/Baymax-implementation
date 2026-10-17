#!/usr/bin/env python3
"""Builds Chapter 4 (Implementation) of the Baymax report in the structure of the faculty template.
Every algorithm, constant and metric below was read from the project's code or its training output (see the file named in each row).
Standard library only; the styles come from the template file."""
import os, struct, zipfile
from xml.sax.saxutils import escape

HOME = os.path.expanduser('~')
OUT = os.path.join(HOME, 'Downloads', 'Baymax_Implementation_Chapter')
TEMPLATE = os.path.join(HOME, 'Downloads', 'Final Report Template_FA_26(BSSE Program).docx')
APP = os.path.join(HOME, 'Downloads', 'baymaxxxx 2', 'untitled folder', 'app')
RES = os.path.join(APP, 'ml', 'food_classifier', 'results_2026-10-12')


def esc(t):
    return escape(str(t))


def run(t, b=False, i=False, sz=None, mono=False, color=None):
    pr = ''
    if mono:
        pr += '<w:rFonts w:ascii="Courier New" w:hAnsi="Courier New" w:cs="Courier New"/>'
    if b:
        pr += '<w:b/><w:bCs/>'
    if i:
        pr += '<w:i/><w:iCs/>'
    if color:
        pr += '<w:color w:val="%s"/>' % color
    if sz:
        pr += '<w:sz w:val="%d"/><w:szCs w:val="%d"/>' % (sz, sz)
    return '<w:r>%s<w:t xml:space="preserve">%s</w:t></w:r>' % ('<w:rPr>%s</w:rPr>' % pr if pr else '', esc(t))


def para(content, style=None, jc=None, nonum=False, keep=False, after=None, line=None, ind=None):
    if isinstance(content, str) and not content.startswith('<w:r'):
        content = run(content)
    ppr = ''
    if style:
        ppr += '<w:pStyle w:val="%s"/>' % style
    if keep:
        ppr += '<w:keepNext/>'
    if nonum:
        ppr += '<w:numPr><w:ilvl w:val="0"/><w:numId w:val="0"/></w:numPr>'
    if after is not None or line:
        ppr += '<w:spacing%s%s/>' % (' w:after="%d"' % after if after is not None else '', ' w:line="%d" w:lineRule="auto"' % line if line else '')
    if ind:
        ppr += '<w:ind w:left="%d"/>' % ind
    if jc:
        ppr += '<w:jc w:val="%s"/>' % jc
    return '<w:p>%s%s</w:p>' % ('<w:pPr>%s</w:pPr>' % ppr if ppr else '', content)


body = []
H1 = lambda t: body.append(para(t, 'Heading1', nonum=True))
H2 = lambda t: body.append(para(t, 'Heading2', nonum=True))
H3 = lambda t: body.append(para(t, 'Heading3', nonum=True))
P = lambda t: body.append(para(t, jc='both', line=300, after=100))
B = lambda t: body.append(para(run('•  ' + t), jc='left', line=290, after=40, ind=360))
CAP = lambda t: body.append(para(t, 'Caption', keep=True))
fig_no = [0]


def cell(content, w, b=False, fill=None, sz=18, mono=False):
    items = content if isinstance(content, (list, tuple)) else [content]
    ps = ''
    for it in items:
        if isinstance(it, tuple):  # (text, bold)
            ps += para(run(it[0], b=it[1], sz=sz, mono=mono), after=20)
        else:
            ps += para(run(it, b=b, sz=sz, mono=mono), after=20)
    return '<w:tc><w:tcPr><w:tcW w:w="%d" w:type="dxa"/>%s</w:tcPr>%s</w:tc>' % (w, '<w:shd w:val="clear" w:color="auto" w:fill="%s"/>' % fill if fill else '', ps)


def table(headers, rows, widths, sz=18, mono_col=None):
    x = '<w:tbl><w:tblPr><w:tblStyle w:val="TableGrid"/><w:tblW w:w="%d" w:type="dxa"/><w:tblLayout w:type="fixed"/><w:tblCellMar><w:left w:w="70" w:type="dxa"/><w:right w:w="70" w:type="dxa"/></w:tblCellMar></w:tblPr>' % sum(widths)
    x += '<w:tblGrid>%s</w:tblGrid>' % ''.join('<w:gridCol w:w="%d"/>' % w for w in widths)
    if headers:
        x += '<w:tr><w:trPr><w:tblHeader/></w:trPr>%s</w:tr>' % ''.join(cell(h, w, b=True, fill='D9E2F3', sz=sz) for h, w in zip(headers, widths))
    for r in rows:
        x += '<w:tr>%s</w:tr>' % ''.join(cell(c, w, sz=sz, mono=(mono_col == i)) for i, (c, w) in enumerate(zip(r, widths)))
    body.append(x + '</w:tbl>' + para('', after=80))


def png_size(path):
    with open(path, 'rb') as f:
        d = f.read(24)
    return struct.unpack('>II', d[16:24])


IMAGES = []


def figure(path, caption, width_in=6.2):
    w, h = png_size(path)
    cx = int(width_in * 914400)
    cy = int(cx * h / w)
    rid = 'rIdImg%d' % (len(IMAGES) + 1)
    IMAGES.append((rid, path))
    n = len(IMAGES)
    body.append('<w:p><w:pPr><w:keepNext/><w:jc w:val="center"/></w:pPr><w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0"><wp:extent cx="%d" cy="%d"/><wp:docPr id="%d" name="Figure %d"/>'
                '<wp:cNvGraphicFramePr><a:graphicFrameLocks xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" noChangeAspect="1"/></wp:cNvGraphicFramePr>'
                '<a:graphic xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">'
                '<pic:pic xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:nvPicPr><pic:cNvPr id="0" name="f%d"/><pic:cNvPicPr/></pic:nvPicPr>'
                '<pic:blipFill><a:blip r:embed="%s"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill><pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="%d" cy="%d"/></a:xfrm>'
                '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>' % (cx, cy, n, n, n, rid, cx, cy))
    CAP(caption)


# =================================================================================================================================
H1('Chapter 4: Implementation')
P('This chapter documents how Baymax was implemented: the mobile app (Flutter), the Firebase back end, the Express API and the two web applications (specialist portal and administrator panel). '
  'Module numbers are those of the merged report. The techniques from AI/ML, data science and cyber security that were used are named in Section 4.1.2, with their dataset, training procedure and measured results in Section 4.2 and the security techniques in Section 4.3.')

# ---------------------------------------------------------------------------------------------------------------------------------
H2('4.1 Project Methodology & Algorithms')
H3('4.1.1 Project Methodology (Step-by-Step Approach)')
P('Implementation followed the pipeline below. Each stage states what was done, how and why.')

body.append(para(run('Data Collection', b=True), keep=True, after=40))
B('What: (1) the user\'s own health profile and daily logs (weight, food, workouts, mood) entered in the app; (2) a public health-survey dataset to learn a risk estimate; (3) food and exercise catalogues; (4) food photographs for an image classifier; (5) appointment, payment and plan records created by members and specialists.')
B('How: CDC Diabetes Health Indicators (UCI dataset 891, BRFSS survey, 253,680 adults); food lists from the team\'s own lists, the Indian Nutrient Databank and USDA FoodData Central SR Legacy (97 curated foods plus 2,760 listed foods); 73 exercises curated with energy values from the 2024 Compendium of Physical Activities; Food-101 (subset) and two Kaggle Pakistani-dish datasets for photos. User data is stored in Firebase Realtime Database; catalogues in Cloud Firestore with a bundled JSON fallback.')
B('Why: personalised plans need the user\'s own measurements; a risk estimate needs population data; calorie and energy figures must come from published sources, not guesses.')

body.append(para(run('Data Preprocessing', b=True), keep=True, after=40))
B('Missing values / implausible values: survey rows with BMI outside 12-70 were dropped (253,096 of 253,680 rows used). Rows of the gym dataset whose average heart rate exceeded the maximum were removed (973 to 950 rows); nothing is imputed.')
B('Labels: survey answers were converted to the app\'s six classes with the same priority as the rule engine: heart disease or attack, then diabetes, then high blood pressure or cholesterol, then BMI band (30 or more, 25 or more, otherwise Healthy). Age bands 1-13 were replaced by the middle of each 5-year band.')
B('Duplicates: food images were opened and checked (corrupt, too small, extreme shape) and exact and near-duplicate photos were removed; the authors\' official Food-101 test images were kept as the validation set so no training image leaks into it.')
B('Normalisation: the six model features were standardised with the training mean and standard deviation (z-score); the mean and scale are stored with the model so the phone applies the same transform. Food text is lower-cased, stripped of punctuation and singularised; label text from OCR has digit/letter confusions repaired (for example mi1k to milk).')

body.append(para(run('Feature Extraction & Selection', b=True), keep=True, after=40))
B('Risk model features: BMI, age, sex (0/1), active (0/1), BMI squared and age squared. These are the four inputs the report names plus two squared terms so the model can learn the curved relation between age or BMI and disease.')
B('Plan generation features: BMI, age, activity level, goal, workouts per week, reported conditions and allergies. Joint-load and capacity scores are derived from them (Algorithm 4).')
B('Text features: quantity words, units, size words and food-name tokens extracted from typed meals; ingredient tokens and allergen synonym lists for labels.')

body.append(para(run('Model Training', b=True), keep=True, after=40))
B('Algorithms: multinomial Logistic Regression for health risk (scikit-learn, lbfgs, balanced class weights); EfficientNetV2-B0 transfer learning for food photos (TensorFlow, exported to float16 TFLite); a Gradient Boosting calorie model was built and tested but is deliberately not shipped (Section 4.2); Lloyd\'s K-Means with k-means++ seeding for grouping users; least-squares regression for weight trend.')
B('Training: Logistic Regression used an 80/20 stratified split (random_state 42); the food model used 8,472 training and 2,317 test images. Evaluation: accuracy, macro-F1, ROC-AUC, precision and recall at the chosen flag thresholds (risk model); top-1, top-3 and per-class precision/recall/F1 (food model).')
B('Why: Logistic Regression is small enough to run on the phone as about 40 multiplications and its output can be explained; transfer learning gives usable image accuracy from a few thousand photos; a model is only released if it passes accuracy and physiology checks.')

body.append(para(run('Advanced Techniques', b=True), keep=True, after=40))
B('NLP (rule-based): typed meals such as "2 rotis and a bowl of daal" are split, tokenised and matched to foods with quantities (Algorithm 7); chatbot intent detection by weighted keyword and phrase matching with typo tolerance (Algorithm 10); allergen matching with synonym lists and Levenshtein distance (Algorithm 8).')
B('Computer vision: a convolutional network classifies a food photo among 22 foods; it is experimental and not used in release builds because two classes failed their per-class check.')
B('Security: Firebase token verification, role-based access control, database security rules, time-boxed and logged access to patient data (Section 4.3).')

body.append(para(run('Deployment', b=True), keep=True, after=40))
B('What: an Android/iOS app built with Flutter, an Express API, and two Next.js web applications, all on one Firebase project. How and why: see Section 4.6.')

H3('Implementation of each module')
CAP('Table 4.0 Implementation summary by module (merged numbering)')
table(['Module', 'Where', 'How it is implemented', 'Main algorithm(s)'], [
    ['1 User Authentication & Onboarding', 'App', 'Firebase Authentication (email/password, Google). Three-step health profile form with field validation; password rules; login lock; per-user profile in Realtime Database.', 'Input validation rules; LoginGuard (5 failures, 15 minutes)'],
    ['2 AI Health Classification', 'App', 'HealthCalc for BMI/BMR; rule engine plus an on-device Logistic Regression read from health_classifier.json; result screen with risk factors.', 'Algorithms 1 and 2'],
    ['3 Home Dashboard', 'App', 'HomeDashboard screen reading the plan, activity, food and notification services; mood selector; Quick Access; floating chat button; bottom navigation.', 'Time-of-day greeting rule; MET-based calorie estimate for the workout card'],
    ['4 Workout & Exercise', 'App', 'PlanGenerator with medical restriction rules and ExerciseSelector ranking over the 73-exercise library; AdaptiveCalorieOptimizer for the calorie target.', 'Algorithms 3, 4 and 6'],
    ['8 Smart Diet & Calorie Tracking', 'App', 'FoodParser and FoodDatabase search over 2,857 foods; daily summary; water tracker; experimental TFLite photo scan.', 'Algorithms 7 and 16'],
    ['9 Nutrition Plan', 'App', 'PlanGenerator nutrition part: calorie target, macros, allergen-safe meals by slot, foods to avoid, rotating tips.', 'Algorithms 1 and 5'],
    ['10 Allergy & Ingredient Scanner', 'App (+ OCR backend)', 'Label photo to text by Google Vision through the Node backend; AllergenMatcher compares ingredients with the user\'s allergies.', 'Algorithm 8'],
    ['12 Community Ranking & Gamification', 'App', 'Weekly score, levels, badges, XP, streaks; opt-in leaderboard in Realtime Database.', 'Algorithm 9 (weighted score + K-Means)'],
    ['13 AI Chatbot', 'App', 'On-device ChatbotEngine answering from the user\'s own logs through chat_history; no cloud service.', 'Algorithm 10'],
    ['14 Online Consultation', 'App + Specialist portal + Admin panel + Express API', 'Specialist list, booking with a 10-minute slot hold, request/accept/decline, server-made video room, notes, prescriptions, plans, food-log review, registration with administrator approval, account closing.', 'Algorithms 11, 12 and 17'],
    ['16 Secure Data & Smart Alerts', 'App + API', 'Role-based access, reminders, inactivity detection, notification inbox, allergen and badge notifications.', 'Algorithm 13; role checks (Section 4.3)'],
    ['17 Analytics & Progress', 'App', 'Charts of calories against target, weekly score and weight; 3-day moving average.', 'Moving average; Algorithm 14'],
], [1700, 1100, 4300, 2260], sz=17)
P('Modules 11 (Predictive Body Transformation) and 15 (Payment) are also built (a straight-line weight projection and a test payment gateway) but are outside the module list of this chapter\'s test cases.')

# ---------------------------------------------------------------------------------------------------------------------------------
H3('4.1.2 Algorithm')
P('Each algorithm is documented with its name, input, output and pseudocode, following the template (Table 4.1). Algorithms 2, 4 and 6 are the intelligent core (classification, plan optimisation and adaptive prediction); the others enforce business rules, scheduling or security rules. Pseudocode is written in the template\'s style; source files are named in the last line of each entry.')
CAP('Table 4.1 Algorithms used in Baymax')

ALG = []


def alg(name, inp, out, lines, src):
    d = [('Input: ' + inp, False), ('Output: ' + out, False), ('Pseudocode:', True)] + [(l, False) for l in lines] + [('Source: ' + src, False)]
    ALG.append([[(name, True)], d])


alg('1. CalorieTarget (Business Rule)',
    'weight (kg), height (cm), age, gender, activity level, goal',
    'BMI, WHO category, BMR, TDEE, daily calorie target, macro targets, safety note',
    ['1: procedure CalorieTarget(profile)',
     '2:   BMI <- weight / (height/100)^2',
     '3:   base <- 10*weight + 6.25*height - 5*age',
     '4:   BMR <- base + 5 (male) | base - 161 (female) | base - 78 (other)    {Mifflin-St Jeor}',
     '5:   TDEE <- BMR * factor[activity]    {1.2, 1.375, 1.55, 1.725, 1.9}',
     '6:   floor <- max(BMR, 1500 if male else 1200);  deficit <- TDEE - 500',
     '7:   if BMI < 18.5 then deficit <- TDEE (no deficit)   else if deficit < floor then deficit <- floor',
     '8:   target <- deficit (Lose Weight) | TDEE + 300 (Gain Muscle) | TDEE (otherwise)',
     '9:   protein <- weight * {1.6 | 1.8 | 1.2}, at most 35% of kcal;  fat <- 27% of kcal / 9;  carbs <- remaining kcal / 4',
     '10:  if diabetic then carbs <- min(carbs, 40% of kcal / 4)',
     '11:  water <- 35 ml/kg rounded to 0.5 L, within 1.5-4.0 L;  return target, macros',
     '12: end procedure'], 'utils/health_calc.dart')

alg('2. HybridHealthClassification (AI/Data Science)',
    'BMI, age, gender, activity, reported conditions; trained model (mean, scale, coef, intercept, priors, thresholds)',
    'Category (Healthy, Overweight, Obese, At-Risk, Cardiac, Diabetic), risk level, risk factors, model risk percentages',
    ['1: procedure Classify(P)',
     '2:   if P has heart disease then category <- Cardiac (High)',
     '3:   else if P has diabetes then category <- Diabetic (High)',
     '4:   else if hypertension or asthma or PCOS or BMI < 18.5 or (obesity listed and BMI < 30) or (age >= 60 and sedentary) then category <- At-Risk',
     '5:   else if BMI >= 30 then Obese else if BMI >= 25 then Overweight else Healthy',
     '6:   x <- [BMI, age, sexMale, active, BMI^2, age^2];  z <- (x - mean) / scale',
     '7:   logit_c <- intercept_c + coef_c . z;  p <- softmax(logit)            {multinomial Logistic Regression}',
     '8:   q_c <- p_c * prior_c;  q <- q / sum(q)                                {undo class balancing: calibrated risk}',
     '9:   if category in {Healthy, Overweight, Obese} and (q_Diabetic >= 0.20 or q_Cardiac >= 0.18) then category <- At-Risk',
     '10:  return category, risk level, risk factors, q_Diabetic, q_Cardiac       {model never assigns Cardiac or Diabetic}',
     '11: end procedure'], 'services/health_classifier.dart, services/ml/health_risk_model.dart, ml/health_classifier/train.py')

alg('3. MedicalRestrictionRules (Business Rule)',
    'classification, reported conditions, BMI, age, activity level',
    'Allowed exercise set and limits (intensity, days, session length, hold time)',
    ['1: procedure Restrictions(P, class)',
     '2:   level <- 0 if class in {Cardiac, At-Risk, Obese} else 1;  if sedentary then level--;',
     '3:   if very active or athlete, and class in {Healthy, Overweight} then level++;  intensity <- {Low, Moderate, High}[clamp(level)]',
     '4:   noHighImpact <- obese or cardiac or hypertension or age >= 55',
     '5:   noHIIT <- cardiac or hypertension or diabetic or asthma or age >= 55 or BMI >= 35 or intensity = Low',
     '6:   noIsometric <- cardiac;  maxHold <- 20 s if hypertension;  noPlyo <- noHighImpact or BMI >= 25',
     '7:   addBalance <- age >= 65;  strengthFocus <- BMI < 18.5',
     '8:   maxDays <- 4 if cardiac or age >= 60, 5 if obese/hypertension/diabetic, else 6',
     '9:   maxSession <- 30 min if cardiac else {35, 45, 55}[intensity]',
     '10:  allowed(e) <- e.level <= maxLevel and not (noHighImpact and e.impact = high) and not (noHIIT and e is HIIT) and ...',
     '11: end procedure'], 'services/plan_generator.dart (_intensity, _restrictions)')

alg('4. WeeklyWorkoutPlanGeneration (Optimization / Scheduling)',
    'profile, classification, plan variant',
    'Weekly schedule: for each workout day a warm-up, ranked exercises with sets/reps/time, stretches, cool-down, and the reason for each pick',
    ['1: procedure GeneratePlan(P, class, variant)',
     '2:   R <- Restrictions(P, class);  days <- schedule[min(workoutsPerWeek, R.maxDays)]   {for example 4 days: Mon, Tue, Thu, Sat}',
     '3:   capacity <- {1.0 ... 3.0} by activity, minus 0.5 if age >= 65 (0.25 if >= 50), minus 0.5 if BMI >= 35 (0.25 if >= 30)',
     '4:   for each workout day do: template <- template of the goal;  for each slot (muscle group, count) in template do',
     '5:     pool <- exercises of the group allowed by R and not yet used today',
     '6:     for each e in pool: s <- -2.0*(e.level - capacity) if too hard else -0.8*(capacity - e.level)',
     '7:       s <- s + 0.12*MET (Lose Weight) | +0.5 for push/legs/back (Gain Muscle) | +0.2..0.3 compound lifts',
     '8:       s <- s - jointLoad(e, BMI, age) - 0.6 if floor exercise and (age >= 65 or BMI >= 35) - 0.4*(complexity-1) if age >= 60',
     '9:       s <- s - 0.9 * (times e was used this week) + tieBreak(e, variant)',
     '10:    take the top count by s;  update weekUsage',
     '11:  add warm-up, up to 2 stretches for the muscle regions worked, and cool-down',
     '12:  while main exercises > 3 and duration > R.maxSession do remove the last main exercise',
     '13: return schedule',
     '14: end procedure'], 'services/plan_generator.dart, services/exercise_selector.dart')

alg('5. NutritionPlanGeneration (Business Rule)',
    'profile, classification, calorie target, variant',
    'Meals by slot with serving sizes, macro targets, foods to avoid, tips',
    ['1: procedure NutritionPlan(P, class, variant)',
     '2:   kcal <- optimizer(CalorieTarget(P));  macros <- Macros(kcal, P)',
     '3:   avoid <- {sugary};  if losing or cardiac or hypertension then add {fried, processed}',
     '4:   if diabetic then add {highSugar, refined};  if cardiac or hypertension then add {highSodium}',
     '5:   budget <- {Breakfast 25%, Lunch 35%, Dinner 30%, Snack 10%} of kcal',
     '6:   for each meal, for each role (e.g. main, carb, veg) do',
     '7:     pool <- foods with that role and meal, with no allergen in P.allergies and no avoid tag',
     '8:     pick <- pool[(variant + role + meal seed) mod |pool|]',
     '9:   factor <- (budget - fixed kcal) / scalable kcal;  serving <- round factor to 0.5, within 0.5-2.5',
     '10: return meals     {allergen foods can never enter the pool}',
     '11: end procedure'], 'services/plan_generator.dart (_nutrition, _buildMeal)')

alg('6. AdaptiveCalorieEstimation (AI/Data Science: least-squares regression + Bayesian update)',
    'formula TDEE, BMR, weigh-ins and daily calorie logs of the last 28 days',
    'Adjusted maintenance calories, data share, explanation',
    ['1: procedure EstimateMaintenance(prior, BMR, weights, intake)',
     '2:   if fewer than 4 weigh-ins, or they span < 14 days, or < 10 days with intake >= 0.6*BMR then return prior',
     '3:   slope, SE <- least-squares line through (day, kg)',
     '4:   observed <- mean(intake) - slope * 7700                 {energy balance, 7700 kcal per kg}',
     '5:   if |observed/prior - 1| > 0.30 then return prior         {logs not trusted: probably unlogged meals}',
     '6:   sigmaPrior <- 0.10*prior;  sigmaObs <- sqrt((SE*7700)^2 + (0.10*mean(intake))^2)',
     '7:   share <- min(0.7, sigmaPrior^2 / (sigmaPrior^2 + sigmaObs^2))        {normal-normal update}',
     '8:   tdee <- prior + share*(observed - prior);  clamp tdee to [0.90*prior, 1.15*prior]',
     '9:   if |tdee - prior| < 100 kcal then return prior (unchanged)',
     '10:  return tdee',
     '11: end procedure'], 'services/calorie_optimizer.dart (replaces the Gradient Boosting named in the report: see Section 4.2)')

alg('7. FoodTextParsingAndSearch (NLP, rule-based + Levenshtein)',
    'text such as "2 rotis and a bowl of daal, 150g chicken breast"; food catalogue',
    'List of (food, servings, kcal, macros); unknown parts reported',
    ['1: procedure Parse(text)',
     '2:   split text on , ; and plus & + then also;  normalise (lower-case, no punctuation, "150g" -> "150 g")',
     '3:   for each phrase: read number or number word or fraction, unit (g, ml, kg, cup, bowl ...), size (small 0.75, large 1.3 ...)',
     '4:   food <- Search(remaining words);  servings <- quantity converted by the food\'s serving weight',
     '5:   if no food found then mark the part unknown (never guessed)',
     '6: procedure Search(q): for each food key: score <- 1.0 exact | 0.9 starts with | 0.8 contains |',
     '7:     0.5 + 0.3*(matched tokens / query tokens) where a token matches if equal or within the edit budget',
     '8:   edit budget by word length: <= 5 letters 0, 6-8 letters 1, longer 2 (Levenshtein distance)',
     '9:   return foods with score >= 0.45, best first, at most 8'], 'services/food_parser.dart, services/food_database.dart, utils/fuzzy.dart')

alg('8. AllergenMatching (Business Rule / NLP)',
    'OCR or pasted ingredient text, the user\'s allergy list',
    'Per-ingredient safe/unsafe flags, allergens found, trace-risk allergens, overall verdict',
    ['1: procedure Analyze(text, allergies)',
     '2:   split text at "may contain / traces of / made in a facility" into body and trace parts; drop text before "Ingredients:"',
     '3:   phrases <- body split on , ; ( ) and bullets',
     '4:   for each phrase, for each allergy: tokens <- deOCR(normalise(phrase));  remove look-alike phrases (e.g. coconut milk, cocoa butter)',
     '5:     if any synonym of the allergy is a whole word or phrase (optional plural) then exact hit',
     '6:     else if a token of >= 4 letters is within the edit budget of a one-word synonym then possible hit (fuzzy)',
     '7:   the same check on the trace part gives trace-risk allergens',
     '8:   verdict <- not safe if any hit or any trace hit;  safe otherwise',
     '9: end procedure'], 'services/allergen_matcher.dart, utils/fuzzy.dart')

alg('9. FitnessScoreAndGrouping (AI/Data Science: weighted score + K-Means clustering)',
    'for each day of the week: planned, workout done, food logged, kcal, target; weekly data of all users',
    'Weekly score 0-100, level, K-Means group',
    ['1: procedure WeeklyScore(days)',
     '2:   training <- min(1, done / planned);  logging <- days logged / days elapsed;  adherence <- days within +-15% of target / days logged',
     '3:   score <- 100 * (50*training + 25*logging + 25*adherence) / (sum of the weights that apply)',
     '4:   level <- Advanced if average >= 70, Intermediate if >= 40, else Beginner',
     '5: procedure GroupCohort(users)',
     '6:   if |users| < 15 then use the thresholds above',
     '7:   points <- [score/100, workouts/7, logDays/7];  centroids <- k-means++ seeding (k = 3, seed 7)',
     '8:   repeat (Lloyd): assign each point to the nearest centroid; recompute centroids;  until no change or 100 iterations',
     '9:   rank the three clusters by centroid score: Beginner < Intermediate < Advanced'], 'services/gamification.dart')

alg('10. ChatbotIntentDetection (NLP, rule-based)',
    'user message, the user\'s profile, plan and logs',
    'Reply text, detected intent, suggested actions',
    ['1: procedure Respond(message, context)',
     '2:   if the message describes an emergency then return the emergency reply (checked first)',
     '3:   if it describes a symptom or pain then return advice and a "Book a consultation" action',
     '4:   norm <- normalise(message);  for each intent: score <- sum over its keywords of',
     '5:     +2 for a multi-word phrase present, +1 for a single word present, +0.8 for a fuzzy match (word >= 6 letters)',
     '6:   best <- intent with the highest score (ties: the longest matched phrase);  accept only if score >= 1',
     '7:   definitional questions ("what is ...", "how is ... calculated") are answered from the FAQ',
     '8:   build the answer from the user\'s own data (food log, workouts, weigh-ins); if a log is unavailable say "I can\'t read your ..."',
     '9:   otherwise return the fallback reply'], 'services/chatbot_engine.dart')

alg('11. AppointmentScheduling (Scheduling / Business Rule)',
    'specialist availability (working days, start, end, slot length, time-zone offset), booked slots, now, member\'s chosen slot, note',
    'Open slots, or the reason a booking cannot go ahead; a held booking',
    ['1: procedure OpenSlots(S, day, now, booked)',
     '2:   if S is not taking bookings then return empty;  if day not in S.workingDays then return empty',
     '3:   for m <- S.start to S.end - S.slotLength step S.slotLength do slot <- day + m - S.tzOffset (as UTC)',
     '4:   keep slot if slot >= now + 15 min and slot not in booked',
     '5: procedure Book(S, slot, note)',
     '6:   check in order: taking bookings, slot chosen, slot free, >= 15 min ahead, inside working hours, note <= 500 characters',
     '7:   create slots/{S}/{slotStartMs}; success only if the key does not already exist   {database enforces one booking per time}',
     '8:   appointment <- pending_payment with a hold of 10 minutes;  after payment status <- requested',
     '9:   a hold older than 10 minutes can be taken over by someone else'], 'services/consultation_rules.dart, services/consultation_service.dart, database.rules.json')

alg('12. RequestAcceptance and VideoRoomCreation (Business Rule, server side)',
    'appointment id, specialist\'s ID token',
    'Confirmed appointment with a video link, or a refusal',
    ['1: procedure Accept(id, token)',
     '2:   uid <- verify(token);  role <- roles[uid];  refuse (403) unless role is a specialist with a matching profile',
     '3:   appointment <- appointments[id];  refuse (404) unless appointment.specialistId = uid',
     '4:   if status != requested then refuse;  if now >= startAt then refuse "expired"',
     '5:   room <- MEETING_BASE_URL + "/baymax-" + 20 random lower-case letters/digits   {unguessable; chat bookings start muted}',
     '6:   write status <- confirmed, meetingLink <- room, respondedAt <- now;  keep the slot',
     '7:   write a notification for the patient;  return the appointment'], 'baymax-api/src/routes/specialist.js, src/lib/rules.js')

alg('13. InactivityDetection (Business Rule)',
    'today, last workout date, planned weekdays',
    'Inactivity record (days since workout, missed planned days) or none',
    ['1: procedure DetectInactivity(today, lastWorkout, plannedWeekdays)',
     '2:   if lastWorkout is unknown then return none',
     '3:   days <- today - lastWorkout;  if days < 3 then return none',
     '4:   missed <- number of planned weekdays between lastWorkout and today (not counting today) without a workout',
     '5:   if missed >= 1 then return (days, missed) else return none     {rest days alone never count}'], 'services/gamification.dart')

alg('14. WeightTrendProjection (Data Science: simple linear regression)',
    'weigh-ins of the last 28 days, optional target weight',
    'Current fitted weight, kg per week, weight in 30 days, weeks to target',
    ['1: procedure Project(weights, target)',
     '2:   require >= 4 weigh-ins spanning >= 14 days, else return "not reliable" with the reason',
     '3:   fit least-squares line kg = a + b*day;  perWeek <- 7*b;  in30 <- fit(last) + 30*b',
     '4:   if target given and |perWeek| > 0.05 and the trend leads toward the target then weeks <- (target - fit(last)) / perWeek',
     '5:   return the results      {a straight-line extrapolation, not a forecasting model}'], 'services/weight_projection.dart, services/calorie_optimizer.dart (fitWeights)')

alg('15. CardNumberCheck (Business Rule, Luhn)',
    'card number digits (test gateway)',
    'valid / invalid, brand',
    ['1: procedure Luhn(digits)',
     '2:   sum <- 0;  for i <- last digit down to first do',
     '3:     n <- digit;  if i is every second digit from the right then n <- 2n, and if n > 9 then n <- n - 9',
     '4:     sum <- sum + n',
     '5:   return digits not empty and sum mod 10 = 0;   brand <- Visa if starts with 4, Mastercard if 51-55 or 2221-2720'], 'services/payment_rules.dart')

alg('16. FoodImageClassification (AI/Deep Learning, experimental)',
    'photo of a meal (256 x 256 RGB)',
    'Top-3 foods with confidence; accepted only above the minimum confidence',
    ['1: procedure ClassifyFood(image)',
     '2:   resize to 256 x 256;  run the EfficientNetV2-B0 TFLite model (preprocessing inside the model)',
     '3:   probabilities over 22 foods;  take the top 3',
     '4:   if top1 < minimum confidence (0.30-0.35) then return "not sure"',
     '5:   look the food up in the catalogue and offer it for logging; the user confirms the quantity'], 'services/food_image_classifier.dart, ml/food_classifier/ (not used in release builds: see Section 4.2)')

alg('17. SharedDataAccessControl (Business Rule / Security)',
    'appointment, what the patient ticked to share, now, specialist\'s token',
    'The shared data, or a reason it is locked; an access-log entry',
    ['1: procedure SharedData(appointment, now, uid)',
     '2:   refuse unless appointment.specialistId = uid (answers 404 so other people\'s bookings look absent)',
     '3:   if status not in {confirmed, completed, no_show} then locked ("accept the request first")',
     '4:   if now < start - 30 min then locked "too early";  if now > end + 60 min then locked "ended"',
     '5:   for each item the patient ticked (health summary, 7-day food log, 30-day activity) read only that item',
     '6:   append accessLog/{appointment}: who, when, which items;  return the data'], 'baymax-api/src/lib/rules.js, src/routes/specialist.js')

table(['Algorithm Name', 'Details'], ALG, [2300, 7060], sz=16)
P('Moving average (Module 17): for each day, the average of the logged values in the window of that day and the two before it; days with nothing logged are ignored, and a window with no logged day gives no value (analytics_screen.dart).')

# ---------------------------------------------------------------------------------------------------------------------------------
H2('4.2 Training Results & Model Evaluation')
H3('Model 1: Logistic Regression health-risk classifier (Module 2): released')
CAP('Table 4.2 Logistic Regression: dataset, setup and results')
table(None, [
    [[('Algorithm', True)], 'Multinomial Logistic Regression (scikit-learn, lbfgs, C = 1.0, balanced class weights, up to 2,000 iterations). Exported as health_classifier.json (and a 2.6 KB TFLite file) and evaluated in plain Dart on the phone.'],
    [[('Dataset', True)], 'CDC Diabetes Health Indicators, UCI dataset 891 (BRFSS telephone survey, US adults, self-reported). 253,680 rows; 253,096 used after dropping implausible BMI. Size 13.5 MB, CSV. Licence: see the UCI page. The survey year is stated as 2014 by UCI and 2015 by the Kaggle copy, so it is not asserted.'],
    [[('Preprocessing', True)], 'BMI 12-70 kept; age bands replaced by band mid-points; labels derived from survey answers (heart disease, diabetes, high blood pressure or cholesterol, BMI band); features BMI, age, sex, active, BMI squared, age squared; standardised with the training mean and scale.'],
    [[('Training setup', True)], '80% train / 20% test (50,620 test rows), stratified, random_state 42; CPU, Python 3.9, scikit-learn. Training prior of each class stored to calibrate probabilities.'],
    [[('Metrics (test set)', True)], ['6-class accuracy 40.4%; macro-F1 0.40 (weak, and expected: four demographic inputs cannot separate the At-Risk group).',
                                     'ROC-AUC (calibrated probability, class vs rest): Cardiac 0.759; Diabetic 0.733.',
                                     'Risk flags (thresholds chosen so about 15% of people are flagged and precision is at least twice the base rate): Cardiac threshold 0.18, base rate 9.4%, precision 24.9%, recall 39.3%, 14.9% flagged. Diabetic threshold 0.20, base rate 10.8%, precision 26.9%, recall 36.1%, 14.6% flagged.']],
    [[('Use in the app', True)], 'Rules decide first; the model only adds a statistical risk estimate and, if nothing was reported and the risk is above the threshold, moves the person to At-Risk. It never assigns Cardiac or Diabetic. Exported weights were verified against scikit-learn (maximum difference 1.4e-6) and unit-tested.'],
    [[('Limitations', True)], 'US survey data; not validated for South Asian populations (who tend to develop diabetes at lower BMI); screening estimate, not a diagnosis. The app says so on screen.'],
], [1900, 7460], sz=17)

H3('Model 2: EfficientNetV2-B0 food classifier (Module 8): experimental, not released')
CAP('Table 4.3 Food image classifier: dataset, setup and results')
table(None, [
    [[('Algorithm', True)], 'Convolutional neural network by transfer learning: EfficientNetV2-B0 pre-trained on ImageNet, fine-tuned; input 256 x 256 RGB; exported as float16 TFLite (about 4.5 MB). Version 20261012.'],
    [[('Dataset', True)], 'Cleaned subset of Food-101 (101 dishes x 1,000 photos, 4.65 GB, official train/test split) plus two Kaggle Pakistani-dish datasets; 22 foods in the final labels. Cleaning: corrupt and tiny images removed, exact and near-duplicates removed, label-noise review (0 images removed in the final run). 8,472 training images, 2,317 test images; longest side 384 px.'],
    [[('Training setup', True)], 'Trained with the Kaggle notebook package on a Kaggle GPU; the test set was never used for any decision. TFLite output agreed with the trained model on 100% of checked images.'],
    [[('Metrics', True)], ['Test top-1 accuracy 92.6%; top-3 98.6%; with flip averaging 92.9%. By source: Food-101 93.6% (2,093 images); Pakistani set 1 85.2% (182); Pakistani set 2 76.2% (42).',
                           'Per-class F1 ranges from 0.72 (paratha, recall 0.65) and 0.79 (aloo gobi, recall 0.65) up to 0.97 (tea with milk, french fries, cake slice); roti 0.81, butter chicken 0.83, chicken biryani 0.86 (precision 0.75), haleem 0.88.']],
    [[('Decision', True)], 'ship_recommended = False: the model failed the per-class gate on aloo gobi and paratha (recall 0.65 each), and Pakistani dishes have few photos. It is loaded only in debug/profile builds. More photos of the team\'s own dishes are needed.'],
], [1900, 7460], sz=17)
cm = os.path.join(RES, 'confusion_matrix.png')
tc = os.path.join(RES, 'training_curves.png')
if os.path.exists(tc):
    figure(tc, 'Figure 4.1 Food classifier training curves (accuracy and loss)')
if os.path.exists(cm):
    figure(cm, 'Figure 4.2 Food classifier confusion matrix on the held-out test set', width_in=5.6)

H3('Model 3: Gradient Boosting calorie model (Module 4): built, failed validation, not released')
P('A Gradient Boosting model for calories burned per session was trained on the Gym Members Exercise Dataset (Kaggle, 973 rows, 950 after cleaning). The analysis showed the data is not physiologically realistic: calories per kg-hour are about 10 for every workout type (workout type explains 0.4% of the variance), only 48% of sessions have an energy cost within 0.5-2x of the 2024 Compendium and 0 of 232 yoga sessions do, and the trained model predicts about 765 kcal for an hour of any workout type and does not learn that heavier people burn more. '
  'The training script exports a model only if it beats the MET estimate on held-out data and agrees with published energy costs within 0.5-2x for every workout type and increases with body weight; the second check failed, so no model was exported. The app uses the Compendium METs for workout energy and Algorithm 6 for the calorie target. The measured doubly-labelled-water data needed for a legitimate model is available from the IAEA by application.')

# ---------------------------------------------------------------------------------------------------------------------------------
H2('4.3 Security Techniques')
CAP('Table 4.4 Security techniques used')
table(['Area', 'Technique', 'Where'], [
    ['Authentication', 'Firebase Authentication: email/password and Google sign-in (OAuth through Firebase); the browsers and phone receive a signed ID token (a JSON Web Token). The Express API verifies every token with the Firebase Admin SDK; requests without a valid Bearer token get 401. Password reset links are generated by the server; an administrator never sets a password.', 'App; baymax-api/src/middleware/auth.js'],
    ['Authorisation (RBAC)', 'Roles member, doctor, nutritionist, trainer and admin are stored server-side in roles/{uid} and never taken from the client. The API answers 403 to a wrong role and 404 to someone else\'s record, even when the address is typed in directly. Plan changes are limited to the specialist\'s own patients, from acceptance until 30 days after the appointment, and by role (diet: doctor and nutritionist; workout: doctor and trainer; prescriptions: doctors only).', 'API; roles node'],
    ['Database security rules', 'Realtime Database rules: nothing is readable or writable by default; a member reads and writes only users/{uid}; plans, reviews, meeting links and roles are write-protected from members; a booking hold must carry the right patient id, the real fee, a hold of at most 10 minutes, a real specialist and a future time; only the two people involved can read an appointment. Field-level .validate rules reject malformed data. The rules were tested on the Firebase emulator with real signed-in test users.', 'app/database.rules.json'],
    ['Encryption', 'TLS for all traffic between app, browsers, API and Firebase; Google encrypts stored data at rest. The app does not implement its own AES layer and says only this. Card numbers and CVV are never stored or logged (test gateway only).', 'Firebase; payment_service.dart'],
    ['Attack prevention', 'Input validation on every form and on every API body (type, length and range checks, 20 kB JSON limit); only https meeting links are passed to the browser (no script injection through a link); helmet security headers with an explicit cross-origin policy; CORS limited to the web apps\' origins; rate limit of 300 requests per minute per client on /api; login lock after 5 failures for 15 minutes; Luhn check of card numbers; unguessable video room names; no SQL is used so SQL injection does not apply, and the portals render data as text to avoid XSS.', 'baymax-api/src/app.js; app validators'],
    ['Privacy and audit', 'The member chooses per item what a specialist may see (nothing by default). The data opens only after acceptance, from 30 minutes before to 60 minutes after the slot, and every opening is written to accessLog/{appointment}.', 'API; Algorithm 17'],
    ['Secrets', 'The Firebase service-account key and .env files are stored outside the project folders and git-ignored; the administrator password is generated by a script, saved to a private file with restricted permissions and never printed.', 'baymax-api/scripts'],
], [1700, 5800, 1860], sz=17)
P('No intrusion-detection or anomaly-detection model is used, so there are no results to report for one.')

# ---------------------------------------------------------------------------------------------------------------------------------
H2('4.4 External APIs/SDKs')
CAP('Table 4.5 Details of APIs and SDKs used in the project')
table(['Name of API and version', 'Description of API', 'Purpose of usage', 'Endpoint / function / class in which it is used'], [
    ['firebase_auth 6.7 (app); Firebase Authentication', 'Identity service: email/password and Google sign-in, password reset', 'Sign up, log in, session persistence, forgot password', 'services/auth_service.dart, services/auth_flow.dart'],
    ['firebase-admin 14.5 (Node)', 'Server SDK for Auth and Realtime Database', 'Verify ID tokens, create specialist and administrator accounts, generate password-reset links, delete accounts, read and write portal data', 'baymax-api: middleware/authenticate, lib/accounts.js, lib/db.js (verifyIdToken, createUser, generatePasswordResetLink, deleteUser)'],
    ['firebase_database 12.6', 'Realtime Database client', 'User profile, food log, activity, notifications, appointments, slots, saved settings', 'services/realtime_db.dart and the service classes that use it'],
    ['cloud_firestore 6.10', 'Document database', 'Shared food and exercise catalogues (cache-first, JSON fallback)', 'services/catalog_service.dart (collections foods, exercises)'],
    ['firebase (JS SDK 13.0)', 'Web client SDK', 'Sign-in in the specialist portal and admin panel; the token is sent to the Express API', 'portal and admin: src/lib/firebase.ts, src/lib/api.ts'],
    ['Google Cloud Vision API (text detection)', 'OCR', 'Read ingredient text from a label photo (needs an API key held by the Node backend)', 'services/ocr_service.dart calls /api/scan/ocr on the backend (Baymax-main)'],
    ['tflite_flutter 0.12', 'TensorFlow Lite runtime for Flutter', 'Run the food classifier on the phone', 'services/food_image_classifier.dart'],
    ['Jitsi Meet (meet.jit.si)', 'Open-source video conferencing', 'Video room for each accepted consultation; the server only builds the room link', 'baymax-api: routes/specialist.js (accept), MEETING_BASE_URL'],
    ['flutter_local_notifications 22.3, timezone 0.11', 'Local notification scheduling', 'Workout and meal reminders', 'services/notification_service.dart'],
    ['image_picker 1.2', 'Camera and gallery access', 'Pick a label or food photo', 'screens/allergy, screens/diet/food_scan_screen.dart'],
    ['Express 5.3, helmet 8.3, cors 2.8, express-rate-limit 8.7', 'Node web framework and security middleware', 'The API behind the portal and admin panel', 'baymax-api/src/app.js'],
    ['USDA FoodData Central SR Legacy, Indian Nutrient Databank, 2024 Compendium of Physical Activities', 'Published datasets (not live APIs)', 'Food calories and macros; exercise energy (MET) values', 'assets/data/foods*.json, exercises.json; Profile > Sources & methodology screen'],
], [2100, 2300, 2500, 2460], sz=16)

# ---------------------------------------------------------------------------------------------------------------------------------
H2('4.5 User Interface')
P('Screens are listed per sub-system with a short description. Insert a phone screenshot under each caption (two to four screens per page); screenshots were not taken for this draft.')
H3('Mobile App (Flutter, "aurora glass" theme)')
UI = [
    ('Splash, Login and Sign-up', 'Animated logo; email and Google login; sign-up with live validation (Create account stays disabled until every field is valid and the terms are ticked); forgot password.', 'screens/auth'),
    ('Health profile (3 steps) and BMI result', 'Personal information, medical history and allergies, goals and activity; then BMI, BMR, calorie targets and recommended actions.', 'screens/health_profiling'),
    ('Health classification', 'Category, risk level, risk factors, statistical risk from the model with the survey average, and tips.', 'health_classification.dart'),
    ('Home dashboard', 'Greeting, today\'s activity cards, today\'s workout, calories eaten, mood selector, Quick Access grid, notification bell, floating chat button, bottom navigation.', 'screens/dashboard'),
    ('Workout plan and Exercise detail', 'Week selector, exercises with sets/reps, reasons for each pick, medical notes; technique steps and muscles.', 'screens/workout_and_exercise'),
    ('Nutrition plan and Calorie target', 'Calorie and macro targets, meals by slot with kcal, foods to avoid, rotating tips; adaptive calorie estimate and weight log.', 'screens/nutrition'),
    ('Diet tracker, Food text log, Daily summary', 'Calorie ring, meals with subtotals, search dropdown, water tracker, consumed/burned/net, 7-day chart, macro donut and verdict.', 'screens/diet'),
    ('Allergy scanner and result', 'Photo of a label; alert dialog and safe/unsafe ingredient chips.', 'screens/allergy'),
    ('Community and My badges', 'Podium, level filter, weekly reset countdown, XP level, earned and locked badges with unlock rules.', 'screens/community'),
    ('AI chatbot', 'Chat with quick-reply chips; answers from the user\'s own logs; symptom and emergency replies.', 'screens/chatbot'),
    ('Notifications', 'Tabs All/Workout/Diet/Alerts, unread counts, mark all read.', 'screens/notifications'),
    ('Analytics and Body transformation', 'Calories against target with moving average, weekly score, weight trend and projection.', 'screens/analytics'),
    ('Find a specialist, Book appointment, My appointments', 'Filter and search, time and consultation type, what to share, notes; upcoming and past appointments, join, cancel, specialist notes.', 'screens/specialists'),
    ('Profile, Settings, Sources & methodology', 'Profile values, reminders and leaderboard opt-in, and the source of every number.', 'screens/profile'),
]
CAP('Table 4.6 Mobile app screens')
table(['Screen', 'Description', 'Folder / file'], [[a, b, c] for a, b, c in UI], [2300, 5200, 1860], sz=17)
H3('Specialist Web Portal (Next.js, port 3000)')
CAP('Table 4.7 Specialist portal pages')
table(['Page', 'Description'], [
    ['Login and Register', 'Specialists sign in; new specialists apply with professional details and a licence number (pending until approved).'],
    ['Dashboard', 'Greeting, four counters (consultations today, upcoming 7 days, patients, awaiting notes), new requests with Accept/Decline, today\'s sessions with Join call.'],
    ['Appointments and Appointment page', 'Filter by patient, status and date; the appointment page shows the patient\'s note, the meeting link and the shared data as a dashboard with charts; notes and prescription; complete, missed, cancel.'],
    ['My patients and Patient record', 'Patients with an accepted appointment, the specialist\'s own history, diet plan and workout plan editors, food-log review.'],
    ['Prescriptions and My profile', 'List of prescriptions written; specialty, fees, working days and hours, availability; close my account.'],
], [2600, 6760], sz=17)
H3('Administrator Panel (Next.js, port 3001)')
CAP('Table 4.8 Administrator panel pages')
table(['Page', 'Description'], [
    ['Login', 'Administrator sign-in (the account is created by a server script, never by the browser).'],
    ['Overview', 'Number of specialists by type, pending registrations and appointments by status.'],
    ['Registrations', 'Pending applications with the licence number; approve (creates the role and a verified public profile) or reject with a reason.'],
    ['Specialists', 'List by type; add a specialist (an account is created without a password and a link to choose one is shown); delete a specialist.'],
], [2600, 6760], sz=17)

# ---------------------------------------------------------------------------------------------------------------------------------
H2('4.6 Deployment')
P('Deployment environment: Firebase project baymax-148da hosts authentication, the Realtime Database and Cloud Firestore; the database security rules are deployed with the Firebase CLI. The mobile app is built with Flutter 3.41.9 (Dart 3.11) and run on an Android phone over USB (debug build; a debug APK also builds). '
  'The Express API (Node.js, Express 5.3, firebase-admin 14.5) runs on port 4000 and holds the service-account key outside the project; the specialist portal (port 3000) and the administrator panel (port 3001) are Next.js 16 / React 19 / TypeScript applications that call only the API. '
  'A small separate Node backend serves label OCR to Google Vision. Video uses the public Jitsi Meet server.')
P('Current state: the API and both web applications run on the development computer against the real Firebase project (one approved specialist and one administrator exist); they have not been deployed to a public host. Automated tests run on the Firebase Emulator Suite (Auth and Database emulators, project demo-baymax) so that tests never touch real data. '
  'For a public deployment the API needs a Node host with the service-account secret, the web apps need static or Node hosting with the Firebase web configuration, and Jitsi should be self-hosted with a TURN server.')

# =================================================================================================================================
NS = ('xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
      'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"')
sect = '<w:sectPr><w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1300" w:right="1440" w:bottom="1300" w:left="1440" w:header="600" w:footer="600" w:gutter="0"/></w:sectPr>'
document = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document %s><w:body>%s%s</w:body></w:document>' % (NS, ''.join(body), sect)
os.makedirs(OUT, exist_ok=True)
out = os.path.join(OUT, 'Baymax_Chapter4_Implementation.docx')
with zipfile.ZipFile(TEMPLATE) as tz:
    styles, numbering, fonts = tz.read('word/styles.xml'), tz.read('word/numbering.xml'), tz.read('word/fontTable.xml')
ct = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Default Extension="png" ContentType="image/png"/>'
      '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
      '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>'
      '<Override PartName="/word/numbering.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/>'
      '<Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/>'
      '<Override PartName="/word/fontTable.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.fontTable+xml"/></Types>')
rels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>'
drels = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
         '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
         '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering" Target="numbering.xml"/>'
         '<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" Target="settings.xml"/>'
         '<Relationship Id="rId4" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/fontTable" Target="fontTable.xml"/>'
         + ''.join('<Relationship Id="%s" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/%s"/>' % (rid, os.path.basename(p)) for rid, p in IMAGES) + '</Relationships>')
settings = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:settings xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:defaultTabStop w:val="720"/></w:settings>'
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
    z.writestr('[Content_Types].xml', ct)
    z.writestr('_rels/.rels', rels)
    z.writestr('word/document.xml', document)
    z.writestr('word/_rels/document.xml.rels', drels)
    z.writestr('word/styles.xml', styles)
    z.writestr('word/numbering.xml', numbering)
    z.writestr('word/fontTable.xml', fonts)
    z.writestr('word/settings.xml', settings)
    for rid, p in IMAGES:
        z.write(p, 'word/media/' + os.path.basename(p))
print('wrote', out, '| algorithms', len(ALG), '| images', len(IMAGES))
