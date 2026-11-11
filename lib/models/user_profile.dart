class UserProfile {
  const UserProfile({
    required this.uid,
    required this.name,
    required this.email,
    required this.phone,
    required this.avatar,
  });

  final String uid;
  final String name;
  final String email;
  final String phone;
  final String avatar;

  factory UserProfile.fromFirestore(
    Map<String, dynamic>? data, {
    required String uid,
    String? fallbackName,
    String? fallbackEmail,
  }) {
    return UserProfile(
      uid: uid,
      name: data?['name']?.toString() ?? fallbackName ?? 'User',
      email: data?['email']?.toString() ?? fallbackEmail ?? '',
      phone: data?['phone']?.toString() ?? '',
      avatar: data?['avatar']?.toString() ?? 'assets/avatars/avatar_hoodie.jpg',
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'phone': phone,
      'avatar': avatar,
    };
  }

  UserProfile copyWith({
    String? name,
    String? phone,
    String? avatar,
  }) {
    return UserProfile(
      uid: uid,
      name: name ?? this.name,
      email: email,
      phone: phone ?? this.phone,
      avatar: avatar ?? this.avatar,
    );
  }
}
