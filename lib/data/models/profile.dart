class Profile {
  final String id; // matches auth.users.id
  final String fullName;
  final String email;
  final String? mobileNumber;
  final String? district;
  final bool isAdmin;
  final DateTime createdAt;

  const Profile({
    required this.id,
    required this.fullName,
    required this.email,
    this.mobileNumber,
    this.district,
    required this.isAdmin,
    required this.createdAt,
  });

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
        id: json['id'] as String,
        fullName: json['full_name'] as String? ?? '',
        email: json['email'] as String? ?? '',
        mobileNumber: json['mobile_number'] as String?,
        district: json['district'] as String?,
        isAdmin: json['is_admin'] as bool? ?? false,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'full_name': fullName,
        'email': email,
        'mobile_number': mobileNumber,
        'district': district,
        'is_admin': isAdmin,
        'created_at': createdAt.toIso8601String(),
      };
}
