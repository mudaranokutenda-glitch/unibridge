import 'package:flutter/material.dart';
import 'config.dart';

// ---------------- My role (student, rep, attache, admin) ----------------
// Only decides which buttons and screens the app shows. The real security
// is in the database rules (RLS) and the Edge Functions.

class MyRole {
  final String role;
  final String? repWilaya;
  const MyRole(this.role, this.repWilaya);

  bool get isStaff => role == 'attache' || role == 'admin';
  bool get isAdmin => role == 'admin';
  bool get isRep => role == 'rep' && repWilaya != null;
  // Can open the students list (staff: all wilayas, rep: their own).
  bool get canSeeStudents => isStaff || isRep;

  static const student = MyRole('student', null);
}

Future<MyRole> loadMyRole() async {
  try {
    final data = await supabase.rpc('my_role');
    final rows = List<Map<String, dynamic>>.from(data as List);
    if (rows.isEmpty) return MyRole.student;
    return MyRole(
      (rows.first['role'] ?? 'student').toString(),
      rows.first['rep_wilaya']?.toString(),
    );
  } catch (e) {
    // Before the roles SQL is run, everyone is simply a student.
    debugPrint('Could not load role: $e');
    return MyRole.student;
  }
}
