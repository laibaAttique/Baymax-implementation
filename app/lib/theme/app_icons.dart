import 'package:flutter/material.dart';

/// Material icons for content that the catalogues (Firestore / bundled JSON) still describe with an emoji `icon` field.
/// The app never draws those emoji: it draws the icon from here, so the look stays consistent and the data stays unchanged.
class AppIcons {
  AppIcons._();

  static const _food = <String, IconData>{
    // drinks
    '🥤': Icons.local_drink_rounded, '🥛': Icons.local_drink_rounded, '🧃': Icons.local_drink_rounded,
    '🍵': Icons.emoji_food_beverage_rounded, '☕': Icons.coffee_rounded,
    // bread and flatbreads
    '🍞': Icons.bakery_dining_rounded, '🫓': Icons.bakery_dining_rounded, '🥪': Icons.lunch_dining_rounded, '🍔': Icons.lunch_dining_rounded,
    '🍕': Icons.local_pizza_rounded,
    // rice, curries, soups, noodles
    '🍚': Icons.rice_bowl_rounded, '🍛': Icons.rice_bowl_rounded, '🥘': Icons.soup_kitchen_rounded, '🍲': Icons.soup_kitchen_rounded,
    '🥣': Icons.rice_bowl_rounded, '🍜': Icons.ramen_dining_rounded, '🍝': Icons.ramen_dining_rounded, '🥟': Icons.ramen_dining_rounded,
    // protein
    '🍗': Icons.kebab_dining_rounded, '🍢': Icons.kebab_dining_rounded, '🥚': Icons.egg_alt_rounded, '🍳': Icons.egg_alt_rounded,
    '🐟': Icons.set_meal_rounded, '🍤': Icons.set_meal_rounded,
    // dairy and fats
    '🧀': Icons.bubble_chart_rounded, '🧈': Icons.bubble_chart_rounded, '🫒': Icons.water_drop_rounded,
    // nuts, vegetables, fruit
    '🥜': Icons.grain_rounded, '🥗': Icons.eco_rounded, '🥦': Icons.eco_rounded, '🥔': Icons.eco_rounded, '🍠': Icons.eco_rounded,
    '🍎': Icons.apple_rounded, '🍌': Icons.apple_rounded, '🍊': Icons.apple_rounded, '🥭': Icons.apple_rounded, '🍐': Icons.apple_rounded,
    '🍇': Icons.apple_rounded, '🍉': Icons.apple_rounded, '🍈': Icons.apple_rounded, '🍓': Icons.apple_rounded, '🥥': Icons.apple_rounded,
    '🌴': Icons.apple_rounded,
    // sweets and snacks
    '🍮': Icons.cake_rounded, '🍰': Icons.cake_rounded, '🍪': Icons.cookie_rounded, '🍫': Icons.cookie_rounded, '🍨': Icons.icecream_rounded,
    '🍟': Icons.fastfood_rounded,
  };

  /// Icon for a food whose catalogue icon is [emoji].
  static IconData food(String emoji) => _food[emoji] ?? Icons.restaurant_rounded;

  /// Icon for an exercise by its muscle [group] (push, legs, core, cardio, back, mobility).
  static IconData exercise(String group) {
    switch (group) {
      case 'push':
        return Icons.fitness_center_rounded;
      case 'back':
        return Icons.accessibility_new_rounded;
      case 'legs':
        return Icons.directions_walk_rounded;
      case 'core':
        return Icons.sports_gymnastics_rounded;
      case 'cardio':
        return Icons.directions_run_rounded;
      case 'mobility':
        return Icons.self_improvement_rounded;
      default:
        return Icons.fitness_center_rounded;
    }
  }

  /// Icon for a meal slot.
  static IconData meal(String meal) {
    switch (meal) {
      case 'Breakfast':
        return Icons.wb_twilight_rounded;
      case 'Lunch':
        return Icons.wb_sunny_rounded;
      case 'Dinner':
        return Icons.nights_stay_rounded;
      default:
        return Icons.apple_rounded;
    }
  }

  /// Icon for a badge by its id (see `gamification.dart`).
  static IconData badge(String id) {
    switch (id) {
      case 'first_workout':
        return Icons.flag_rounded;
      case 'streak_3':
        return Icons.local_fire_department_rounded;
      case 'streak_7':
        return Icons.bolt_rounded;
      case 'full_week':
        return Icons.military_tech_rounded;
      case 'logger_3':
        return Icons.restaurant_rounded;
      case 'logger_7':
        return Icons.menu_book_rounded;
      case 'on_target_3':
        return Icons.track_changes_rounded;
      case 'high_scorer':
        return Icons.star_rounded;
      case 'daily_7':
        return Icons.whatshot_rounded;
      case 'daily_30':
        return Icons.local_fire_department_rounded;
      default:
        return Icons.emoji_events_rounded;
    }
  }
}
