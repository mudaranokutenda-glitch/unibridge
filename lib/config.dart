import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const String supabaseUrl = 'https://lhdkzcsaqlhswyytirxb.supabase.co';

// The anon key is public by design (it is safe inside the app).
const String supabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImxoZGt6Y3NhcWxoc3d5eXRpcnhiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODgwMjE2OTEsImV4cCI6MjEwMzU5NzY5MX0._ITsT0ZoXeWfZRJX-OdRBlktvKVsozAHhd6IsnCLTtw';

final supabase = Supabase.instance.client;

const String googleWebClientId =
    '446026136458-6b9o3prsfjcgttf58am8cdkch2b4ghri.apps.googleusercontent.com';

// Grey for secondary text. Readable in both light and dark mode.
const Color kMutedText = Color(0xFF8A8A8A);

// See-through grey for empty photo boxes. Works in light and dark mode.
const Color kPlaceholderBg = Color(0x22888888);
