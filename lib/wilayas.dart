import 'package:flutter/material.dart';
import 'l10n.dart';

// ---------------- The 58 wilayas of Algeria ----------------
// The ONE list used everywhere a wilaya is chosen. It must stay exactly the
// same as is_valid_wilaya() in sql/2026-11-05-01-roles.sql.
// A wilaya is always chosen from this list, never typed.

const List<String> kWilayas = [
  '01 - Adrar', '02 - Chlef', '03 - Laghouat', '04 - Oum El Bouaghi',
  '05 - Batna', '06 - Béjaïa', '07 - Biskra', '08 - Béchar',
  '09 - Blida', '10 - Bouira', '11 - Tamanrasset', '12 - Tébessa',
  '13 - Tlemcen', '14 - Tiaret', '15 - Tizi Ouzou', '16 - Alger',
  '17 - Djelfa', '18 - Jijel', '19 - Sétif', '20 - Saïda',
  '21 - Skikda', '22 - Sidi Bel Abbès', '23 - Annaba', '24 - Guelma',
  '25 - Constantine', '26 - Médéa', '27 - Mostaganem', "28 - M'Sila",
  '29 - Mascara', '30 - Ouargla', '31 - Oran', '32 - El Bayadh',
  '33 - Illizi', '34 - Bordj Bou Arréridj', '35 - Boumerdès', '36 - El Tarf',
  '37 - Tindouf', '38 - Tissemsilt', '39 - El Oued', '40 - Khenchela',
  '41 - Souk Ahras', '42 - Tipaza', '43 - Mila', '44 - Aïn Defla',
  '45 - Naâma', '46 - Aïn Témouchent', '47 - Ghardaïa', '48 - Relizane',
  '49 - Timimoun', '50 - Bordj Badji Mokhtar', '51 - Ouled Djellal', '52 - Béni Abbès',
  '53 - In Salah', '54 - In Guezzam', '55 - Touggourt', '56 - Djanet',
  "57 - El M'Ghair", '58 - El Meniaa',
];

// The saved value if it is one of the 58, otherwise null (= not chosen).
String? validWilaya(dynamic value) {
  final v = value?.toString();
  return kWilayas.contains(v) ? v : null;
}

// A dropdown with the 58 wilayas. With allowAll, the first item is "All"
// (value null), for filters.
class WilayaDropdown extends StatelessWidget {
  final String? value;
  final ValueChanged<String?>? onChanged;
  final String? label;
  final bool allowAll;
  final List<String> choices;

  const WilayaDropdown({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
    this.allowAll = false,
    this.choices = kWilayas,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String?>(
      // The key makes the field show a new value set from outside.
      key: ValueKey(value),
      initialValue: choices.contains(value) ? value : null,
      isExpanded: true,
      decoration: InputDecoration(labelText: label ?? tr('Wilaya')),
      items: [
        if (allowAll)
          DropdownMenuItem<String?>(value: null, child: Text(tr('All wilayas'))),
        for (final w in choices)
          DropdownMenuItem<String?>(value: w, child: Text(w)),
      ],
      onChanged: onChanged,
    );
  }
}

// Academic years like "2025-2026": from 6 years ago to next year.
List<String> academicYearChoices() {
  final now = DateTime.now();
  // A new academic year starts in September.
  final current = now.month >= 9 ? now.year : now.year - 1;
  return [
    for (var y = current + 1; y >= current - 6; y--) '$y-${y + 1}',
  ];
}

String currentAcademicYear() => academicYearChoices()[1];
