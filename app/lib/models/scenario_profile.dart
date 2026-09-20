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

  static List<ScenarioProfile> get presets => [
        ScenarioProfile(
          title: '❤️ Spouse Call (Informal)',
          callerName: 'Sarah Jenkins (Wife)',
          phoneNumber: '+1 (555) 234-5678',
          relationship: RelationshipCategory.spouse,
          dialogOpening: "Hey! Just wanted to see if you'll be home in time for dinner tonight?",
          dialogueIntent: "Checking dinner timeline and asking if he needs groceries picked up.",
          sentimentScore: 0.85,
          lemurSummary: "Spouse checking dinner arrival time and grocery pickup needs.",
          extractedActionItem: "Confirm dinner ETA with Sarah & grab milk on way home.",
          recommendedResponse: "Informal: Tell her he's wrapping up a meeting and will call back in 15 mins.",
        ),
        ScenarioProfile(
          title: '🚨 Child\'s School Emergency',
          callerName: 'St. Jude School (Principal)',
          phoneNumber: '+1 (555) 911-0421',
          relationship: RelationshipCategory.family,
          dialogOpening: "Hello, this is Principal Davis. Your daughter Emma hurt her ankle on the playground.",
          dialogueIntent: "Immediate emergency notification regarding child injury.",
          sentimentScore: -0.60,
          lemurSummary: "Emergency: Daughter injured ankle at St. Jude School playground.",
          extractedActionItem: "Urgent: Pick up Emma from school nurse office.",
          recommendedResponse: "Emergency Override: Patch call through immediately.",
        ),
        ScenarioProfile(
          title: '💼 Enterprise VIP Client',
          callerName: 'Marcus Vance (C-Level Client)',
          phoneNumber: '+1 (555) 789-0123',
          relationship: RelationshipCategory.vipClient,
          dialogOpening: "Good afternoon. We are looking to expand our contract scope by \$200,000 for Q4.",
          dialogueIntent: "High-value enterprise contract expansion negotiation.",
          sentimentScore: 0.90,
          lemurSummary: "Enterprise VIP Client proposing \$200,000 contract scope expansion for Q4.",
          extractedActionItem: "Send updated Q4 scope proposal deck to Marcus Vance.",
          recommendedResponse: "Formal: High priority escalation & warm introduction patch-through.",
        ),
        ScenarioProfile(
          title: '⛔ Cold Sales Prospecting Pitch',
          callerName: 'CloudMetrics Solutions',
          phoneNumber: '+1 (800) 456-7890',
          relationship: RelationshipCategory.unknown,
          dialogOpening: "Hi there! I'm calling from CloudMetrics to offer a revolutionary analytics platform...",
          dialogueIntent: "Unsolicited commercial software sales pitch.",
          sentimentScore: 0.10,
          lemurSummary: "Unsolicited cold sales pitch from CloudMetrics vendor.",
          extractedActionItem: "Logged to spam ledger.",
          recommendedResponse: "Formal Gatekeeping: Decline politely and direct to email info deck.",
        ),
        ScenarioProfile(
          title: '⚡ Tech Partner CTO (API Outage)',
          callerName: 'David Chen (CTO, Apex Partner)',
          phoneNumber: '+1 (555) 345-6789',
          relationship: RelationshipCategory.vendor,
          dialogOpening: "Hi, production API is throwing 500 errors on our integration right now!",
          dialogueIntent: "Critical system outage inquiry requiring immediate technical sync.",
          sentimentScore: -0.75,
          lemurSummary: "Critical System Alert: Production API throwing 500 errors on Apex integration.",
          extractedActionItem: "Investigate 500 server errors on Apex integration endpoint.",
          recommendedResponse: "Urgent Technical Patch: Hold 30 seconds while Master opens laptop.",
        ),
      ];
}
