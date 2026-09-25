import 'package:flutter/foundation.dart';
import '../core/constants/relationship_constants.dart';

enum CallActionStatus {
  patchedToMaster,
  heldAndDeferred,
  secretaryResolved,
  declinedSpam,
}

extension CallActionStatusExtension on CallActionStatus {
  String get label {
    switch (this) {
      case CallActionStatus.patchedToMaster:
        return 'You talked';
      case CallActionStatus.heldAndDeferred:
        return 'Ended by you';
      case CallActionStatus.secretaryResolved:
        return 'Handled by secretary';
      case CallActionStatus.declinedSpam:
        return 'Spam';
    }
  }
}

class TranscriptEntry {
  final String speaker; // 'Caller' or 'Secretary' or 'Master'
  final String text;
  final String timeOffset;

  TranscriptEntry({
    required this.speaker,
    required this.text,
    required this.timeOffset,
  });

  Map<String, dynamic> toJson() => {
        'speaker': speaker,
        'text': text,
        'timeOffset': timeOffset,
      };

  factory TranscriptEntry.fromJson(Map<String, dynamic> json) => TranscriptEntry(
        speaker: json['speaker'] as String,
        text: json['text'] as String,
        timeOffset: json['timeOffset'] as String,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TranscriptEntry &&
          runtimeType == other.runtimeType &&
          speaker == other.speaker &&
          text == other.text &&
          timeOffset == other.timeOffset;

  @override
  int get hashCode => speaker.hashCode ^ text.hashCode ^ timeOffset.hashCode;
}

class CallRecordModel {
  final String id;
  final String callerName;
  final String phoneNumber;
  final RelationshipCategory relationship;
  final DateTime timestamp;
  final int durationSeconds;
  final double sentimentScore; // -1.0 to 1.0 (AssemblyAI Sentiment)
  final String lemurSummary; // 1-sentence AssemblyAI LeMUR summary
  final List<TranscriptEntry> transcript;
  final CallActionStatus actionStatus;
  final String? extractedActionItem;
  // How to reach the caller, as they confirmed it to the secretary
  final String? callbackNumber;
  final String? callbackEmail;
  final String? bestTime;
  final String? callerMessage;
  // The caller page's anonymous browser id, to recognise (or block) a repeat caller
  final String? deviceId;
  // 'verified' | 'recognised' | 'unverified' | 'warning', and why
  final String? trust;
  final String? trustNote;

  CallRecordModel({
    required this.id,
    required this.callerName,
    required this.phoneNumber,
    required this.relationship,
    required this.timestamp,
    required this.durationSeconds,
    required this.sentimentScore,
    required this.lemurSummary,
    required this.transcript,
    required this.actionStatus,
    this.extractedActionItem,
    this.callbackNumber,
    this.callbackEmail,
    this.bestTime,
    this.callerMessage,
    this.deviceId,
    this.trust,
    this.trustNote,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'callerName': callerName,
      'phoneNumber': phoneNumber,
      'relationship': relationship.name,
      'timestamp': timestamp.toIso8601String(),
      'durationSeconds': durationSeconds,
      'sentimentScore': sentimentScore,
      'lemurSummary': lemurSummary,
      'transcript': transcript.map((e) => e.toJson()).toList(),
      'actionStatus': actionStatus.name,
      'extractedActionItem': extractedActionItem,
      'callbackNumber': callbackNumber,
      'callbackEmail': callbackEmail,
      'bestTime': bestTime,
      'callerMessage': callerMessage,
      'deviceId': deviceId,
      'trust': trust,
      'trustNote': trustNote,
    };
  }

  factory CallRecordModel.fromJson(Map<String, dynamic> json) {
    return CallRecordModel(
      id: json['id'] as String,
      callerName: json['callerName'] as String,
      phoneNumber: json['phoneNumber'] as String,
      relationship: RelationshipCategory.values.firstWhere(
        (e) => e.name == json['relationship'],
        orElse: () => RelationshipCategory.unknown,
      ),
      timestamp: DateTime.parse(json['timestamp'] as String),
      durationSeconds: json['durationSeconds'] as int,
      sentimentScore: (json['sentimentScore'] as num).toDouble(),
      lemurSummary: json['lemurSummary'] as String,
      transcript: (json['transcript'] as List)
          .map((e) => TranscriptEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
      actionStatus: CallActionStatus.values.firstWhere(
        (e) => e.name == json['actionStatus'],
        orElse: () => CallActionStatus.secretaryResolved,
      ),
      extractedActionItem: json['extractedActionItem'] as String?,
      callbackNumber: json['callbackNumber'] as String?,
      callbackEmail: json['callbackEmail'] as String?,
      bestTime: json['bestTime'] as String?,
      callerMessage: json['callerMessage'] as String?,
      deviceId: json['deviceId'] as String?,
      trust: json['trust'] as String?,
      trustNote: json['trustNote'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CallRecordModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          callerName == other.callerName &&
          phoneNumber == other.phoneNumber &&
          relationship == other.relationship &&
          timestamp == other.timestamp &&
          durationSeconds == other.durationSeconds &&
          sentimentScore == other.sentimentScore &&
          lemurSummary == other.lemurSummary &&
          listEquals(transcript, other.transcript) &&
          actionStatus == other.actionStatus &&
          extractedActionItem == other.extractedActionItem;

  @override
  int get hashCode => Object.hash(
        id,
        callerName,
        phoneNumber,
        relationship,
        timestamp,
        durationSeconds,
        sentimentScore,
        lemurSummary,
        Object.hashAll(transcript),
        actionStatus,
        extractedActionItem,
      );
}
