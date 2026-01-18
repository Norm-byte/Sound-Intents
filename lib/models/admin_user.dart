class AdminUser {
  final String uid;
  final String email;
  final String displayName;
  final String role; // 'super-admin' or 'admin'
  final bool isActive;
  final DateTime createdAt;
  final DateTime? lastLogin;
  final DateTime? lastActive;
  final List<String>? permissions;

  AdminUser({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.role,
    this.isActive = true,
    required this.createdAt,
    this.lastLogin,
    this.lastActive,
    this.permissions,
  });

  bool get isSuperAdmin => role == 'super-admin';

  Map<String, dynamic> toJson() {
    return {
      'uid': uid,
      'email': email,
      'displayName': displayName,
      'role': role,
      'isActive': isActive,
      'createdAt': createdAt.toIso8601String(),
      'lastLogin': lastLogin?.toIso8601String(),
      'lastActive': lastActive?.toIso8601String(),
      'permissions': permissions,
    };
  }

  factory AdminUser.fromJson(Map<String, dynamic> json) {
    return AdminUser(
      uid: json['uid'] as String,
      email: json['email'] as String,
      displayName: json['displayName'] as String,
      role: json['role'] as String,
      isActive: json['isActive'] as bool? ?? true,
      createdAt: DateTime.parse(json['createdAt'] as String),
      lastLogin: json['lastLogin'] != null 
          ? DateTime.parse(json['lastLogin'] as String)
          : null,
      lastActive: json['lastActive'] != null 
          ? DateTime.parse(json['lastActive'] as String)
          : null,
      permissions: (json['permissions'] as List<dynamic>?)?.map((e) => e.toString()).toList(),
    );
  }

  AdminUser copyWith({
    String? displayName,
    String? role,
    bool? isActive,
    DateTime? lastLogin,
    DateTime? lastActive,
  }) {
    return AdminUser(
      uid: uid,
      email: email,
      displayName: displayName ?? this.displayName,
      role: role ?? this.role,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
      lastLogin: lastLogin ?? this.lastLogin,
      lastActive: lastActive ?? this.lastActive,
    );
  }
}
