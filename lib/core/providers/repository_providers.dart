import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/bookmark_repository.dart';
import '../../data/repositories/paper_repository.dart';
import '../../data/repositories/phase_repository.dart';
import '../../data/repositories/practice_repository.dart';
import '../../data/repositories/profile_repository.dart';
import '../../data/repositories/progress_repository.dart';
import '../../data/repositories/search_repository.dart';
import '../../data/repositories/subject_repository.dart';
import '../services/connectivity_service.dart';

final authRepositoryProvider = Provider((ref) => AuthRepository());
final profileRepositoryProvider = Provider((ref) => ProfileRepository());
final phaseRepositoryProvider = Provider((ref) => PhaseRepository());
final subjectRepositoryProvider = Provider((ref) => SubjectRepository());
final paperRepositoryProvider = Provider((ref) => PaperRepository());
final bookmarkRepositoryProvider = Provider((ref) => BookmarkRepository());
final practiceRepositoryProvider = Provider((ref) => PracticeRepository());
final progressRepositoryProvider = Provider((ref) => ProgressRepository());
final searchRepositoryProvider = Provider((ref) => SearchRepository());
final connectivityServiceProvider = Provider((ref) => ConnectivityService());
