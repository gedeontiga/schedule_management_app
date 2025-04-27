class PermutationRequest {
  final String id;
  final String senderId;
  final String receiverId;
  final String scheduleId;
  final String senderDay;
  final String receiverDay;
  final String status; // "pending", "accepted", "rejected"

  PermutationRequest({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.scheduleId,
    required this.senderDay,
    required this.receiverDay,
    this.status = 'pending',
  });

  factory PermutationRequest.fromJson(Map<String, dynamic> json) {
    return PermutationRequest(
      id: json['id'],
      senderId: json['sender_id'],
      receiverId: json['receiver_id'],
      scheduleId: json['schedule_id'],
      senderDay: json['sender_day'],
      receiverDay: json['receiver_day'],
      status: json['status'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sender_id': senderId,
      'receiver_id': receiverId,
      'schedule_id': scheduleId,
      'sender_day': senderDay,
      'receiver_day': receiverDay,
      'status': status,
    };
  }
}
