class Role {
  final String name;

  Role({required this.name});

  Map<String, dynamic> toJson() => {'name': name};

  factory Role.fromJson(Map<String, dynamic> json) => Role(name: json['name']);
}
