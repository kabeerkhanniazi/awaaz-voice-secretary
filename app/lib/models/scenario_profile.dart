import '../core/constants/relationship_constants.dart';

class ScenarioProfile {
  final String title;
  final String callerName;
  final String phoneNumber;
  final RelationshipCategory relationship;
  final String dialogOpening;
  final String dialogueIntent;
  final double sentimentScore;
  final String lemurSummary;
  final String extractedActionItem;
  final String recommendedResponse;

  ScenarioProfile({
    required this.title,
    required this.callerName,
    required this.phoneNumber,
    required this.relationship,
    required this.dialogOpening,
    required this.dialogueIntent,
    required this.sentimentScore,
    required this.lemurSummary,
    required this.extractedActionItem,
    required this.recommendedResponse,
  });
}
