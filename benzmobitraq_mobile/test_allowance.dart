import 'dart:io';
import 'lib/data/models/employee_model.dart';
import 'lib/data/models/travel_allowance_model.dart';

void main() {
  final executiveGrade = EmployeeGrade.executive;

  print('--- Testing Fallback Limits ---');
  final fallbackCarRate = TravelAllowanceLimits.getFuelRatePerKm(executiveGrade);
  final fallbackBikeRate = TravelAllowanceLimits.getBikeRatePerKm(executiveGrade);
  final fallbackFood = TravelAllowanceLimits.getFoodDailyLimit(executiveGrade);

  print('Fallback Car Rate: ₹$fallbackCarRate/km');
  print('Fallback Bike Rate: ₹$fallbackBikeRate/km');
  print('Fallback Food: ₹$fallbackFood/day');

  assert(fallbackCarRate == 7.5);
  assert(fallbackBikeRate == 5.0);
  assert(fallbackFood == 600.0);

  print('\n--- Testing Custom Employee Limits ---');
  final employee = EmployeeModel(
    id: 'test',
    name: 'Test',
    role: 'executive',
    isActive: true,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
    carRatePerKm: 10.0,
    bikeRatePerKm: 7.0,
    dailyAllowance: 1200.0,
  );

  final customFood = TravelAllowanceLimits.getLimitForCategory(grade: executiveGrade, category: 'food_da', employee: employee);
  print('Custom Food: ₹$customFood/day');
  assert(customFood == 1200.0);

  print('\n--- Testing App Logic Equivalents ---');
  double effectiveCarRate = ((employee.carRatePerKm ?? 0) > 0) ? employee.carRatePerKm! : fallbackCarRate;
  double effectiveBikeRate = ((employee.bikeRatePerKm ?? 0) > 0) ? employee.bikeRatePerKm! : fallbackBikeRate;

  print('Effective Car Rate: ₹$effectiveCarRate/km');
  print('Effective Bike Rate: ₹$effectiveBikeRate/km');
  assert(effectiveCarRate == 10.0);
  assert(effectiveBikeRate == 7.0);

  print('\n✅ All tests passed.');
}
