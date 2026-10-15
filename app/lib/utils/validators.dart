import 'health_calc.dart';

/// Input rules from the scope document (Module 1 mockups M2 and M3, Module 2 mockups M4 and M6). Pure functions: each returns null when
/// the value is fine, or the message to show next to the field.
class Validators {
  Validators._();

  /// M2 / FR2.1: at least 2 characters, letters only (spaces, apostrophes, hyphens and dots allowed inside a name).
  static String? fullName(String v) {
    final t = v.trim();
    if (t.isEmpty) return 'Enter your full name.';
    if (t.length < 2) return 'Your name needs at least 2 characters.';
    if (!RegExp(r"^\p{L}[\p{L} .'\-]*$", unicode: true).hasMatch(t)) return 'Use letters only, with no numbers or symbols.';
    return null;
  }

  /// M2 / FR2.2 and M3 / FR3.1: name@domain.com. (Whether it is already registered is decided by the server when the account is created.)
  static String? email(String v) {
    final t = v.trim();
    if (t.isEmpty) return 'Enter your email address.';
    if (!RegExp(r'^[A-Za-z0-9._%+\-]+@[A-Za-z0-9\-]+(\.[A-Za-z0-9\-]+)*\.[A-Za-z]{2,}$').hasMatch(t)) return 'Enter an email like name@example.com.';
    return null;
  }

  /// M2 / FR2.3: at least 8 characters with an uppercase letter, a number and a symbol.
  static String? password(String v) {
    if (v.length < 8) return 'Use at least 8 characters.';
    if (!RegExp(r'[A-Z]').hasMatch(v)) return 'Add an uppercase letter.';
    if (!RegExp(r'[0-9]').hasMatch(v)) return 'Add a number.';
    if (!RegExp(r'[^A-Za-z0-9]').hasMatch(v)) return 'Add a symbol such as ! or @.';
    return null;
  }

  static String? confirmPassword(String password, String confirm) {
    if (confirm.isEmpty) return 'Re-enter your password.';
    return password == confirm ? null : 'The two passwords do not match.';
  }

  /// M4 / FR4.3: at least 13 years old on [now].
  static String? dateOfBirth(DateTime? dob, {DateTime? now}) {
    if (dob == null) return 'Select your date of birth.';
    final today = now ?? DateTime.now();
    var age = today.year - dob.year;
    if (today.month < dob.month || (today.month == dob.month && today.day < dob.day)) age--;
    if (age < 13) return 'You must be at least 13 years old.';
    if (age > 110) return 'Check your date of birth.';
    return null;
  }

  /// M4 / FR4.5: height between 50 cm and 300 cm (in the unit the user chose).
  static String? height(String v, String unit) {
    final n = double.tryParse(v.trim());
    if (n == null) return 'Enter your height as a number.';
    final cm = HealthCalc.toCm(n, unit);
    if (cm < 50 || cm > 300) return unit == 'ft' ? 'Height must be between 1.6 and 9.8 ft.' : 'Height must be between 50 and 300 cm.';
    return null;
  }

  /// M4 / FR4.6: weight between 20 kg and 500 kg (in the unit the user chose).
  static String? weight(String v, String unit) {
    final n = double.tryParse(v.trim());
    if (n == null) return 'Enter your weight as a number.';
    final kg = HealthCalc.toKg(n, unit);
    if (kg < 20 || kg > 500) return unit == 'lbs' ? 'Weight must be between 44 and 1,100 lbs.' : 'Weight must be between 20 and 500 kg.';
    return null;
  }

  /// M6 / FR6.4: a target weight "within a clinically reasonable range relative to the current weight". The scope gives no numbers, so this
  /// is a team choice: the target must give a BMI between 18.5 and 30, unless it is within 15% of the current weight (so someone far from the
  /// healthy range is not blocked from a first, realistic step). Empty is allowed (the field is optional).
  static String? targetWeight(String v, String unit, {required double currentKg, required double heightCm}) {
    final t = v.trim();
    if (t.isEmpty) return null;
    final n = double.tryParse(t);
    if (n == null) return 'Enter your target weight as a number.';
    final kg = HealthCalc.toKg(n, unit);
    if (kg < 20 || kg > 500) return 'Enter a realistic target weight.';
    if (currentKg > 0 && (kg - currentKg).abs() / currentKg <= 0.15) return null;
    final bmi = HealthCalc.bmi(kg, heightCm);
    if (bmi > 0 && (bmi < 18.5 || bmi > 30)) {
      return bmi < 18.5 ? 'That target would be underweight for your height. Choose a healthier goal.' : 'That is a long way from your current weight. Pick a nearer first target.';
    }
    return null;
  }
}
