enum RelationshipCategory {
  spouse,
  family,
  closeFriend,
  vipClient,
  vendor,
  unknown,
}

extension RelationshipCategoryExtension on RelationshipCategory {
  String get displayName {
    switch (this) {
      case RelationshipCategory.spouse:
        return 'Spouse';
      case RelationshipCategory.family:
        return 'Family';
      case RelationshipCategory.closeFriend:
        return 'Close friend';
      case RelationshipCategory.vipClient:
        return 'Important client';
      case RelationshipCategory.vendor:
        return 'Business';
      case RelationshipCategory.unknown:
        return 'Other';
    }
  }

  bool get isInformal {
    return this == RelationshipCategory.spouse ||
        this == RelationshipCategory.family ||
        this == RelationshipCategory.closeFriend;
  }
}
