/// Generates mock statistics for previews
class StatsService {
  static final StatsService instance = StatsService._();
  StatsService._();

  String mockParticipants(String eventTitle) {
    // Generate consistent but varied mock participant counts based on title
    final hash = eventTitle.hashCode.abs();
    return '${50 + (hash % 200)}';
  }

  String mockCountries(String eventTitle) {
    // Generate consistent but varied mock country counts
    final hash = eventTitle.hashCode.abs();
    return '${5 + (hash % 45)}';
  }
}
